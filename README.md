# LyargoOS XBPS Repository

Custom XBPS package repository for [LyargoOS](https://github.com/Meniny/LyargoOS), a Void Linux-based distribution.

## Packages

| Package | Description | Source |
|---------|-------------|--------|
| `brave` | Brave web browser | Upstream GitHub releases |
| `calamares` | GUI installer (with runit patches for Void) | Upstream Codeberg + Void patches |
| `flclash` | Multi-platform proxy client | Upstream AppImage |
| `peazip` | File archiver and compressor | Upstream tarball |
| `lyargoos-artwork` | Wallpapers, logos, splash | [LyargoOS-Artworks](https://github.com/Meniny/LyargoOS-Artworks) |
| `lyargoos-calamares-config` | Calamares config and LyargoOS branding | [LyargoOS-Repo](https://github.com/Meniny/LyargoOS-Repo) |
| `lyargoos-kde-theme` | KDE Plasma theme (color scheme, SDDM, desktop) | [LyargoOS-Artworks](https://github.com/Meniny/LyargoOS-Artworks) |

## Building Packages

### Prerequisites

You need [void-packages](https://github.com/void-linux/void-packages) to build packages.

```bash
# Clone void-packages
git clone https://github.com/void-linux/void-packages.git
cd void-packages

# Bootstrap (if not already done)
./xbps-src binary-bootstrap
```

### Add this repo as a custom source

```bash
# In your void-packages checkout, add this repo's srcpkgs
# Option 1: Symlink
ln -s /path/to/lyargoos-repo/srcpkgs/* srcpkgs/

# Option 2: Copy
cp -r /path/to/lyargoos-repo/srcpkgs/* srcpkgs/
```

### Build a package

```bash
./xbps-src pkg brave
./xbps-src pkg calamares
./xbps-src pkg flclash
./xbps-src pkg peazip
./xbps-src pkg lyargoos-artwork
./xbps-src pkg lyargoos-calamares-config
./xbps-src pkg lyargoos-kde-theme
```

Built packages are stored in `hostdir/binpkgs/`.

### Custom Icons

To use custom SVG icons for apps (instead of upstream PNGs), place your SVG files in the package's `files/` directory and update the template's `do_install()` to install them. For example:

```bash
# In brave/template do_install():
vinstall ${FILESDIR}/brave.svg 644 usr/share/icons/hicolor/scalable/apps brave-desktop.svg
```

## Hosting the Repository

### Sign packages

```bash
# Generate a signing key (one-time)
openssl genpkey -algorithm ed25519 -out repo.key

# Sign all packages
xbps-rindex --sign -s "your-repo-name" hostdir/binpkgs/

# Generate index
xbps-rindex -a hostdir/binpkgs/
```

### Upload to GitHub Releases

1. Create a GitHub release in this repo
2. Upload all `.xbps` files from `hostdir/binpkgs/` as release assets
3. The repo URL for users will be: `https://github.com/Meniny/LyargoOS-Repo/releases/latest/download`

### Or host on your own server

Serve the `hostdir/binpkgs/` directory via static HTTP. Any web server works (nginx, Caddy, GitHub Pages, Cloudflare R2, etc.).

## Adding the Repo to LyargoOS

In `lyargoos/lyargoos.conf`, add your repo URL:

```bash
REPOS=(
    "https://github.com/Meniny/LyargoOS-Repo/releases/latest/download"
)
```

Then add packages to `EXTRA_PACKAGES` or to flavor-specific `FLAVOR_PKGS`.

## Repository Structure

```
lyargoos-repo/
├── README.md
├── srcpkgs/
│   ├── brave/
│   │   ├── template
│   │   └── files/          # Wrapper script, desktop file, custom icons
│   ├── calamares/
│   │   ├── template
│   │   ├── patches/        # Runit/locale/fstab patches for Void Linux
│   │   └── files/          # Polkit rules
│   ├── flclash/
│   │   ├── template
│   │   └── files/
│   ├── peazip/
│   │   ├── template
│   │   └── files/
│   ├── lyargoos-artwork/
│   │   └── template        # Fetches from LyargoOS-Artworks repo
│   ├── lyargoos-calamares-config/
│   │   ├── template
│   │   └── files/          # Calamares settings, branding, module configs
│   └── lyargoos-kde-theme/
│       └── template        # Fetches from LyargoOS-Artworks repo
```

## Notes

- Pre-built binary packages (brave, flclash, peazip) use `archs="x86_64"` and `nostrip=yes`
- The `distfiles` URLs point to upstream releases — you need to fill in the `checksum` field after first download
- Custom icons (SVG) can be placed in each package's `files/` directory
- The `lyargoos-artwork` and `lyargoos-kde-theme` packages both fetch from the same `lyargoos-artwork` repo but install different files
