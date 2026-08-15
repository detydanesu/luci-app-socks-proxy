'use strict';
'require view';
'require form';
'require fs';
'require uci';

return view.extend({
	load: function() {
		return uci.load('socks-proxy');
	},

	parseProbeOutput: function(output) {
		var values = {};
		(output || '').trim().split(/\n/).forEach(function(line) {
			var p = line.indexOf('=');
			if (p > -1)
				values[line.substring(0, p)] = line.substring(p + 1);
		});
		return values;
	},

	handleNodeProbe: function(section, button, output) {
		button.disabled = true;
		button.setAttribute('aria-busy', 'true');
		output.style.color = '';
		output.textContent = _('检测中…');

		return fs.exec('/usr/libexec/socks-proxy/check', [ 'node', section ]).then(L.bind(function(res) {
			var values = this.parseProbeOutput(res.stdout);
			var success = values.ok === '1';
			var parts = [ success ? _('可用') : _('不可用') ];

			if (values.latency_ms)
				parts.push(values.latency_ms + ' ms');
			if (values.http_code)
				parts.push('HTTP ' + values.http_code);
			if (values.message)
				parts.push(values.message);

			output.style.color = success ? '#16a34a' : '#dc2626';
			output.textContent = parts.join(' · ');
		}, this)).catch(function(err) {
			output.style.color = '#dc2626';
			output.textContent = _('检测执行失败：') + (err.message || err);
		}).finally(function() {
			button.disabled = false;
			button.removeAttribute('aria-busy');
		});
	},

	addNodeAvailability: function(root) {
		var container = root && root.querySelector ? root : document;
		var table = container.querySelector('#cbi-socks-proxy-node');
		var tbody = table && table.querySelector('tbody.cbi-section-tbody');
		if (!tbody)
			return;

		var view = this;
		Array.prototype.slice.call(
			tbody.querySelectorAll('tr.cbi-section-table-row[data-sid]')
		).forEach(function(row) {
			if (row.querySelector('.socks-proxy-node-availability'))
				return;

			var section = row.getAttribute('data-sid');
			var nameCell = row.children[1] || row.lastElementChild;
			if (!nameCell || !section)
				return;

			var output = E('span', {
				'class': 'socks-proxy-node-availability-result'
			}, _('尚未检测'));
			var button = E('button', {
				'type': 'button',
				'class': 'btn cbi-button-action cbi-button-small',
				'style': 'margin-left:0.5em;',
				'title': _('通过该节点访问检测地址')
			}, _('检测'));

			button.addEventListener('click', function(ev) {
				ev.preventDefault();
				ev.stopPropagation();
				return view.handleNodeProbe(section, button, output);
			});

			nameCell.appendChild(E('div', {
				'class': 'socks-proxy-node-availability',
				'style': 'margin-top:0.35em;display:flex;align-items:center;flex-wrap:wrap;gap:0.25em;'
			}, [
				E('span', { 'class': 'socks-proxy-node-availability-label' }, _('可用性：')),
				output,
				button
			]));
		});
	},

	groupRows: function(root) {
		/*
		 * Map.renderContents() is not the only path that can create this table:
		 * recent LuCI versions rebuild it after save, reset, and dependency
		 * updates. Accept the returned map element when available and fall back
		 * to the document so the grouping also works after those rebuilds.
		 */
		var container = root && root.querySelector ? root : document;
		var table = container.querySelector('#cbi-socks-proxy-node');
		var tbody = table && table.querySelector('tbody.cbi-section-tbody');
		if (!tbody)
			return root;

		var rows = Array.prototype.slice.call(
			tbody.querySelectorAll('tr.cbi-section-table-row[data-sid]')
		);
		if (!rows.length) {
			this.addNodeAvailability(root);
			return root;
		}
		if (tbody.querySelector('tr.cbi-section-table-group')) {
			this.addNodeAvailability(root);
			return root;
		}

		var nodesById = {};
		uci.sections('socks-proxy', 'node').forEach(function(node) {
			nodesById[node['.name']] = node;
		});

		var subscriptionsById = {};
		var subscriptionsByKey = {};
		var subscriptionList = uci.sections('socks-proxy', 'subscription');
		subscriptionList.forEach(function(subscription) {
			subscriptionsById[subscription['.name']] = subscription;
			if (subscription.source_key)
				subscriptionsByKey[subscription.source_key] = subscription;
			if (subscription.url)
				subscriptionsByKey[subscription.url] = subscription;
		});

		/*
		 * Older imports stored the anonymous UCI section ID in source. Those IDs
		 * can change after a commit, so associate an orphaned source with an
		 * otherwise unclaimed subscription when possible. New imports use the
		 * persistent source_key below and do not need this compatibility path.
		 */
		var sourceOrder = [];
		var sourceSeen = {};
		rows.forEach(function(row) {
			var node = nodesById[row.getAttribute('data-sid')] || {};
			var source = node.source || '';
			if (source.indexOf('subscription:') !== 0)
				return;
			var key = source.substr('subscription:'.length);
			if (!sourceSeen[key]) {
				sourceSeen[key] = true;
				sourceOrder.push(key);
			}
		});

		var claimedSubscriptions = {};
		sourceOrder.forEach(function(key) {
			var subscription = subscriptionsById[key] || subscriptionsByKey[key];
			if (subscription)
				claimedSubscriptions[subscription['.name']] = true;
		});

		var unclaimedSubscriptions = subscriptionList.filter(function(subscription) {
			return !claimedSubscriptions[subscription['.name']];
		});
		var legacySubscriptions = {};
		sourceOrder.forEach(function(key) {
			if (subscriptionsById[key] || subscriptionsByKey[key] || !unclaimedSubscriptions.length)
				return;
			legacySubscriptions[key] = unclaimedSubscriptions.shift();
		});

		var groups = {};
		var order = [];
		var getInfo = function(source) {
			if (source && source.indexOf('subscription:') === 0) {
				var source_key = source.substr('subscription:'.length);
				var subscription = subscriptionsById[source_key] ||
					subscriptionsByKey[source_key] || legacySubscriptions[source_key] || {};
				var name = subscription.name || source_key;
				var url = subscription.url || '';
				return {
					key: url || subscription.source_key || source,
					title: _('订阅') + '：' + (name || source_key),
					detail: this.maskUrl(url)
				};
			}

			return {
				key: source || 'manual-import',
				title: _('手动导入'),
				detail: ''
			};
		}.bind(this);

		rows.forEach(function(row) {
			var sid = row.getAttribute('data-sid');
			var node = nodesById[sid] || {};
			var source = node.source || uci.get('socks-proxy', sid, 'source') || '';
			var info = getInfo(source);
			var key = 'group:' + info.key;
			if (!groups[key]) {
				groups[key] = { info: info, rows: [] };
				order.push(key);
			}
			groups[key].rows.push(row);
			row.style.display = 'none';
			row.setAttribute('data-socks-proxy-group', key);
		});

		rows.forEach(function(row) {
			if (row.parentNode === tbody)
				tbody.removeChild(row);
		});

		var titleRow = table.querySelector('thead tr.cbi-section-table-titles');
		var colspan = titleRow ? titleRow.children.length : 1;
		order.forEach(function(key) {
			var group = groups[key];
			var cell = E('td', {
				'class': 'td cbi-section-table-group-cell',
				'colspan': colspan,
				'style': 'padding:0.65em 1em;background:var(--background-color-high);'
			});
			var button = E('button', {
				'type': 'button',
				'class': 'btn cbi-button cbi-button-neutral',
				'aria-expanded': 'false',
				'style': 'width:100%;text-align:left;display:flex;align-items:center;justify-content:space-between;',
				'title': group.info.detail || group.info.title
			}, [
				E('span', {}, group.info.title + (group.info.detail ? ' · ' + group.info.detail : '')),
				E('span', {'class': 'cbi-section-table-group-count'},
					'(' + group.rows.length + ' ' + _('个节点') + ') ▸')
			]);

			button.addEventListener('click', function() {
				var expanded = button.getAttribute('aria-expanded') === 'true';
				expanded = !expanded;
				button.setAttribute('aria-expanded', expanded ? 'true' : 'false');
				button.lastElementChild.textContent = '(' + group.rows.length + ' ' + _('个节点') + ') ' + (expanded ? '▾' : '▸');
				group.rows.forEach(function(row) {
					row.style.display = expanded ? '' : 'none';
				});
			});
			cell.appendChild(button);
			tbody.appendChild(E('tr', {'class': 'tr cbi-section-table-group'}, cell));
			group.rows.forEach(function(row) {
				tbody.appendChild(row);
			});
		});

		this.addNodeAvailability(root);

		return root;
	},

	maskUrl: function(url) {
		var matched = (url || '').match(/^(https?:\/\/[^/?#]+)([^?#]*)/i);
		return matched ? matched[1] + (matched[2] || '') : (url || '');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('socks-proxy', _('代理节点'),
			_('可手动添加节点，也可通过“导入”页面添加。密码等敏感信息保存在 /etc/config/socks-proxy 中，不会显示在状态输出里。'));

		s = m.section(form.GridSection, 'node', _('节点'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.addbtntitle = _('添加节点');
		s.tab('general', _('常规设置'));
		s.tab('protocol', _('协议设置'));
		s.tab('transport', _('TLS 与传输设置'));

		o = s.taboption('general', form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'name', _('名称'));
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'type', _('类型'));
		o.value('shadowsocks', _('Shadowsocks'));
		o.value('vmess', _('VMess'));
		o.value('vless', _('VLESS'));
		o.value('trojan', _('Trojan'));
		o.value('hysteria2', _('Hysteria2'));
		o.value('tuic', _('TUIC'));
		o.value('socks', _('上游 SOCKS5'));
		o.value('http', _('上游 HTTP'));
		o.value('custom', _('自定义 sing-box JSON'));
		o.default = 'shadowsocks';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'server', _('服务器地址'));
		o.datatype = 'host';
		o.depends({ type: 'custom', '!reverse': true });
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'server_port', _('服务器端口'));
		o.datatype = 'port';
		o.depends({ type: 'custom', '!reverse': true });
		o.rmempty = false;

		o = s.taboption('protocol', form.Value, 'uuid', _('UUID'));
		o.depends('type', 'vmess');
		o.depends('type', 'vless');
		o.depends('type', 'tuic');

		o = s.taboption('protocol', form.Value, 'password', _('密码 / 凭据'));
		o.password = true;
		o.depends('type', 'shadowsocks');
		o.depends('type', 'trojan');
		o.depends('type', 'hysteria2');
		o.depends('type', 'tuic');
		o.depends('type', 'socks');
		o.depends('type', 'http');

		o = s.taboption('protocol', form.Value, 'username', _('用户名'));
		o.depends('type', 'socks');
		o.depends('type', 'http');

		o = s.taboption('protocol', form.Value, 'method', _('加密方式'));
		o.depends('type', 'shadowsocks');
		o.placeholder = '2022-blake3-aes-128-gcm';

		o = s.taboption('protocol', form.Value, 'plugin', _('插件'));
		o.depends('type', 'shadowsocks');

		o = s.taboption('protocol', form.Value, 'plugin_opts', _('插件选项'));
		o.depends('type', 'shadowsocks');

		o = s.taboption('protocol', form.ListValue, 'security', _('VMess 加密方式'));
		o.value('auto', _('自动'));
		o.value('aes-128-gcm', 'AES-128-GCM');
		o.value('chacha20-poly1305', 'ChaCha20-Poly1305');
		o.value('none', _('无'));
		o.default = 'auto';
		o.depends('type', 'vmess');

		o = s.taboption('protocol', form.Value, 'alter_id', _('Alter ID（额外 ID）'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.depends('type', 'vmess');

		o = s.taboption('protocol', form.Value, 'flow', _('VLESS 流控'));
		o.depends('type', 'vless');

		o = s.taboption('protocol', form.Value, 'up_mbps', _('上传速率（Mbps）'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria2');

		o = s.taboption('protocol', form.Value, 'down_mbps', _('下载速率（Mbps）'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria2');

		o = s.taboption('protocol', form.ListValue, 'obfs_type', _('Hysteria2 混淆'));
		o.value('', _('禁用'));
		o.value('salamander', 'Salamander');
		o.depends('type', 'hysteria2');

		o = s.taboption('protocol', form.Value, 'obfs_password', _('混淆密码'));
		o.password = true;
		o.depends({ type: 'hysteria2', obfs_type: 'salamander' });

		o = s.taboption('protocol', form.ListValue, 'congestion_control', _('TUIC 拥塞控制'));
		o.value('bbr', 'BBR');
		o.value('cubic', 'CUBIC');
		o.value('new_reno', 'New Reno');
		o.default = 'bbr';
		o.depends('type', 'tuic');

		o = s.taboption('protocol', form.ListValue, 'udp_relay_mode', _('TUIC UDP 中继模式'));
		o.value('native', _('原生'));
		o.value('quic', 'QUIC');
		o.default = 'native';
		o.depends('type', 'tuic');

		o = s.taboption('protocol', form.ListValue, 'socks_version', _('SOCKS 版本'));
		o.value('5', '5');
		o.value('4', '4');
		o.value('4a', '4a');
		o.default = '5';
		o.depends('type', 'socks');

		o = s.taboption('transport', form.Flag, 'tls', _('启用 TLS'));
		o.depends('type', 'vmess');
		o.depends('type', 'vless');
		o.depends('type', 'trojan');
		o.depends('type', 'hysteria2');
		o.depends('type', 'tuic');
		o.depends('type', 'http');
		o.default = '0';

		o = s.taboption('transport', form.Value, 'server_name', _('TLS 服务器名称'));
		o.depends('tls', '1');

		o = s.taboption('transport', form.Value, 'tls_alpn', _('TLS ALPN'));
		o.depends('tls', '1');
		o.placeholder = _('多个值用英文逗号分隔；TUIC 默认使用 h3');
		o.description = _('TUIC 通常需要 h3。订阅链接中的 alpn 参数会自动导入。');

		o = s.taboption('transport', form.Flag, 'insecure', _('允许不安全的 TLS'));
		o.depends('tls', '1');
		o.default = '0';

		o = s.taboption('transport', form.ListValue, 'utls_fingerprint', _('uTLS 指纹'));
		o.value('', _('禁用'));
		o.value('chrome', 'Chrome');
		o.value('firefox', 'Firefox');
		o.value('safari', 'Safari');
		o.value('randomized', _('随机'));
		o.depends('tls', '1');

		o = s.taboption('transport', form.Flag, 'reality', _('REALITY'));
		o.depends({ type: 'vless', tls: '1' });

		o = s.taboption('transport', form.Value, 'reality_public_key', _('REALITY 公钥'));
		o.depends('reality', '1');

		o = s.taboption('transport', form.Value, 'reality_short_id', _('REALITY 短 ID'));
		o.depends('reality', '1');

		o = s.taboption('transport', form.ListValue, 'transport', _('传输方式'));
		o.value('tcp', 'TCP');
		o.value('ws', 'WebSocket');
		o.value('grpc', 'gRPC');
		o.value('httpupgrade', 'HTTPUpgrade');
		o.default = 'tcp';
		o.depends('type', 'vmess');
		o.depends('type', 'vless');
		o.depends('type', 'trojan');

		o = s.taboption('transport', form.Value, 'transport_path', _('路径'));
		o.depends('transport', 'ws');
		o.depends('transport', 'httpupgrade');

		o = s.taboption('transport', form.Value, 'transport_host', _('Host 请求头'));
		o.depends('transport', 'ws');
		o.depends('transport', 'httpupgrade');

		o = s.taboption('transport', form.Value, 'grpc_service_name', _('gRPC 服务名称'));
		o.depends('transport', 'grpc');

		o = s.taboption('protocol', form.TextValue, 'custom_json', _('自定义出站 JSON'));
		o.rows = 14;
		o.depends('type', 'custom');
		o.description = _('请输入一个 sing-box 出站对象，本插件会自动替换其中的 tag。');

		/* Keep the overview table compact. All remaining fields stay available
		 * in the edit dialog. */
		for (var i = 3; i < s.children.length; i++)
			s.children[i].modalonly = true;

		var view = this;
		return m.render().then(function(root) {
			var applyGrouping = function() {
				view.groupRows(root);
			};

			applyGrouping();
			setTimeout(applyGrouping, 0);

			/* Re-apply after LuCI replaces the table during save/reset. */
			if (root && root.querySelector && typeof MutationObserver != 'undefined') {
				if (root.__socksProxyGroupObserver)
					root.__socksProxyGroupObserver.disconnect();
				root.__socksProxyGroupObserver = new MutationObserver(applyGrouping);
				root.__socksProxyGroupObserver.observe(root, {
					childList: true,
					subtree: true
				});
			}

			return root;
		});
	}
});
