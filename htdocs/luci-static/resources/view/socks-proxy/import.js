'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

return view.extend({
	load: function() {
		return uci.load('socks-proxy');
	},

	runImport: function(map, args) {
		return map.save().then(function() {
			return uci.save();
		}).then(function() {
			return fs.exec('/usr/libexec/socks-proxy/import', args);
		}).then(function(res) {
			var result;
			try { result = JSON.parse(res.stdout || '{}'); }
			catch (e) { throw new Error((res.stderr || res.stdout || e.message).trim()); }
			if (!result.success)
				throw new Error(result.error || _('导入失败'));
			ui.addNotification(null, E('p', _('已导入 %d 个节点。').format(result.imported || 0)), 'info');
			window.setTimeout(function() { window.location.reload(); }, 500);
		}).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'error');
		});
	},

	runFileImport: function(map, textarea, replaceCheckbox) {
		var content = textarea.value || '';
		if (!content.trim()) {
			ui.addNotification(null, E('p', _('请至少粘贴一个分享链接。')), 'warning');
			return Promise.resolve();
		}

		return map.save().then(function() {
			return uci.save();
		}).then(function() {
			return fs.write('/tmp/socks-proxy-import.txt', content);
		}).then(L.bind(function() {
			return fs.exec('/usr/libexec/socks-proxy/import', [
				'file', '/tmp/socks-proxy-import.txt', replaceCheckbox.checked ? '1' : '0'
			]);
		}, this)).then(function(res) {
			var result;
			try { result = JSON.parse(res.stdout || '{}'); }
			catch (e) { throw new Error((res.stderr || res.stdout || e.message).trim()); }
			if (!result.success)
				throw new Error(result.error || _('导入失败'));
			textarea.value = '';
			ui.addNotification(null, E('p', _('已导入 %d 个节点。').format(result.imported || 0)), 'info');
			window.setTimeout(function() { window.location.reload(); }, 500);
		}).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'error');
		});
	},

	render: function() {
		var m, s, o, urlOption;

		m = new form.Map('socks-proxy', _('订阅管理'),
			_('订阅内容可以是普通文本，也可以是经过 Base64 编码的分享链接。'));

		s = m.section(form.GridSection, 'subscription', _('订阅'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.addbtntitle = _('添加订阅');

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';

		o = s.option(form.Value, 'name', _('名称'));
		o.rmempty = false;

		urlOption = s.option(form.Value, 'url', _('订阅地址'));
		urlOption.rmempty = false;
		urlOption.validate = function(section_id, value) {
			value = (value || '').trim();
			if (!/^https?:\/\/[^\s]+$/i.test(value))
				return _('订阅地址必须以 http:// 或 https:// 开头，且不能包含空格。');
			return true;
		};

		o = s.option(form.Button, '_update', _('更新'));
		o.inputtitle = _('更新节点');
		o.inputstyle = 'apply';
		o.editable = true;
		o.onclick = L.bind(function(ev, section_id) {
			var url = urlOption.formvalue(section_id) || uci.get('socks-proxy', section_id, 'url') || '';
			return this.runImport(m, [ 'subscription-url', section_id, url.trim() ]);
		}, this);

		return m.render().then(L.bind(function(subscriptionForm) {
			var textarea = E('textarea', {
				'class': 'cbi-input-textarea',
				'rows': 12,
				'style': 'width:100%',
				'placeholder': 'hysteria2://...\nvless://...\nss://...'
			});
			var replaceCheckbox = E('input', { 'type': 'checkbox' });
			return E([], [
				E('h2', _('导入节点')),
				E('p', { 'class': 'cbi-map-descr' }, _('每行粘贴一个分享链接。支持：ss、vmess、vless、trojan、hysteria2、hy2、tuic、socks5、http 和 https。')),
				E('div', { 'class': 'cbi-section' }, [
					E('h3', _('分享链接')),
					textarea,
					E('label', { 'style': 'display:block;margin:1em 0' }, [ replaceCheckbox, ' ', _('替换所有现有节点') ]),
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': ui.createHandlerFn(this, 'runFileImport', m, textarea, replaceCheckbox)
					}, _('立即导入'))
				]),
				subscriptionForm
			]);
		}, this));
	}
});
