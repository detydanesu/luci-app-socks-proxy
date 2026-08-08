#!/usr/bin/ucode

'use strict';

import { cursor } from 'uci';
import { urldecode } from 'luci.http';
import { readfile } from 'fs';

const uci = cursor();

function nonempty(value) {
	return value != null && value != '';
}

function decode64(value) {
	let text = replace(replace(trim(value), /-/g, '+'), /_/g, '/');
	while (length(text) % 4)
		text += '=';
	return b64dec(text);
}

function query_params(query) {
	const params = {};
	const parts = split(query || '', '&');
	for (let i = 0; i < length(parts); i++) {
		if (!nonempty(parts[i]))
			continue;
		const p = index(parts[i], '=');
		const key = urldecode(p < 0 ? parts[i] : substr(parts[i], 0, p), true);
		const value = urldecode(p < 0 ? '' : substr(parts[i], p + 1), true);
		params[key] = value;
	}
	return params;
}

function parse_authority(value) {
	let userinfo = '';
	let hostport = value;
	const matched = match(value, /^(.*)@([^@]+)$/);
	if (matched) {
		userinfo = matched[1];
		hostport = matched[2];
	}

	let host = '';
	let port = 0;
	if (substr(hostport, 0, 1) == '[') {
		const close = index(hostport, ']');
		if (close > 0) {
			host = substr(hostport, 1, close - 1);
			port = int(substr(hostport, close + 2));
		}
	}
	else {
		const parts = split(hostport, ':');
		if (length(parts) >= 2) {
			port = int(parts[length(parts) - 1]);
			host = join(':', slice(parts, 0, length(parts) - 1));
		}
	}

	return { userinfo, host, port };
}

function common_uri(uri) {
	const scheme_end = index(uri, '://');
	if (scheme_end < 1)
		return null;

	let scheme = lc(substr(uri, 0, scheme_end));
	let rest = substr(uri, scheme_end + 3);
	let name = '';
	let query = '';

	const hash = index(rest, '#');
	if (hash >= 0) {
		name = urldecode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}

	const question = index(rest, '?');
	if (question >= 0) {
		query = substr(rest, question + 1);
		rest = substr(rest, 0, question);
	}

	return { scheme, rest, name, params: query_params(query) };
}

function apply_tls_transport(node, params) {
	const security = params.security || '';
	if (security == 'tls' || security == 'reality' || params.tls == '1')
		node.tls = '1';
	if (security == 'reality')
		node.reality = '1';

	node.server_name = params.sni || params.serverName || params.peer || '';
	node.insecure = (params.insecure == '1' || params.allowInsecure == '1') ? '1' : '0';
	node.utls_fingerprint = params.fp || '';
	node.reality_public_key = params.pbk || params.publicKey || '';
	node.reality_short_id = params.sid || params.shortId || '';
	node.transport = params.type || params.net || 'tcp';
	node.transport_path = params.path || '';
	node.transport_host = params.host || '';
	node.grpc_service_name = params.serviceName || params.service_name || '';

	return node;
}

function parse_vmess(uri) {
	const raw = substr(uri, length('vmess://'));
	let decoded;
	let data;
	try {
		decoded = decode64(raw);
		data = json(decoded);
	}
	catch (e) {
		return null;
	}

	let node = {
		type: 'vmess',
		name: data.ps || data.name || 'VMess',
		server: data.add,
		server_port: `${int(data.port)}`,
		uuid: data.id,
		alter_id: `${int(data.aid || 0)}`,
		security: data.scy || data.security || 'auto',
		tls: data.tls == 'tls' ? '1' : '0',
		server_name: data.sni || data.host || '',
		insecure: data.allowInsecure == true ? '1' : '0',
		transport: data.net || 'tcp',
		transport_path: data.path || '',
		transport_host: data.host || '',
		grpc_service_name: data.path || data.serviceName || '',
		utls_fingerprint: data.fp || ''
	};

	return node;
}

function parse_ss(uri) {
	const parsed = common_uri(uri);
	if (!parsed)
		return null;

	let rest = parsed.rest;
	if (index(rest, '@') < 0) {
		try { rest = decode64(rest); }
		catch (e) { return null; }
	}

	const authority = parse_authority(rest);
	if (!authority.host || !authority.port)
		return null;

	let userinfo = authority.userinfo;
	if (index(userinfo, ':') < 0) {
		try { userinfo = decode64(userinfo); }
		catch (e) { return null; }
	}
	const split_at = index(userinfo, ':');
	if (split_at < 1)
		return null;

	return {
		type: 'shadowsocks',
		name: parsed.name || authority.host,
		server: authority.host,
		server_port: `${authority.port}`,
		method: urldecode(substr(userinfo, 0, split_at)),
		password: urldecode(substr(userinfo, split_at + 1)),
		plugin: parsed.params.plugin ? split(parsed.params.plugin, ';')[0] : '',
		plugin_opts: parsed.params.plugin ? join(';', slice(split(parsed.params.plugin, ';'), 1)) : ''
	};
}

function parse_standard(uri) {
	const parsed = common_uri(uri);
	if (!parsed)
		return null;
	const authority = parse_authority(parsed.rest);
	if (!authority.host || !authority.port)
		return null;

	const credentials = split(authority.userinfo || '', ':');
	const first = urldecode(credentials[0] || '');
	const second = urldecode(join(':', slice(credentials, 1)) || '');
	let node = {
		name: parsed.name || authority.host,
		server: authority.host,
		server_port: `${authority.port}`
	};

	switch (parsed.scheme) {
	case 'vless':
		node.type = 'vless';
		node.uuid = first;
		node.flow = parsed.params.flow || '';
		apply_tls_transport(node, parsed.params);
		break;
	case 'trojan':
		node.type = 'trojan';
		node.password = first;
		node.tls = '1';
		apply_tls_transport(node, parsed.params);
		break;
	case 'hysteria2':
	case 'hy2':
		node.type = 'hysteria2';
		node.password = first;
		node.tls = '1';
		node.server_name = parsed.params.sni || authority.host;
		node.insecure = (parsed.params.insecure == '1') ? '1' : '0';
		node.obfs_type = parsed.params.obfs || '';
		node.obfs_password = parsed.params['obfs-password'] || parsed.params.obfs_password || '';
		node.up_mbps = parsed.params.upmbps || parsed.params.up || '';
		node.down_mbps = parsed.params.downmbps || parsed.params.down || '';
		break;
	case 'tuic':
		node.type = 'tuic';
		node.uuid = first;
		node.password = second;
		node.tls = '1';
		node.server_name = parsed.params.sni || authority.host;
		node.insecure = (parsed.params.allow_insecure == '1' || parsed.params.insecure == '1') ? '1' : '0';
		node.congestion_control = parsed.params.congestion_control || 'bbr';
		node.udp_relay_mode = parsed.params.udp_relay_mode || 'native';
		break;
	case 'socks':
	case 'socks5':
		node.type = 'socks';
		node.socks_version = '5';
		node.username = first;
		node.password = second;
		break;
	case 'http':
	case 'https':
		node.type = 'http';
		node.username = first;
		node.password = second;
		node.tls = parsed.scheme == 'https' ? '1' : '0';
		node.server_name = parsed.params.sni || authority.host;
		break;
	default:
		return null;
	}

	return node;
}

function parse_link(uri) {
	uri = trim(uri);
	if (!nonempty(uri) || substr(uri, 0, 1) == '#')
		return null;
	if (substr(uri, 0, length('vmess://')) == 'vmess://')
		return parse_vmess(uri);
	if (substr(uri, 0, length('ss://')) == 'ss://')
		return parse_ss(uri);
	return parse_standard(uri);
}

function delete_source(source, delete_all) {
	const sections = [];
	uci.foreach('socks-proxy', 'node', (node) => {
		if (delete_all || node.source == source)
			push(sections, node['.name']);
	});
	for (let i = 0; i < length(sections); i++)
		uci.delete('socks-proxy', sections[i]);
}

function write_node(node, source) {
	const sid = uci.add('socks-proxy', 'node');
	uci.set('socks-proxy', sid, 'enabled', '1');
	uci.set('socks-proxy', sid, 'source', source);
	for (let key in node) {
		if (node[key] != null && node[key] != '')
			uci.set('socks-proxy', sid, key, `${node[key]}`);
	}
	return sid;
}

let source;
let content;
let replace_existing = false;

if (mode == 'file') {
	content = readfile(input_path) || '';
	replace_existing = replace_existing == '1';
	source = 'manual-import';
}
else if (mode == 'subscription') {
	content = readfile(input_path) || '';
	source = `subscription:${section}`;
}
else {
	print({ success: false, error: '无效的导入模式' });
	exit(2);
}

if (index(content, '://') < 0) {
	try {
		const decoded = decode64(content);
		if (index(decoded, '://') >= 0)
			content = decoded;
	}
	catch (e) {}
}

content = replace(replace(content, /\r/g, '\n'), /\n+/g, '\n');
const links = split(content, '\n');
const parsed_nodes = [];
const errors = [];

for (let i = 0; i < length(links); i++) {
	const line = trim(links[i]);
	if (!line)
		continue;
	const node = parse_link(line);
	if (node)
		push(parsed_nodes, node);
	else
		push(errors, i + 1);
}

if (!length(parsed_nodes)) {
	print({ success: false, imported: 0, errors, error: '未找到支持的节点链接' });
	exit(1);
}

delete_source(source, replace_existing);
for (let i = 0; i < length(parsed_nodes); i++)
	write_node(parsed_nodes[i], source);

uci.commit('socks-proxy');
print({ success: true, imported: length(parsed_nodes), errors });
