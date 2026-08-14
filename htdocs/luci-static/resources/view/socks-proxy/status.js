'use strict';
'require view';
'require fs';
'require ui';
'require uci';

function parseValues(output) {
	var values = {};
	(output || '').trim().split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > -1)
			values[line.substring(0, p)] = line.substring(p + 1);
	});
	return values;
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('socks-proxy'),
			fs.exec('/usr/libexec/socks-proxy/status', [])
		]);
	},

	handleAction: function(action) {
		return fs.exec('/etc/init.d/socks-proxy', [ action ]).then(L.bind(function() {
			ui.addNotification(null, E('p', _('服务操作已完成。')), 'info');
			window.setTimeout(function() { window.location.reload(); }, 700);
		}, this)).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'error');
		});
	},

	handleProbe: function(mode, section, button, output) {
		button.disabled = true;
		output.style.color = '';
		output.textContent = _('检测中…');

		return fs.exec('/usr/libexec/socks-proxy/check', [ mode, section ]).then(function(res) {
			var values = parseValues(res.stdout);
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
		}).catch(function(err) {
			output.style.color = '#dc2626';
			output.textContent = _('检测执行失败：') + err.message;
		}).finally(function() {
			button.disabled = false;
		});
	},

	probeRow: function(mode, section, title, detail) {
		var output = E('span', { 'class': 'availability-result' }, _('尚未检测'));
		var button = E('button', { 'class': 'btn cbi-button-action' }, _('检测'));

		button.addEventListener('click', L.bind(function(ev) {
			ev.preventDefault();
			return this.handleProbe(mode, section, button, output);
		}, this));

		return E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td left' }, title || section),
			E('td', { 'class': 'td left' }, detail || '-'),
			E('td', { 'class': 'td left' }, output),
			E('td', { 'class': 'td right' }, button)
		]);
	},

	probeTable: function(mode, title, sections, detailFn) {
		var rows = [ E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th left' }, _('名称')),
			E('th', { 'class': 'th left' }, mode === 'node' ? _('类型 / 服务器') : _('协议 / 监听端口')),
			E('th', { 'class': 'th left' }, _('检测结果')),
			E('th', { 'class': 'th right' }, _('操作'))
		]) ];

		sections.forEach(L.bind(function(section) {
			rows.push(this.probeRow(
				mode,
				section['.name'],
				section.name || section.remarks || section['.name'],
				detailFn(section)
			));
		}, this));

		if (!sections.length)
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'colspan': 4 }, _('暂无可检测项目。'))
			]));

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, title),
			E('table', { 'class': 'table' }, rows)
		]);
	},

	render: function(data) {
		var values = parseValues(data[1].stdout);
		var running = values.running === '1';
		var gidOk = values.gid === '65534';
		var nodes = uci.sections('socks-proxy', 'node');
		var listeners = uci.sections('socks-proxy', 'listener');

		return E([], [
			E('h2', _('SOCKS/HTTP 代理状态')),
			E('div', { 'class': 'cbi-section' }, [
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('服务状态')), E('td', { 'class': 'td left' }, running ? _('运行中') : _('已停止')) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('PID')), E('td', { 'class': 'td left' }, values.pid || '-') ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('连接所属组')), E('td', { 'class': 'td left' }, (values.gid || '-') + (running ? (gidOk ? ' — ' + _('已绕过 OpenClash') : ' — ' + _('未绕过 OpenClash')) : '')) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('已配置节点')), E('td', { 'class': 'td left' }, values.nodes || '0') ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('已配置监听端口')), E('td', { 'class': 'td left' }, values.listeners || '0') ])
				])
			]),
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, 'handleAction', 'start') }, _('启动')),
				' ',
				E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, 'handleAction', 'restart') }, _('重启')),
				' ',
				E('button', { 'class': 'btn cbi-button-negative', 'click': ui.createHandlerFn(this, 'handleAction', 'stop') }, _('停止'))
			]),
			E('p', { 'class': 'cbi-section-descr' }, _('节点检测会临时启动一个仅本机可访问的 SOCKS5 端口，并以 nogroup 身份直连测试；监听代理检测会通过已经建立的代理端口发起真实请求。')),
			this.probeTable('listener', _('已建立代理可用性'), listeners, function(listener) {
				return (listener.protocol || 'socks').toUpperCase() + ' · ' + (listener.bind_mode === 'lan' ? '0.0.0.0' : (listener.listen_address || '127.0.0.1')) + ':' + (listener.port || '-');
			}),
			this.probeTable('node', _('节点可用性'), nodes, function(node) {
				return (node.type || '-').toUpperCase() + ' · ' + (node.server || '-') + ':' + (node.server_port || '-');
			})
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
