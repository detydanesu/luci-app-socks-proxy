'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return uci.load('socks-proxy');
	},

	render: function() {
		var m, s, o;
		var nodes = uci.sections('socks-proxy', 'node').filter(function(node) {
			return node.enabled !== '0';
		});

		m = new form.Map('socks-proxy', _('SOCKS/HTTP 代理'),
			_('将选定的 sing-box 节点作为普通的 SOCKS5 或 HTTP 代理端口使用。本服务不会修改 DNS、路由或防火墙转发规则。'));

		s = m.section(form.NamedSection, 'global', 'global', _('服务设置'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('启用服务'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.ListValue, 'log_level', _('日志级别'));
		o.value('error', _('错误'));
		o.value('warn', _('警告'));
		o.value('info', _('信息'));
		o.value('debug', _('调试'));
		o.default = 'info';

		o = s.option(form.Flag, 'bypass_openclash', _('绕过 OpenClash'));
		o.default = '1';
		o.readonly = true;
		o.description = _('服务以 root:nogroup（GID 65534）身份运行。当前 OpenClash 输出规则会放行属于该组的连接。');

		s = m.section(form.GridSection, 'listener', _('代理监听端口'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.addbtntitle = _('添加监听端口');

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'name', _('名称'));
		o.placeholder = _('局域网 SOCKS');
		o.rmempty = false;

		o = s.option(form.ListValue, 'protocol', _('代理协议'));
		o.value('socks', _('SOCKS5'));
		o.value('http', _('HTTP'));
		o.value('mixed', _('SOCKS5 + HTTP（混合）'));
		o.default = 'socks';
		o.rmempty = false;

		o = s.option(form.ListValue, 'node', _('出站节点'));
		nodes.forEach(function(node) {
			o.value(node['.name'], node.name || node.remarks || node['.name']);
		});
		o.rmempty = false;

		o = s.option(form.ListValue, 'bind_mode', _('访问范围'));
		o.value('local', _('仅本机'));
		o.value('lan', _('局域网设备'));
		o.default = 'local';
		o.rmempty = false;
		o.description = _('局域网模式会监听所有 IPv4 接口，但本插件不会创建允许从 WAN 访问的防火墙规则。');

		o = s.option(form.Value, 'port', _('监听端口'));
		o.datatype = 'port';
		o.placeholder = '1081';
		o.rmempty = false;

		o = s.option(form.Flag, 'auth_enabled', _('启用身份验证'));
		o.default = '0';
		o.description = _('局域网监听端口强烈建议启用身份验证。');

		o = s.option(form.Value, 'username', _('用户名'));
		o.depends('auth_enabled', '1');
		o.rmempty = false;

		o = s.option(form.Value, 'password', _('密码'));
		o.depends('auth_enabled', '1');
		o.password = true;
		o.rmempty = false;

		return m.render();
	}
});
