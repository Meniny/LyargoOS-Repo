#!/bin/sh
# Build script for LyargoOS packages
# Usage: ./build.sh [options] [packages...]
#
# Options:
#   -a, --arch ARCH      Build for specific arch (x86_64, aarch64). Can be specified multiple times.
#   -A, --all-archs      Build for all supported architectures
#   -p, --pkg PKG        Build specific package. Can be specified multiple times.
#   -P, --all-pkgs       Build all packages in srcpkgs/
#   -c, --clean          Clean build directory before building
#   -h, --help           Show this help
#
# Examples:
#   ./build.sh -p brave -p flclash -a x86_64          # Build brave and flclash for x86_64 only
#   ./build.sh -P -A                                   # Build all packages for all architectures
#   ./build.sh -p brave                                # Build brave for default arch (x86_64)
#   ./build.sh -p peazip-qt6 -a x86_64                    # Build peazip-qt6 for x86_64

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { printf "${BLUE}==> ${NC}%s\n" "$1"; }
success() { printf "${GREEN}==> ${NC}%s\n" "$1"; }
warn() { printf "${YELLOW}==> ${NC}%s\n" "$1"; }
error() { printf "${RED}Error: ${NC}%s\n" "$1" >&2; }

# Auto-detect paths based on script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOID_PKGS="${VOID_PKGS:-$SCRIPT_DIR/void-packages}"

# Verify paths exist
if [ ! -d "$VOID_PKGS" ]; then
    error "void-packages not found at $VOID_PKGS"
    info "Initialize submodule: git submodule update --init --recursive"
    exit 1
fi

# Default values
ARCHS=""
PKGS=""
CLEAN=0

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -a|--arch)
            ARCHS="$ARCHS $2"
            shift 2
            ;;
        -A|--all-archs)
            ARCHS="x86_64 aarch64"
            shift
            ;;
        -p|--pkg)
            PKGS="$PKGS $2"
            shift 2
            ;;
        -P|--all-pkgs)
            # Get all package names from lyargoos-repo
            PKGS=$(ls "$SCRIPT_DIR/srcpkgs/")
            shift
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        -h|--help)
            head -20 "$0" | tail -16
            exit 0
            ;;
        *)
            # Treat as package name
            PKGS="$PKGS $1"
            shift
            ;;
    esac
done

# Defaults
[ -z "$ARCHS" ] && ARCHS="x86_64"
[ -z "$PKGS" ] && { error "No packages specified. Use -p PKG or -P for all."; exit 1; }

# Ask about cleaning if not specified via flag
if [ "$CLEAN" = 0 ]; then
    info "Packages to build: $PKGS"
    printf "${CYAN}Clean build directories for these packages first? [y/N]: ${NC}"
    read -r CLEAN_CHOICE
    if [ "$CLEAN_CHOICE" = "y" ] || [ "$CLEAN_CHOICE" = "Y" ]; then
        CLEAN=1
    fi
    echo ""
fi

cd "$VOID_PKGS"

# Bootstrap if needed
if [ ! -d "hostdir/masterdir" ]; then
    info "Bootstrapping xbps-src..."
    ./xbps-src binary-bootstrap
    echo ""
fi

# Sync packages from lyargoos-repo
info "Syncing packages from lyargoos-repo..."
for pkg in $PKGS; do
    if [ -d "$SCRIPT_DIR/srcpkgs/$pkg" ]; then
        rm -rf "srcpkgs/$pkg"
        cp -r "$SCRIPT_DIR/srcpkgs/$pkg" "srcpkgs/$pkg"
    else
        warn "Package $pkg not found in lyargoos-repo"
    fi
done

# Clean if requested
if [ "$CLEAN" = 1 ]; then
    info "Cleaning build directories..."
    for pkg in $PKGS; do
        ./xbps-src clean "$pkg" 2>/dev/null || true
    done
fi

# Build each package for each architecture
for arch in $ARCHS; do
    echo ""
    echo "=========================================="
    echo "Building for $arch"
    echo "=========================================="

    for pkg in $PKGS; do
        echo ""
        info "Building $pkg for $arch..."

        if [ "$arch" = "x86_64" ]; then
            ./xbps-src pkg "$pkg"
        else
            ./xbps-src -a "$arch" pkg "$pkg"
        fi

        if [ $? -eq 0 ]; then
            success "$pkg ($arch) built successfully"
        else
            error "$pkg ($arch) failed"
        fi
    done
done

echo ""
success "Build complete!"
info "Packages are in: $VOID_PKGS/hostdir/binpkgs/"
ls -lh "$VOID_PKGS/hostdir/binpkgs/"*.xbps 2>/dev/null | grep -E "$(echo $PKGS | tr ' ' '|')" || echo "No packages found"
