#!/usr/bin/ucode

'use strict';

import { cursor } from 'uci';
import { urldecode } from 'luci.http';
import { readfile } from 'fs';

const uci = cursor();

function nonempty(value) {
	return value != null && value != '';
}

function truthy(value) {
	return value == true || value == 1 || value == '1' || value == 'true';
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
	node.tls_alpn = params.alpn || '';
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
		tls_alpn: data.alpn || '',
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
		node.tls_alpn = parsed.params.alpn || '';
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
		node.tls_alpn = parsed.params.alpn || 'h3';
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
		node.tls_alpn = parsed.params.alpn || '';
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

function add_unique(list, seen, value) {
	if (nonempty(value) && !seen[value]) {
		seen[value] = true;
		push(list, value);
	}
}

function node_signature(node) {
	/*
	 * Names and traffic counters can change between subscription updates. The
	 * transport endpoint and credentials are a more useful identity when we
	 * decide whether an existing UCI section can be reused.
	 */
	return join('|', [
		node.type || '',
		node.server || '',
		node.server_port || '',
		node.uuid || '',
		node.password || '',
		node.transport || '',
		node.transport_path || '',
		node.transport_host || '',
		node.server_name || '',
		node.flow || '',
		node.custom_json || ''
	]);
}

function collect_subscription_groups() {
	const groups = {};
	const order = [];
	const seen = {};

	uci.foreach('socks-proxy', 'node', (node) => {
		const source = node.source || '';
		if (index(source, 'subscription:') != 0)
			return;

		const key = substr(source, length('subscription:'));
		if (!groups[key]) {
			groups[key] = [];
			if (!seen[key]) {
				seen[key] = true;
				push(order, key);
			}
		}
		push(groups[key], node);
	});

	return { groups, order };
}

function collect_subscription_keys() {
	const keys = {};
	uci.foreach('socks-proxy', 'subscription', (subscription) => {
		keys[subscription['.name']] = true;
		if (nonempty(subscription.source_key))
			keys[subscription.source_key] = true;
		if (nonempty(subscription.url))
			keys[subscription.url] = true;
	});
	return keys;
}

function duplicate_legacy_sources(parsed_nodes, groups) {
	const result = [];
	const result_seen = {};
	const known_keys = collect_subscription_keys();
	const parsed_signatures = {};
	const parsed_count = length(parsed_nodes);

	for (let i = 0; i < parsed_count; i++)
		parsed_signatures[node_signature(parsed_nodes[i])] = true;

	/*
	 * Before source_key was introduced, a subscription update could leave an
	 * orphaned group such as subscription:cfg100caa behind. If that group still
	 * substantially overlaps the freshly downloaded nodes, it is safe to treat
	 * it as the old copy of this subscription. Only orphaned sources are
	 * considered, so two live subscriptions with different URLs are preserved.
	 */
	for (let i = 0; i < length(groups.order); i++) {
		const key = groups.order[i];
		if (known_keys[key] || !groups.groups[key])
			continue;

		const group = groups.groups[key];
		let matches = 0;
		for (let j = 0; j < length(group); j++) {
			if (parsed_signatures[node_signature(group[j])])
				matches++;
		}

		const group_ratio = length(group) ? matches / length(group) : 0;
		const parsed_ratio = parsed_count ? matches / parsed_count : 0;
		if (matches >= 2 && (group_ratio >= 0.6 || parsed_ratio >= 0.6))
			add_unique(result, result_seen, key);
	}

	return result;
}

function clear_node_options(section) {
	const values = uci.get_all('socks-proxy', section) || {};
	for (let key in values) {
		if (substr(key, 0, 1) != '.')
			uci.delete('socks-proxy', section, key);
	}
}

function write_node(node, source, section) {
	const sid = section || uci.add('socks-proxy', 'node');
	if (section)
		clear_node_options(section);
	uci.set('socks-proxy', sid, 'enabled', '1');
	uci.set('socks-proxy', sid, 'source', source);
	for (let key in node) {
		if (node[key] != null && node[key] != '')
			uci.set('socks-proxy', sid, key, `${node[key]}`);
	}
	return sid;
}

function replace_subscription_nodes(parsed_nodes, source_list, source) {
	const source_seen = {};
	const existing = [];
	const existing_by_id = {};
	const listener_ids = [];
	const listener_seen = {};

	for (let i = 0; i < length(source_list); i++)
		source_seen[source_list[i]] = true;

	uci.foreach('socks-proxy', 'node', (node) => {
		const node_source = node.source || '';
		if (!source_seen[node_source])
			return;

		const record = {
			id: node['.name'],
			node,
			used: false
		};
		push(existing, record);
		existing_by_id[record.id] = record;
	});

	uci.foreach('socks-proxy', 'listener', (listener) => {
		const id = listener.node || '';
		if (existing_by_id[id] && !listener_seen[id]) {
			listener_seen[id] = true;
			push(listener_ids, id);
		}
	});

	/* Keep listener targets at the front so they are reused before stale rows. */
	const ordered = [];
	const ordered_seen = {};
	for (let i = 0; i < length(listener_ids); i++) {
		const record = existing_by_id[listener_ids[i]];
		if (record && !ordered_seen[record.id]) {
			ordered_seen[record.id] = true;
			push(ordered, record);
		}
	}
	for (let i = 0; i < length(existing); i++) {
		if (!ordered_seen[existing[i].id]) {
			ordered_seen[existing[i].id] = true;
			push(ordered, existing[i]);
		}
	}

	const resulting_ids = [];
	for (let i = 0; i < length(parsed_nodes); i++) {
		const parsed = parsed_nodes[i];
		const signature = node_signature(parsed);
		let record = null;

		for (let j = 0; j < length(ordered); j++) {
			if (!ordered[j].used && node_signature(ordered[j].node) == signature) {
				record = ordered[j];
				break;
			}
		}
		if (!record) {
			for (let j = 0; j < length(ordered); j++) {
				if (!ordered[j].used) {
					record = ordered[j];
					break;
				}
			}
		}

		const id = write_node(parsed, source, record ? record.id : null);
		if (record)
			record.used = true;
		push(resulting_ids, id);
	}

	/* If a listener pointed at a removed row, keep it usable on the first new node. */
	const fallback = resulting_ids[0] || '';
	for (let i = 0; i < length(ordered); i++) {
		const record = ordered[i];
		if (record.used)
			continue;

		if (listener_seen[record.id] && nonempty(fallback)) {
			uci.foreach('socks-proxy', 'listener', (listener) => {
				if (listener.node == record.id)
					uci.set('socks-proxy', listener['.name'], 'node', fallback);
			});
		}
		uci.delete('socks-proxy', record.id);
	}
}

let source;
let legacy_source;
let subscription_skip_verify = false;
let subscription_source_key;
let content;
let replace_existing = false;

if (mode == 'file') {
	content = readfile(input_path) || '';
	replace_existing = replace_existing == '1';
	source = 'manual-import';
}
else if (mode == 'subscription') {
	content = readfile(input_path) || '';
	legacy_source = `subscription:${section}`;
	subscription_source_key = uci.get('socks-proxy', section, 'source_key');
	if (!nonempty(subscription_source_key)) {
		subscription_source_key = uci.get('socks-proxy', section, 'url') || section;
		uci.set('socks-proxy', section, 'source_key', subscription_source_key);
	}
	source = `subscription:${subscription_source_key}`;
	subscription_skip_verify = truthy(uci.get('socks-proxy', section, 'insecure'));
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

if (subscription_skip_verify) {
	for (let i = 0; i < length(parsed_nodes); i++)
		parsed_nodes[i].insecure = '1';
}

if (mode == 'subscription') {
	const groups = collect_subscription_groups();
	const source_list = [];
	const source_seen = {};
	add_unique(source_list, source_seen, source);
	if (nonempty(legacy_source) && legacy_source != source)
		add_unique(source_list, source_seen, legacy_source);

	const duplicate_sources = duplicate_legacy_sources(parsed_nodes, groups);
	for (let i = 0; i < length(duplicate_sources); i++)
		add_unique(source_list, source_seen, `subscription:${duplicate_sources[i]}`);

	replace_subscription_nodes(parsed_nodes, source_list, source);
}
else {
	delete_source(source, replace_existing);
	for (let i = 0; i < length(parsed_nodes); i++)
		write_node(parsed_nodes[i], source, null);
}

uci.commit('socks-proxy');
print({ success: true, imported: length(parsed_nodes), errors });
