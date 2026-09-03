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
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }

# Highlight helpers
hl_pkg() { echo -e "${MAGENTA}${BOLD}$1${NC}"; }
hl_arch() { echo -e "${CYAN}$1${NC}"; }
hl_ver() { echo -e "${YELLOW}$1${NC}"; }
hl_file() { echo -e "${CYAN}${BOLD}$1${NC}"; }

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
PKG_FILES=""

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

# Show what will be processed and ask for confirmation BEFORE doing anything
echo ""
info "This script will:"
echo "  - Remove old package versions from \"staging/\" folder"
echo "  - Copy new packages from void-packages/hostdir/binpkgs/ to \"staging/\" folder"
echo "  - Delete old assets from GitHub release $TAG"
echo "  - Re-index and sign the repository"
echo "  - Upload new packages to GitHub release $TAG"
echo ""
info "Update details:"
if [ -n "$PKGS" ]; then
    echo -n "  Packages: "
    for pkg in $PKGS; do
        echo -n "$(hl_pkg $pkg) "
    done
    echo ""
fi
if [ -n "$FILES" ]; then
    echo -n "  Files: "
    for file in $FILES; do
        echo -n "$(hl_file $file) "
    done
    echo ""
fi
if [ -n "$TAG" ]; then
    echo -e "  Tag: $(hl_ver $TAG)"
fi
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Aborted by user"
    exit 1
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
info "Verifying release $(hl_ver $TAG) exists..."
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    error "Release $(hl_ver $TAG) does not exist in $REPO"
    error "Create it first with: ./publish.sh"
    exit 1
fi
success "Release $(hl_ver $TAG) found"

VOID_BINPKGS="$SCRIPT_DIR/void-packages/hostdir/binpkgs"

cd "$STAGING"

# Process packages by name
for pkg in $PKGS; do
    echo ""
    info "Processing package: $(hl_pkg $pkg)"
    
    # Find all matching packages in void-packages/hostdir/binpkgs (all architectures)
    pkg_files=$(ls "$VOID_BINPKGS"/${pkg}-[0-9]*.xbps 2>/dev/null || true)
    
    if [ -z "$pkg_files" ]; then
        warn "No built package found for $(hl_pkg $pkg) in $VOID_BINPKGS"
        warn "Build it first with: ./build.sh -p $pkg"
        continue
    fi
    
    # Process each architecture
    for pkg_file in $pkg_files; do
        pkg_basename=$(basename "$pkg_file")
        pkg_pattern=$(echo "$pkg_basename" | sed 's/-[0-9].*//')
        pkg_arch=$(echo "$pkg_basename" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
        pkg_version=$(echo "$pkg_basename" | sed "s/^${pkg_pattern}-//" | sed 's/\.xbps.*//')
        
        info "Found: $(hl_file $pkg_basename) [$(hl_arch $pkg_arch)]"
        
        # Remove old versions from staging (matching this package pattern AND arch)
        for old_pkg in ${pkg_pattern}-[0-9]*.xbps; do
            if [ -f "$old_pkg" ]; then
                old_arch=$(echo "$old_pkg" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
                if [ "$old_arch" = "$pkg_arch" ]; then
                    rm -f "$old_pkg" "${old_pkg}.sig2" 2>/dev/null || true
                    echo -e "  ${RED}✗${NC} Removed old: $old_pkg"
                fi
            fi
        done
        
        # Copy new package
        cp "$pkg_file" .
        echo -e "  ${GREEN}✓${NC} Copied: $pkg_basename"
        
        # Delete old assets from GitHub release (matching this package pattern AND arch)
        NO_COLOR=1 gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' 2>/dev/null | grep "^${pkg_pattern}-[0-9]" | while read asset; do
            asset_arch=$(echo "$asset" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
            if [ "$asset_arch" = "$pkg_arch" ]; then
                echo -e "  ${RED}🗑${NC} Deleting from release: $asset"
                if ! NO_COLOR=1 gh release delete-asset "$TAG" --repo "$REPO" "$asset" --yes >/dev/null 2>&1; then
                    error "Failed to delete $asset from release"
                fi
            fi
        done
        
        # Add to PKG_FILES for upload
        PKG_FILES="$PKG_FILES $pkg_file"
    done
done

# Process specific files
for file in $FILES; do
    if [ ! -f "$file" ]; then
        warn "File not found: $file"
        continue
    fi
    
    file_basename=$(basename "$file")
    pkg_pattern=$(echo "$file_basename" | sed 's/-[0-9].*//')
    file_arch=$(echo "$file_basename" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
    
    # Remove old versions from staging (same package pattern, same arch only)
    for old_pkg in ${pkg_pattern}-[0-9]*.xbps; do
        if [ -f "$old_pkg" ] && [ "$old_pkg" != "$file_basename" ]; then
            old_arch=$(echo "$old_pkg" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
            if [ "$old_arch" = "$file_arch" ]; then
                rm -f "$old_pkg" "${old_pkg}.sig2" 2>/dev/null || true
                echo -e "  ${RED}✗${NC} Removed old: $old_pkg"
            fi
        fi
    done
    
    # Copy to staging if not already there
    if [ "$(dirname "$file")" != "$STAGING" ]; then
        if [ ! -f "$file_basename" ]; then
            cp "$file" .
            echo -e "  ${GREEN}✓${NC} Copied: $file_basename"
        fi
    fi
    
    # Delete old assets from GitHub release (same arch only)
    NO_COLOR=1 gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' 2>/dev/null | grep "^${pkg_pattern}-[0-9]" | while read asset; do
        if [ "$asset" != "$file_basename" ]; then
            asset_arch=$(echo "$asset" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
            if [ "$asset_arch" = "$file_arch" ]; then
                echo -e "  ${RED}🗑${NC} Deleting from release: $asset"
                if ! NO_COLOR=1 gh release delete-asset "$TAG" --repo "$REPO" "$asset" --yes >/dev/null 2>&1; then
                    error "Failed to delete $asset from release"
                fi
            fi
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
for file in $PKG_FILES $FILES; do
    file_basename=$(basename "$file")
    if [ -f "$file_basename" ] && [ ! -f "${file_basename}.sig2" ]; then
        xbps-rindex --privkey "$PRIVKEY" --sign-pkg "$file_basename"
    fi
done

# Upload updated files
echo ""
info "Uploading to release $(hl_ver $TAG)..."

# Combine PKG_FILES and FILES for upload
ALL_FILES="$PKG_FILES $FILES"

for file in $ALL_FILES; do
    file_basename=$(basename "$file")
    file_arch=$(echo "$file_basename" | sed 's/\.xbps.*$//' | awk -F'.' '{print $NF}')
    
    # Upload package file
    if [ -f "$file_basename" ]; then
        echo -e "  ${GREEN}↑${NC} $file_basename [$file_arch]"
        if ! NO_COLOR=1 gh release upload "$TAG" "$file_basename" --repo "$REPO" --clobber >/dev/null 2>&1; then
            error "Failed to upload $file_basename"
            exit 1
        fi
    fi
    # Upload signature if exists
    if [ -f "${file_basename}.sig2" ]; then
        echo -e "  ${GREEN}↑${NC} ${file_basename}.sig2"
        if ! NO_COLOR=1 gh release upload "$TAG" "${file_basename}.sig2" --repo "$REPO" --clobber >/dev/null 2>&1; then
            error "Failed to upload ${file_basename}.sig2"
            exit 1
        fi
    fi
done

# Upload repodata files
for repodata in *-repodata; do
    if [ -f "$repodata" ]; then
        echo -e "  ${GREEN}↑${NC} $repodata"
        if ! NO_COLOR=1 gh release upload "$TAG" "$repodata" --repo "$REPO" --clobber >/dev/null 2>&1; then
            error "Failed to upload $repodata"
            exit 1
        fi
    fi
done

echo ""
success "Done! Updated release: https://github.com/$REPO/releases/tag/$TAG"
