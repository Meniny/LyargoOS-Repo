#!/bin/bash
# LyargoOS Repository Manager
# Manage the LyargoOS XBPS repository on Void Linux

set -e

REPO_CONF="/usr/share/xbps.d/99-lyargoos.conf"
REPO_URL="https://repo.lyargoos.org/current"
REPO_LINE="repository=${REPO_URL}"

usage() {
	cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  install     Add the LyargoOS repository to XBPS
  uninstall   Remove the LyargoOS repository from XBPS
  enable      Re-enable a disabled LyargoOS repository
  disable     Temporarily disable the LyargoOS repository (comment out)
  status      Show whether the repository is installed and enabled

EOF
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "Error: this command requires root privileges." >&2
		exit 1
	fi
}

cmd_install() {
	require_root
	if [ -f "$REPO_CONF" ]; then
		echo "LyargoOS repository is already installed at $REPO_CONF"
		exit 0
	fi
	echo "$REPO_LINE" > "$REPO_CONF"
	echo "LyargoOS repository installed."
	echo "Run 'xbps-install -S' to sync the package index."
}

cmd_uninstall() {
	require_root
	if [ ! -f "$REPO_CONF" ]; then
		echo "LyargoOS repository is not installed."
		exit 0
	fi
	rm -f "$REPO_CONF"
	echo "LyargoOS repository removed."
}

cmd_enable() {
	require_root
	if [ ! -f "$REPO_CONF" ]; then
		echo "LyargoOS repository is not installed. Run '$(basename "$0") install' first." >&2
		exit 1
	fi
	if grep -q "^#[[:space:]]*repository=" "$REPO_CONF"; then
		sed -i "s|^#[[:space:]]*repository=|repository=|" "$REPO_CONF"
		echo "LyargoOS repository enabled."
	else
		echo "LyargoOS repository is already enabled."
	fi
}

cmd_disable() {
	require_root
	if [ ! -f "$REPO_CONF" ]; then
		echo "LyargoOS repository is not installed. Run '$(basename "$0") install' first." >&2
		exit 1
	fi
	if grep -q "^repository=" "$REPO_CONF"; then
		sed -i "s|^repository=|#repository=|" "$REPO_CONF"
		echo "LyargoOS repository disabled."
	else
		echo "LyargoOS repository is already disabled."
	fi
}

cmd_status() {
	if [ ! -f "$REPO_CONF" ]; then
		echo "LyargoOS repository: not installed"
		exit 0
	fi
	if grep -q "^repository=" "$REPO_CONF"; then
		echo "LyargoOS repository: enabled"
	elif grep -q "^#[[:space:]]*repository=" "$REPO_CONF"; then
		echo "LyargoOS repository: disabled"
	else
		echo "LyargoOS repository: installed (unexpected content in $REPO_CONF)"
	fi
	echo "Config: $REPO_CONF"
	echo "URL:    $REPO_URL"
}

case "${1:-}" in
	install)   cmd_install ;;
	uninstall) cmd_uninstall ;;
	enable)    cmd_enable ;;
	disable)   cmd_disable ;;
	status)    cmd_status ;;
	*)         usage; exit 1 ;;
esac
