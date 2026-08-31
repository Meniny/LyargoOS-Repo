# TODO: lyargoos-welcome

Welcome app for LyargoOS — shown on first login after installation.

## What it should do

- Display LyargoOS branding (logo, version, links)
- Quick links: official website, documentation, community/chat, report a bug
- System info: show CPU, RAM, disk, desktop environment, kernel version
- Optional: enable/disable on startup checkbox
- Optional: links to Flathub, package manager docs, driver setup
- Should work on KDE (Qt), XFCE (GTK), and GNOME (GTK)

## Tech choices (pick one)

- **Python + PyQt6** — cross-DE, easy to develop
- **Bash + yad/zenity** — minimal deps, simple dialogs
- **Rust + gtk4** — fast, small binary, native look on GTK DEs
- **Web-based (electron/tauri)** — modern UI, heavier

## Files needed

```
srcpkgs/lyargoos-welcome/
  template              # XBPS package template
  files/
    lyargoos-welcome    # Main application script/binary
    lyargoos-welcome.desktop  # XDG desktop entry
    autostart/
      lyargoos-welcome.desktop  # XDG autostart (first-boot only)
```

## Integration

- Add `lyargoos-welcome` to `BASE_PACKAGES` in `lyargoos.conf`
- Autostart `.desktop` file in `/etc/xdg/autostart/` (via overlay or package)
- First-boot only: use a flag file like `~/.config/lyargoos-welcome-shown`
  to skip on subsequent logins, or use `OnlyShowIn` / `X-GNOME-Autostart-phase`

## Notes

- Keep it lightweight — this is a Void Linux distro, not Electron bloat
- Should respect the DE's theme (don't hardcode colors)
- i18n would be nice but not critical for v1
