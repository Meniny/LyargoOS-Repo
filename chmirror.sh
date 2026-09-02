#!/bin/sh
# Set XBPS mirror for void-packages builds
# Usage: ./mirror.sh [mirror-url]
# If no URL provided, shows interactive menu

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOID_PKGS="${VOID_PKGS:-$(dirname "$SCRIPT_DIR")/void-packages}"

if [ ! -d "$VOID_PKGS/etc/xbps.d" ]; then
    echo "Error: void-packages not found at $VOID_PKGS"
    echo "Set VOID_PKGS environment variable if needed"
    exit 1
fi

# If no argument, show menu
if [ $# -eq 0 ]; then
    echo "Select a mirror:"
    echo ""
    echo "China:"
    echo "  1) Tsinghua University (recommended for China)"
    echo "  2) Aliyun"
    echo "  3) USTC"
    echo ""
    echo "United States:"
    echo "  4) Clarkson University"
    echo "  5) OCF Berkeley"
    echo ""
    echo "Europe:"
    echo "  6) Leaseweb Germany"
    echo "  7) Leaseweb Netherlands"
    echo ""
    echo "Official:"
    echo "  8) Default (repo-default.voidlinux.org)"
    echo ""
    echo "  9) Custom URL"
    echo ""
    printf "Enter choice [1-9]: "
    read -r choice
    
    case "$choice" in
        1) MIRROR="https://mirrors.tuna.tsinghua.edu.cn/voidlinux" ;;
        2) MIRROR="https://mirrors.aliyun.com/voidlinux" ;;
        3) MIRROR="https://mirrors.ustc.edu.cn/voidlinux" ;;
        4) MIRROR="https://mirror.clarkson.edu/voidlinux" ;;
        5) MIRROR="https://mirrors.ocf.berkeley.edu/voidlinux" ;;
        6) MIRROR="https://mirror.de.leaseweb.net/voidlinux" ;;
        7) MIRROR="https://mirror.nl.leaseweb.net/voidlinux" ;;
        8) MIRROR="https://repo-default.voidlinux.org" ;;
        9) 
            printf "Enter custom mirror URL: "
            read -r MIRROR
            if [ -z "$MIRROR" ]; then
                echo "Error: No URL provided"
                exit 1
            fi
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
else
    MIRROR="$1"
fi

echo "Setting XBPS mirror to: $MIRROR"

cd "$VOID_PKGS/etc/xbps.d"

# First reset all mirrors to default
for conf in repos-remote*.conf; do
    if [ -f "$conf" ]; then
        # Reset known mirrors to default
        sed -i 's|https://mirrors.tuna.tsinghua.edu.cn/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
        sed -i 's|https://mirrors.aliyun.com/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
        sed -i 's|https://mirrors.ustc.edu.cn/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
        sed -i 's|https://mirror.clarkson.edu/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
        sed -i 's|https://mirrors.ocf.berkeley.edu/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
        sed -i 's|https://mirror.de.leaseweb.net/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
        sed -i 's|https://mirror.nl.leaseweb.net/voidlinux|https://repo-default.voidlinux.org|g' "$conf"
    fi
done

# Then set the new mirror
if [ "$MIRROR" != "https://repo-default.voidlinux.org" ]; then
    for conf in repos-remote*.conf; do
        if [ -f "$conf" ]; then
            sed -i "s|https://repo-default.voidlinux.org|${MIRROR}|g" "$conf"
            echo "Updated: $conf"
        fi
    done
else
    echo "Reset to default mirror"
    for conf in repos-remote*.conf; do
        if [ -f "$conf" ]; then
            echo "Reset: $conf"
        fi
    done
fi

echo ""
echo "Mirror updated. Restart any running builds to use the new mirror."
