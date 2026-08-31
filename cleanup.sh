#!/bin/sh
set -e

REPO="Meniny/LyargoOS-Repo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo "${GREEN}==>${NC} $1"; }
warn() { echo "${YELLOW}==>${NC} $1"; }
error() { echo "${RED}Error:${NC} $1" >&2; }

cd "$SCRIPT_DIR"

# Collect all tags (local + remote combined)
info "Fetching tags..."
LOCAL_TAGS=$(git tag -l 2>/dev/null || true)
REMOTE_TAGS=$(git ls-remote --tags origin 2>/dev/null | awk -F'/' '{print $3}' | grep -v '\^{}' || true)
RELEASE_TAGS=$(gh release list --repo "$REPO" --limit 1000 2>/dev/null | awk '{print $1}' || true)

# Merge and deduplicate
ALL_TAGS=$(printf "%s\n%s\n%s\n" "$LOCAL_TAGS" "$REMOTE_TAGS" "$RELEASE_TAGS" | sort -u | grep -v '^$' || true)

if [ -z "$ALL_TAGS" ]; then
    warn "No tags found."
    exit 0
fi

# Build whiptail checklist
MENU_ITEMS=""
for TAG in $ALL_TAGS; do
    HAS_LOCAL=""
    HAS_REMOTE=""
    HAS_RELEASE=""

    echo "$LOCAL_TAGS" | grep -qx "$TAG" && HAS_LOCAL="local"
    echo "$REMOTE_TAGS" | grep -qx "$TAG" && HAS_REMOTE="remote"
    echo "$RELEASE_TAGS" | grep -qx "$TAG" && HAS_RELEASE="release"

    STATUS=$(printf "%s %s %s" "$HAS_LOCAL" "$HAS_REMOTE" "$HAS_RELEASE" | xargs | tr ' ' ',')
    [ -z "$STATUS" ] && STATUS="unknown"

    MENU_ITEMS="$MENU_ITEMS $TAG \"$STATUS\" OFF"
done

# Show whiptail checklist
SELECTED=$(whiptail --title "Delete Tags" \
    --checklist "Select tags to delete (releases with same name will also be deleted):" \
    20 70 15 \
    $MENU_ITEMS \
    3>&1 1>&2 2>&3) || exit 1

if [ -z "$SELECTED" ]; then
    echo "No tags selected."
    exit 0
fi

# Process selected tags
for TAG in $SELECTED; do
    TAG=$(echo "$TAG" | tr -d '"')

    # Delete GitHub release if exists
    if echo "$RELEASE_TAGS" | grep -qx "$TAG"; then
        info "Deleting release: $TAG"
        gh release delete "$TAG" --repo "$REPO" --yes 2>/dev/null || true
    fi

    # Delete remote tag if exists
    if echo "$REMOTE_TAGS" | grep -qx "$TAG"; then
        info "Deleting remote tag: $TAG"
        git push origin "refs/tags/$TAG" --delete 2>/dev/null || true
    fi

    # Delete local tag if exists
    if echo "$LOCAL_TAGS" | grep -qx "$TAG"; then
        info "Deleting local tag: $TAG"
        git tag -d "$TAG" 2>/dev/null || true
    fi
done

echo ""
info "Done."
