#!/usr/bin/env python3
# Check for package updates and optionally download assets
# Usage: ./check-updates.py [package...]

import json
import os
import re
import sys
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# Colors
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'

def info(msg):
    print(f"{Colors.BLUE}==> {Colors.NC}{msg}")

def success(msg):
    print(f"{Colors.GREEN}✓{Colors.NC} {msg}")

def warn(msg):
    print(f"{Colors.YELLOW}⚠{Colors.NC} {msg}")

def error(msg):
    print(f"{Colors.RED}✗{Colors.NC} {msg}")

SCRIPT_DIR = Path(__file__).parent
DOWNLOAD_DIR = SCRIPT_DIR / "downloads"

def discover_packages(pkg_names=None):
    """Discover packages from srcpkgs directory and determine which support auto-check.
    If pkg_names is provided, only check those specific packages."""
    srcpkgs_dir = SCRIPT_DIR / "srcpkgs"
    if not srcpkgs_dir.exists():
        return [], []
    
    packages = []
    skipped = []
    
    # Determine which packages to check
    if pkg_names:
        pkg_dirs = [srcpkgs_dir / name for name in pkg_names if (srcpkgs_dir / name).is_dir()]
    else:
        pkg_dirs = sorted([d for d in srcpkgs_dir.iterdir() if d.is_dir()])
    
    for pkg_dir in pkg_dirs:
        if not pkg_dir.is_dir():
            continue
        
        pkg_name = pkg_dir.name
        template = pkg_dir / "template"
        
        if not template.exists():
            if pkg_names:  # Only report if user specifically requested this package
                error(f"Package {pkg_name} has no template file")
            continue
        
        # Read template to get distfiles and check if it's GitHub-based
        with open(template) as f:
            content = f.read()
        
        # Extract distfiles (may be indented inside case statements)
        distfiles_match = re.search(r'distfiles=(.+)$', content, re.MULTILINE)
        if not distfiles_match:
            if not pkg_names:  # Only track skipped when checking all
                skipped.append((pkg_name, "no distfiles"))
            elif pkg_names:  # Report when specifically requested
                error(f"Package {pkg_name} has no distfiles")
            continue
        
        distfiles = distfiles_match.group(1).strip().strip('"')
        
        # Check if it's a GitHub release URL
        github_match = re.search(r'github\.com/([^/]+)/([^/]+)/releases', distfiles)
        if not github_match:
            if not pkg_names:  # Only track skipped when checking all
                skipped.append((pkg_name, "not GitHub releases"))
            elif pkg_names:  # Report when specifically requested
                error(f"Package {pkg_name} doesn't use GitHub releases")
            continue
        
        owner = github_match.group(1)
        repo = github_match.group(2)
        
        # Check if this is LyargoOS-Distfiles (multi-package repo)
        is_distfiles = (owner == "Meniny" and repo == "LyargoOS-Distfiles")
        
        # Extract archs
        archs_match = re.search(r'^archs=(.+)$', content, re.MULTILINE)
        if archs_match:
            archs = archs_match.group(1).strip().strip('"')
        else:
            archs = "all"  # Default if not specified
        
        # Determine version transform based on common patterns
        transform = None
        if re.search(r's/\^v//', content):
            # Template strips 'v' prefix
            transform = lambda v: v.lstrip('v')
        
        # For LyargoOS-Distfiles, need to filter by package name and extract version from tag
        if is_distfiles:
            # Tag format: pkg-version (e.g., qq-3.2.32_260812)
            # Extract version part after pkg-
            def distfiles_transform(tag):
                # Remove package prefix (e.g., "qq-" from "qq-3.2.32_260812")
                if tag.startswith(f"{pkg_name}-"):
                    version_part = tag[len(f"{pkg_name}-"):]
                    # Remove build number if present (e.g., "3.2.32_260812" -> "3.2.32")
                    return version_part.split('_')[0]
                return tag
            transform = distfiles_transform
        
        packages.append((pkg_name, f"{owner}/{repo}", transform, archs, is_distfiles))
    
    return packages, skipped

def get_template_info(pkg):
    template = SCRIPT_DIR / "srcpkgs" / pkg / "template"
    if not template.exists():
        return None, None
    
    version = None
    distfiles_pattern = None
    
    with open(template) as f:
        for line in f:
            if line.startswith("version="):
                version = line.split("=", 1)[1].strip()
            elif line.startswith("distfiles="):
                distfiles_pattern = line.split("=", 1)[1].strip().strip('"')
    
    return version, distfiles_pattern

def get_latest_release(repo, pkg_filter=None):
    """Get latest release from GitHub repo.
    If pkg_filter is provided, find the latest release with tag starting with pkg_filter-"""
    if pkg_filter:
        # For multi-package repos, get all releases and filter by package name
        url = f"https://api.github.com/repos/{repo}/releases"
        req = Request(url, headers={"User-Agent": "check-updates"})
        try:
            with urlopen(req, timeout=10) as response:
                releases = json.loads(response.read())
                # Find latest release for this package
                for release in releases:
                    tag = release.get("tag_name", "")
                    if tag.startswith(f"{pkg_filter}-"):
                        return release
                return None
        except (URLError, HTTPError, json.JSONDecodeError) as e:
            return None
    else:
        # Standard single-package repo
        url = f"https://api.github.com/repos/{repo}/releases/latest"
        req = Request(url, headers={"User-Agent": "check-updates"})
        try:
            with urlopen(req, timeout=10) as response:
                return json.loads(response.read())
        except (URLError, HTTPError, json.JSONDecodeError) as e:
            return None

def main():
    # Get package names from arguments
    pkg_names = sys.argv[1:] if len(sys.argv) > 1 else None
    
    # Discover packages (only specific ones if provided)
    packages, skipped = discover_packages(pkg_names)
    
    if not packages:
        if pkg_names:
            error(f"No valid packages found in: {', '.join(pkg_names)}")
        else:
            error("No packages found in srcpkgs/ that support auto-update checking")
            if skipped:
                print(f"\nSkipped {len(skipped)} package(s):")
                for pkg_name, reason in skipped:
                    print(f"  {pkg_name}: {reason}")
        return
    
    info("Checking for package updates...")
    pkg_list = ", ".join([f"{p[0]} ({p[3]})" for p in packages])
    print(f"Packages: {pkg_list}")
    
    # Only show skipped packages when checking all
    if not pkg_names and skipped:
        print(f"\nSkipped {len(skipped)} package(s) (no auto-check):")
        for pkg_name, reason in skipped:
            print(f"  {pkg_name}: {reason}")
    
    print()
    
    updates = []
    
    for pkg, repo, transform, archs, is_distfiles in packages:
        print(f"{Colors.BLUE}Checking{Colors.NC} {pkg}... ", end="", flush=True)
        
        current, distfiles_pattern = get_template_info(pkg)
        if not current:
            print()
            error(f"{pkg}: template not found")
            continue
        
        release = get_latest_release(repo, pkg if is_distfiles else None)
        if not release:
            print()
            error(f"{pkg}: failed to fetch release info")
            continue
        
        latest_raw = release.get("tag_name")
        if not latest_raw:
            print()
            error(f"{pkg}: failed to fetch latest version")
            continue
        
        latest = transform(latest_raw) if transform else latest_raw
        
        if current == latest:
            print(f"{Colors.GREEN}up to date{Colors.NC} ({current})")
        else:
            print(f"{Colors.YELLOW}update available{Colors.NC} ({current} → {latest})")
            
            # Get assets that match the distfiles pattern
            assets = []
            for asset in release.get("assets", []):
                name = asset.get("name", "")
                url = asset.get("browser_download_url", "")
                
                # If we have a distfiles pattern, only show matching assets
                if distfiles_pattern:
                    # Extract filename from pattern (last part after /)
                    pattern_file = distfiles_pattern.split("/")[-1]
                    # Replace version placeholders
                    pattern_file = pattern_file.replace("${version}", latest).replace("${_ver}", latest)
                    # Check if asset name matches the pattern
                    if name == pattern_file:
                        assets.append({"name": name, "url": url})
                else:
                    # No pattern, use smart filtering
                    # Skip non-Linux, source archives, zsync, and update manifests
                    if re.search(r'\.(tar\..*|zip|zsync|mar|exe|dmg)$', name):
                        continue
                    # Skip Windows/macOS specific files
                    if re.search(r'(windows|win|macos|mac|osx)', name, re.IGNORECASE):
                        continue
                    # Only include Linux files
                    if re.search(r'(linux|x86_64|amd64|aarch64|arm64)', name, re.IGNORECASE):
                        assets.append({"name": name, "url": url})
            
            for asset in assets:
                print(f"  {Colors.CYAN}→{Colors.NC} {asset['name']}")
                print(f"    {asset['url']}")
            
            updates.append({
                "pkg": pkg,
                "repo": repo,
                "current": current,
                "latest": latest,
                "assets": assets
            })
    
    print()
    if not updates:
        success("All packages are up to date!")
        return
    
    warn(f"{len(updates)} package(s) have updates available")
    print()
    
    download = input(f"{Colors.CYAN}Download assets? [y/N]: {Colors.NC}").strip().lower()
    if download != 'y':
        info("Download skipped")
        print()
        info("To update a package manually:")
        print("  1. Edit srcpkgs/<pkg>/template and update version=")
        print("  2. Run: xgensum -f srcpkgs/<pkg>/template")
        print("  3. Test build: ./build.sh -p <pkg>")
        return
    
    DOWNLOAD_DIR.mkdir(exist_ok=True)
    
    print()
    info("Downloading assets...")
    
    import hashlib
    
    checksums = []
    
    for update in updates:
        pkg = update["pkg"]
        latest = update["latest"]
        
        print()
        info(f"Downloading {pkg} {latest}...")
        
        for asset in update["assets"]:
            asset_name = asset["name"]
            asset_url = asset["url"]
            asset_path = DOWNLOAD_DIR / asset_name
            
            if asset_path.exists():
                success(f"{asset_name} (already exists, skipping)")
                checksum = hashlib.sha256(asset_path.read_bytes()).hexdigest()
            else:
                print(f"  Downloading {asset_name}... ", end="", flush=True)
                try:
                    req = Request(asset_url, headers={"User-Agent": "check-updates"})
                    with urlopen(req, timeout=30) as response:
                        data = response.read()
                        asset_path.write_bytes(data)
                        print("done")
                        checksum = hashlib.sha256(data).hexdigest()
                except Exception as e:
                    print("failed")
                    continue
            
            checksums.append({
                "pkg": pkg,
                "version": latest,
                "asset": asset_name,
                "checksum": checksum
            })
    
    print()
    success("Download complete!")
    print()
    info("Checksums:")
    
    for item in checksums:
        print(f"  {Colors.CYAN}{item['pkg']}{Colors.NC} {item['version']}")
        print(f"    {item['asset']}")
        print(f"    {Colors.GREEN}{item['checksum']}{Colors.NC}")
    
    print()
    info("To update a package:")
    print("  1. Edit srcpkgs/<pkg>/template and update version= and checksum=")
    print("  2. Test build: ./build.sh -p <pkg>")
    print("  3. Commit and push")

if __name__ == "__main__":
    main()
