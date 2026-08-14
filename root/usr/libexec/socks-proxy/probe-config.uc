#!/usr/bin/ucode

'use strict';

import { readfile } from 'fs';

const node_id = ARGV[0] || '';
const listen_port = int(ARGV[1]);
let config;

if (!match(node_id, /^[A-Za-z0-9_]+$/) || listen_port == null || listen_port < 1 || listen_port > 65535) {
	warn('Invalid probe arguments\n');
	exit(2);
}

try {
	config = json(readfile('/dev/stdin') || '');
}
catch (e) {
	warn(`Unable to read generated sing-box configuration: ${e}\n`);
	exit(2);
}

const target = `node-${node_id}`;
let found = false;

for (let i = 0; i < length(config.outbounds || []); i++) {
	if (config.outbounds[i].tag == target) {
		found = true;
		break;
	}
}

if (!found) {
	warn(`Node ${node_id} is disabled, invalid or unsupported\n`);
	exit(3);
}

config.log = {
	level: 'error',
	timestamp: true
};
config.inbounds = [{
	type: 'socks',
	tag: 'probe-in',
	listen: '127.0.0.1',
	listen_port
}];
config.route = {
	auto_detect_interface: true,
	rules: [{
		inbound: [ 'probe-in' ],
		action: 'route',
		outbound: target
	}],
	final: target
};

print(config);
