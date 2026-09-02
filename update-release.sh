#!/bin/bash
# Update specific packages in an existing GitHub release
# Usage: ./update-release.sh -t <tag> -p <package1> [-p <package2>] ...
#    or: ./update-release.sh -t <tag> -f <file1.xbps> [-f <file2.xbps>] ...
#
# Examples:
#   ./update-release.sh -t v0.1 -p qq -p wechat
#   ./update-release.sh -t latest -p flclash
#   ./update-release.sh -t v0.1 -f staging/qq-3.2.32_1.x86_64.xbps

set -e

REPO="Meniny/LyargoOS-Repo"
SIGNEDBY="LyargoOS"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="$SCRIPT_DIR/staging"
PRIVKEY="$STAGING/private.pem"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }

usage() {
    echo "Usage: $0 -t <tag> (-p <package> | -f <file>) ..."
    echo ""
    echo "Options:"
    echo "  -t TAG       Release tag (or 'latest')"
    echo "  -p PKG       Package name to update (from void-packages/hostdir/binpkgs/)"
    echo "  -f FILE      Specific .xbps file to upload"
    echo "  -h           Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -t v0.1 -p qq -p wechat"
    echo "  $0 -t latest -p flclash"
    echo "  $0 -t v0.1 -f /path/to/qq-3.2.32_1.x86_64.xbps"
    exit 1
}

TAG=""
PKGS=""
FILES=""

while getopts "t:p:f:h" opt; do
    case $opt in
        t) TAG="$OPTARG" ;;
        p) PKGS="$PKGS $OPTARG" ;;
        f) FILES="$FILES $OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$TAG" ]; then
    error "Tag is required (-t)"
    usage
fi

if [ -z "$PKGS" ] && [ -z "$FILES" ]; then
    error "At least one package (-p) or file (-f) is required"
    usage
fi

if [ ! -f "$PRIVKEY" ]; then
    error "Private key not found at $PRIVKEY"
    exit 1
fi

# Check gh (GitHub CLI) is available and authenticated
if ! command -v gh >/dev/null 2>&1; then
    error "gh (GitHub CLI) is not installed"
    error "Install it with: xbps-install -S github-cli"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    error "gh is not authenticated"
    error "Run: gh auth login"
    exit 1
fi

# Resolve 'latest' tag
if [ "$TAG" = "latest" ]; then
    info "Resolving latest release tag..."
    TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || echo "")
    if [ -z "$TAG" ]; then
        error "Could not determine latest release tag"
        exit 1
    fi
    info "Latest tag: $TAG"
fi

# Verify release exists
info "Verifying release $TAG exists..."
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    error "Release $TAG does not exist in $REPO"
    error "Create it first with: ./publish.sh"
    exit 1
fi
success "Release $TAG found"

VOID_BINPKGS="$SCRIPT_DIR/void-packages/hostdir/binpkgs"

cd "$STAGING"

# Process packages by name
for pkg in $PKGS; do
    info "Processing package: $pkg"
    
    # Find the package in void-packages/hostdir/binpkgs
    pkg_file=$(ls "$VOID_BINPKGS"/${pkg}-*.xbps 2>/dev/null | head -n1)
    
    if [ -z "$pkg_file" ]; then
        warn "No built package found for $pkg in $VOID_BINPKGS"
        warn "Build it first with: ./build.sh -p $pkg"
        continue
    fi
    
    pkg_basename=$(basename "$pkg_file")
    info "Found: $pkg_basename"
    
    # Extract package name pattern (e.g., "qq-" from "qq-3.2.32_1.x86_64.xbps")
    pkg_pattern=$(echo "$pkg_basename" | sed 's/-[0-9].*//')
    
    # Remove old versions from staging
    info "Removing old versions from staging..."
    for old_pkg in ${pkg_pattern}-*.xbps; do
        if [ -f "$old_pkg" ]; then
            rm -f "$old_pkg" "${old_pkg}.sig2" 2>/dev/null || true
            echo "  Removed: $old_pkg"
        fi
    done
    
    # Copy new package
    cp "$pkg_file" .
    success "Copied: $pkg_basename"
    
    # Delete old assets from GitHub release
    info "Deleting old assets from release $TAG..."
    gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' | grep "^${pkg_pattern}-" | while read asset; do
        echo "  Deleting: $asset"
        gh release delete-asset "$TAG" --repo "$REPO" "$asset" --yes 2>/dev/null || true
    done
    
    # Add to FILES for upload
    FILES="$FILES $pkg_file"
done

# Process specific files
for file in $FILES; do
    if [ ! -f "$file" ]; then
        warn "File not found: $file"
        continue
    fi
    
    file_basename=$(basename "$file")
    pkg_pattern=$(echo "$file_basename" | sed 's/-[0-9].*//')
    
    info "Processing file: $file_basename"
    
    # Remove old versions from staging
    for old_pkg in ${pkg_pattern}-*.xbps; do
        if [ -f "$old_pkg" ] && [ "$old_pkg" != "$file_basename" ]; then
            rm -f "$old_pkg" "${old_pkg}.sig2" 2>/dev/null || true
            echo "  Removed: $old_pkg"
        fi
    done
    
    # Copy to staging if not already there
    if [ "$(dirname "$file")" != "$STAGING" ]; then
        cp "$file" .
        success "Copied: $file_basename"
    fi
    
    # Delete old assets from GitHub release
    info "Deleting old assets from release $TAG..."
    gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' | grep "^${pkg_pattern}-" | while read asset; do
        if [ "$asset" != "$file_basename" ]; then
            echo "  Deleting: $asset"
            gh release delete-asset "$TAG" --repo "$REPO" "$asset" --yes 2>/dev/null || true
        fi
    done
done

# Re-index and sign
info "Re-indexing packages..."
rm -f x86_64-repodata aarch64-repodata

if ls *.x86_64.xbps 1>/dev/null 2>&1; then
    xbps-rindex -a *.x86_64.xbps
fi

if ls *.aarch64.xbps 1>/dev/null 2>&1; then
    XBPS_ARCH=aarch64 xbps-rindex -a *.aarch64.xbps
fi

info "Re-signing repository..."
xbps-rindex --privkey "$PRIVKEY" --sign --signedby "$SIGNEDBY" "$STAGING"

info "Signing new packages..."
for file in $FILES; do
    file_basename=$(basename "$file")
    if [ -f "$file_basename" ] && [ ! -f "${file_basename}.sig2" ]; then
        xbps-rindex --privkey "$PRIVKEY" --sign-pkg "$file_basename"
    fi
done

# Upload updated files
info "Uploading to release $TAG..."

for file in $FILES; do
    file_basename=$(basename "$file")
    # Upload package file
    if [ -f "$file_basename" ]; then
        info "Uploading: $file_basename"
        gh release upload "$TAG" "$file_basename" --repo "$REPO" --clobber
    fi
    # Upload signature if exists
    if [ -f "${file_basename}.sig2" ]; then
        info "Uploading: ${file_basename}.sig2"
        gh release upload "$TAG" "${file_basename}.sig2" --repo "$REPO" --clobber
    fi
done

# Upload repodata files
for repodata in *-repodata; do
    if [ -f "$repodata" ]; then
        info "Uploading: $repodata"
        gh release upload "$TAG" "$repodata" --repo "$REPO" --clobber
    fi
done

echo ""
success "Done! Updated release: https://github.com/$REPO/releases/tag/$TAG"
