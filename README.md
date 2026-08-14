# luci-app-socks-proxy

A small LuCI application that exposes selected sing-box nodes as local or LAN
SOCKS5/HTTP proxy listeners. It does not install transparent-proxy, DNS hijack,
policy-routing or traffic-forwarding rules.

## Design goals

- Multiple nodes and listeners; each listener selects its own outbound node.
- SOCKS5, HTTP and mixed SOCKS5/HTTP listener modes.
- Optional username/password authentication per listener.
- Local-only (`127.0.0.1`) or LAN (`0.0.0.0`) binding.
- Share-link and subscription import for common proxy protocols.
- Active availability checks for individual nodes and established listeners.
- The sing-box service runs as `root:nogroup` (GID 65534). On OpenClash
  installations whose output chains contain `meta skgid 65534 return`, this
  bypasses OpenClash without changing its configuration.

## Supported outbound types

- Shadowsocks
- VMess
- VLESS
- Trojan
- Hysteria2
- TUIC
- SOCKS5
- HTTP/HTTPS
- Custom sing-box outbound JSON

## Build

Place this directory in an OpenWrt/ImmortalWrt package feed and run:

```sh
make package/luci-app-socks-proxy/compile V=s
```

The package is architecture independent, while the installed `sing-box`
dependency must match the router architecture.

The included GitHub Actions workflow builds against the official ImmortalWrt
25.12.1 `rockchip/armv8` SDK and verifies the SDK SHA-256 checksum before use.

## Install the release APK

Download the APK and `SHA256SUMS` from the GitHub Releases page, then copy the
APK to the router and install it with:

```sh
apk add --allow-untrusted /tmp/luci-app-socks-proxy-0.2.0-r1.apk
```

The package itself is architecture independent. Its dependencies, especially
`sing-box`, must come from repositories compatible with the router firmware.

## Configuration

1. Open **Services → SOCKS/HTTP Proxy → Import** to paste share links or add a
   subscription URL.
2. Confirm or edit imported nodes on the **Nodes** page.
3. Add one or more listeners under **Settings**. Each listener independently
   selects SOCKS5, HTTP or mixed mode, a node, local/LAN binding and optional
   authentication.
4. Enable the service and apply the configuration.

Listener credentials are stored in `/etc/config/socks-proxy`. Keep that file
mode `0600`. The generated runtime configuration is also written with mode
`0600`.

## OpenClash coexistence

The service runs sing-box with primary GID 65534 (`nogroup`). OpenClash builds
tested with this package contain an early `meta skgid 65534 return` rule in
both TCP and UDP output chains. The status page displays whether the running
process actually has GID 65534. If a future OpenClash version removes that
rule, the process remains functional but its traffic may no longer bypass
OpenClash.

## Safety model

The application never opens WAN firewall ports. A listener bound to
`0.0.0.0` is normally reachable from the LAN zone because OpenWrt permits LAN
input by default. Do not add a WAN allow rule for a proxy listener.
