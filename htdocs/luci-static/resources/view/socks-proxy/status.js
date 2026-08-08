'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return fs.exec('/usr/libexec/socks-proxy/status', []).then(function(res) {
			return res.stdout || '';
		});
	},

	handleAction: function(action) {
		return fs.exec('/etc/init.d/socks-proxy', [ action ]).then(L.bind(function() {
			ui.addNotification(null, E('p', _('服务操作已完成。')), 'info');
			window.setTimeout(function() { window.location.reload(); }, 700);
		}, this)).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'error');
		});
	},

	render: function(status) {
		var values = {};
		status.trim().split(/\n/).forEach(function(line) {
			var p = line.indexOf('=');
			if (p > -1)
				values[line.substring(0, p)] = line.substring(p + 1);
		});

		var running = values.running === '1';
		var gidOk = values.gid === '65534';

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
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
