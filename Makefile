include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-socks-proxy
PKG_VERSION:=0.2.0
PKG_RELEASE:=4
PKG_LICENSE:=MIT
PKG_MAINTAINER:=luci-socks contributors

LUCI_TITLE:=LuCI support for isolated SOCKS5 and HTTP proxies
LUCI_DESCRIPTION:=Manage sing-box nodes and authenticated SOCKS5/HTTP listeners without transparent proxying.
LUCI_DEPENDS:=+luci-base +sing-box +ucode +ucode-mod-uci +ucode-mod-fs +curl +ca-bundle
LUCI_PKGARCH:=all

PKG_CONFIG_DEPENDS:=

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
