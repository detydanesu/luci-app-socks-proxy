#!/usr/bin/ucode

'use strict';

import { cursor } from 'uci';

const uci = cursor();
const global = uci.get_all('socks-proxy', 'global') || {};
const outbounds = [];
const inbounds = [];
const route_rules = [];
const node_tags = {};

function bool(value) {
	return value == true || value == 1 || value == '1' || value == 'true';
}

function integer(value, fallback) {
	const n = int(value);
	return n == null ? fallback : n;
}

function nonempty(value) {
	return value != null && value != '';
}

function tls_config(node) {
	if (!bool(node.tls))
		return null;

	const tls = {
		enabled: true,
		server_name: node.server_name || node.server,
		insecure: bool(node.insecure)
	};
	const alpn_value = node.tls_alpn || (node.type == 'tuic' ? 'h3' : '');
	if (nonempty(alpn_value)) {
		const values = split(alpn_value, ',');
		const alpn = [];
		for (let i = 0; i < length(values); i++) {
			const value = trim(values[i]);
			if (nonempty(value))
				push(alpn, value);
		}
		if (length(alpn))
			tls.alpn = alpn;
	}

	if (nonempty(node.utls_fingerprint))
		tls.utls = { enabled: true, fingerprint: node.utls_fingerprint };

	if (bool(node.reality)) {
		tls.reality = {
			enabled: true,
			public_key: node.reality_public_key,
			short_id: node.reality_short_id || ''
		};
	}

	return tls;
}

function transport_config(node) {
	const type = node.transport || 'tcp';
	if (type == 'tcp' || type == '')
		return null;

	const transport = { type };
	if (type == 'ws' || type == 'httpupgrade') {
		transport.path = node.transport_path || '/';
		if (nonempty(node.transport_host))
			transport.headers = { Host: node.transport_host };
	}
	else if (type == 'grpc') {
		transport.service_name = node.grpc_service_name || '';
	}

	return transport;
}

function build_outbound(node) {
	const type = node.type;
	const tag = `node-${node['.name']}`;
	let outbound = {
		type,
		tag,
		server: node.server,
		server_port: integer(node.server_port, 0)
	};

	if (type != 'custom' && (!nonempty(node.server) || outbound.server_port <= 0))
		return null;

	switch (type) {
	case 'shadowsocks':
		outbound.method = node.method;
		outbound.password = node.password || '';
		if (nonempty(node.plugin))
			outbound.plugin = node.plugin;
		if (nonempty(node.plugin_opts))
			outbound.plugin_options = node.plugin_opts;
		break;

	case 'vmess':
		outbound.uuid = node.uuid;
		outbound.security = node.security || 'auto';
		outbound.alter_id = integer(node.alter_id, 0);
		outbound.tls = tls_config(node);
		outbound.transport = transport_config(node);
		break;

	case 'vless':
		outbound.uuid = node.uuid;
		if (nonempty(node.flow))
			outbound.flow = node.flow;
		outbound.tls = tls_config(node);
		outbound.transport = transport_config(node);
		break;

	case 'trojan':
		outbound.password = node.password || '';
		outbound.tls = tls_config(node);
		outbound.transport = transport_config(node);
		break;

	case 'hysteria2':
		outbound.password = node.password || '';
		outbound.tls = tls_config(node);
		if (integer(node.up_mbps, 0) > 0)
			outbound.up_mbps = integer(node.up_mbps, 0);
		if (integer(node.down_mbps, 0) > 0)
			outbound.down_mbps = integer(node.down_mbps, 0);
		if (nonempty(node.obfs_type))
			outbound.obfs = { type: node.obfs_type, password: node.obfs_password || '' };
		break;

	case 'tuic':
		outbound.uuid = node.uuid;
		outbound.password = node.password || '';
		outbound.congestion_control = node.congestion_control || 'bbr';
		outbound.udp_relay_mode = node.udp_relay_mode || 'native';
		outbound.tls = tls_config(node);
		break;

	case 'socks':
		outbound.version = node.socks_version || '5';
		if (nonempty(node.username))
			outbound.username = node.username;
		if (nonempty(node.password))
			outbound.password = node.password;
		break;

	case 'http':
		if (nonempty(node.username))
			outbound.username = node.username;
		if (nonempty(node.password))
			outbound.password = node.password;
		outbound.tls = tls_config(node);
		break;

	case 'custom':
		try {
			outbound = json(node.custom_json || '{}');
		}
		catch (e) {
			warn(`Invalid custom JSON for node ${node['.name']}: ${e}\n`);
			return null;
		}
		outbound.tag = tag;
		break;

	default:
		warn(`Unsupported node type: ${type}\n`);
		return null;
	}

	return outbound;
}

uci.foreach('socks-proxy', 'node', (node) => {
	if (!bool(node.enabled))
		return;

	const outbound = build_outbound(node);
	if (outbound != null) {
		push(outbounds, outbound);
		node_tags[node['.name']] = outbound.tag;
	}
});

uci.foreach('socks-proxy', 'listener', (listener) => {
	if (!bool(listener.enabled) || !node_tags[listener.node])
		return;

	const protocol = listener.protocol || 'socks';
	if (protocol != 'socks' && protocol != 'http' && protocol != 'mixed')
		return;

	const tag = `in-${listener['.name']}`;
	const inbound = {
		type: protocol,
		tag,
		listen: listener.bind_mode == 'lan' ? '0.0.0.0' : (listener.listen_address || '127.0.0.1'),
		listen_port: integer(listener.port, 0)
	};

	if (inbound.listen_port <= 0)
		return;

	if (bool(listener.auth_enabled) && nonempty(listener.username)) {
		inbound.users = [{
			username: listener.username,
			password: listener.password || ''
		}];
	}

	push(inbounds, inbound);
	push(route_rules, {
		inbound: [ tag ],
		action: 'route',
		outbound: node_tags[listener.node]
	});
});

push(outbounds, { type: 'direct', tag: 'direct' });

const config = {
	log: {
		level: global.log_level || 'info',
		timestamp: true
	},
	inbounds,
	outbounds,
	route: {
		auto_detect_interface: true,
		rules: route_rules,
		final: 'direct'
	}
};

print(config);
