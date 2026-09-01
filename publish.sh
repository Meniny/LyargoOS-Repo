#!/bin/sh
set -e

REPO="Meniny/LyargoOS-Repo"
SIGNEDBY="LyargoOS"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="$SCRIPT_DIR/staging"
PRIVKEY="$STAGING/private.pem"
PUBKEY="$STAGING/$SIGNEDBY.pub"
OVERLAY_XBPSD="$SCRIPT_DIR/../lyargoos/overlay/common/etc/xbps.d"
MODE="create"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo "${BLUE}==>${NC} $1"; }
success() { echo "${GREEN}==>${NC} $1"; }
warn() { echo "${YELLOW}==>${NC} $1"; }
error() { echo "${RED}Error:${NC} $1" >&2; }

usage() {
    echo "Usage: $0 [-n|-r|-R] [tag] [title] [notes]"
    echo ""
    echo "Run without arguments for interactive mode."
    echo ""
    echo "Modes:"
    echo "  -n         Create new tag and release (fails if exists)"
    echo "  -r         Delete and recreate release only (keeps git tag)"
    echo "  -R         Delete and recreate both tag and release"
    echo ""
    echo "Examples:"
    echo "  $0                              # Interactive mode"
    echo "  $0 -n v0.1 \"v0.1 - Initial\" \"Notes\""
    echo "  $0 -r v0.1 \"v0.1 - Updated\" \"Rebuilt\""
    echo "  $0 -R v0.2 \"v0.2 - New\" \"New tag and release\""
    exit 1
}

while getopts "nrRh" opt; do
    case $opt in
        n) MODE="create" ;;
        r) MODE="release" ;;
        R) MODE="both" ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

# Interactive mode if arguments are missing
if [ -z "$1" ]; then
    echo "${CYAN}Mode:${NC} [n]ew, [r]elease only, [R]ecreate all (default: n)"
    printf "> "
    read -r MODE_CHOICE
    case "$MODE_CHOICE" in
        r|R) MODE="release"; [ "$MODE_CHOICE" = "R" ] && MODE="both" ;;
        *) MODE="create" ;;
    esac

    printf "${CYAN}Tag${NC} [v0.1]: "
    read -r TAG
    [ -z "$TAG" ] && TAG="v0.1"

    printf "${CYAN}Title${NC} [$TAG]: "
    read -r TITLE
    [ -z "$TITLE" ] && TITLE="$TAG"

    printf "${CYAN}Notes${NC} [Package release $TAG]: "
    read -r NOTES
    [ -z "$NOTES" ] && NOTES="Package release $TAG"
else
    TAG="$1"
    TITLE="$2"
    NOTES="${3:-Package release $TAG}"
fi

echo ""
echo "${CYAN}Mode:${NC} $MODE"
echo "${CYAN}Tag:${NC} $TAG"
echo "${CYAN}Title:${NC} $TITLE"
echo "${CYAN}Notes:${NC} $NOTES"
echo ""

if [ ! -f "$PRIVKEY" ]; then
    error "private key not found at $PRIVKEY"
    echo "Run the key generation steps in README.md first" >&2
    exit 1
fi

cd "$STAGING"

info "Indexing x86_64 packages..."
rm -f x86_64-repodata
xbps-rindex -a *.x86_64.xbps

# Check for aarch64 packages
if ls *.aarch64.xbps 1>/dev/null 2>&1; then
    info "Indexing aarch64 packages..."
    rm -f aarch64-repodata
    XBPS_ARCH=aarch64 xbps-rindex -a *.aarch64.xbps
fi

info "Initializing signed repository..."
xbps-rindex --privkey "$PRIVKEY" --sign --signedby "$SIGNEDBY" "$STAGING"

# Calculate fingerprint using xbps-fingerprint tool (extracted from XBPS source)
info "Calculating repository fingerprint..."
if [ ! -x "$SCRIPT_DIR/xbps-fingerprint" ]; then
    info "Building xbps-fingerprint tool..."
    make -f "$SCRIPT_DIR/Makefile.fingerprint" -C "$SCRIPT_DIR" >/dev/null 2>&1 || {
        error "Failed to build xbps-fingerprint tool"
        exit 1
    }
fi
# Extract public key from private key first
openssl rsa -in "$PRIVKEY" -pubout -out "$STAGING/temp_pubkey.pem" 2>/dev/null
FINGERPRINT=$("$SCRIPT_DIR/xbps-fingerprint" "$STAGING/temp_pubkey.pem")
rm -f "$STAGING/temp_pubkey.pem"
echo "$FINGERPRINT" > "$STAGING/fingerprint"
info "Fingerprint: $FINGERPRINT"

info "Signing all packages..."
rm -f "$STAGING"/*.sig2
xbps-rindex --privkey "$PRIVKEY" --sign-pkg "$STAGING"/*.xbps

# Extract public key from private key and copy to ISO overlay
# This ensures the ISO always has the matching public key for verification
info "Updating public key in ISO overlay..."
openssl rsa -in "$PRIVKEY" -pubout -out "$PUBKEY" 2>/dev/null
if [ -d "$OVERLAY_XBPSD" ]; then
    cp "$PUBKEY" "$OVERLAY_XBPSD/"
    # Also copy fingerprint if available
    if [ -f "$STAGING/fingerprint" ]; then
        cp "$STAGING/fingerprint" "$SCRIPT_DIR/../lyargoos/overlay/common/etc/xbps.d/"
    fi
else
    error "overlay directory not found: $OVERLAY_XBPSD"
fi

# Ask if user wants to commit fingerprint changes to lyargoos repo
LYARGOOS_DIR="$SCRIPT_DIR/../lyargoos"
if [ -d "$LYARGOOS_DIR" ] && [ -f "$LYARGOOS_DIR/overlay/common/etc/xbps.d/fingerprint" ]; then
    echo ""
    printf "${CYAN}Commit fingerprint to lyargoos repo? [y/N]:${NC} "
    read -r COMMIT_CHOICE
    if [ "$COMMIT_CHOICE" = "y" ] || [ "$COMMIT_CHOICE" = "Y" ]; then
        info "Committing fingerprint to lyargoos repo..."
        cd "$LYARGOOS_DIR"
        git add overlay/common/etc/xbps.d/fingerprint overlay/common/etc/xbps.d/LyargoOS.pub
        git commit -m "Update XBPS repo signing key"
        printf "${CYAN}Push to remote? [y/N]:${NC} "
        read -r PUSH_CHOICE
        if [ "$PUSH_CHOICE" = "y" ] || [ "$PUSH_CHOICE" = "Y" ]; then
            git push
        fi
        cd "$STAGING"
    fi
fi

case "$MODE" in
    create)
        info "Creating git tag..."
        cd "$SCRIPT_DIR"
        git tag "$TAG"
        git push origin "$TAG"
        cd "$STAGING"
        ;;
    release)
        info "Deleting old GitHub release..."
        gh release delete "$TAG" --repo "$REPO" --yes 2>/dev/null || true
        ;;
    both)
        info "Deleting old GitHub release..."
        gh release delete "$TAG" --repo "$REPO" --yes 2>/dev/null || true

        info "Deleting old git tag..."
        git push origin "refs/tags/$TAG" --delete 2>/dev/null || true
        git tag -d "$TAG" 2>/dev/null || true

        info "Creating git tag..."
        cd "$SCRIPT_DIR"
        git tag "$TAG"
        git push origin "$TAG"
        cd "$STAGING"
        ;;
esac

info "Creating GitHub release $TAG..."
gh release create "$TAG" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "$NOTES" \
    *.xbps *.sig2 *-repodata "$(basename "$PUBKEY")"

echo ""
success "Done: https://github.com/$REPO/releases/tag/$TAG"
