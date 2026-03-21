# AtlasOS Web Installer - Installation Guide

This directory contains installers that can be downloaded and run directly in-game using `httpget`.

## Quick Install (One Command)

The fastest way to install AtlasOS in your LuaMade game:

```lua
httpget https://YOURUSERNAME.github.io/AtlasOS/atlasos-web-installer.lua /etc/startup.lua && reboot
```

**Replace `YOURUSERNAME` with your actual GitHub username** (or customize the domain if self-hosting).

## Installation Options

### Option 1: Direct Full Installer (Recommended)
Downloads and runs the complete bundled installer (235 KB) in one command:

```lua
httpget https://YOURUSERNAME.github.io/AtlasOS/atlasos-web-installer.lua /etc/startup.lua
reboot
```

**Files included:**
- `atlasos-web-installer.lua` - Complete 48-file bundle (~235 KB)

### Option 2: Bootstrap Installer
For a two-step install, first download the bootstrap, then it fetches the full installer:

```lua
httpget https://YOURUSERNAME.github.io/AtlasOS/bootstrap.lua /tmp/bootstrap.lua
run /tmp/bootstrap.lua
```

**Files included:**
- `bootstrap.lua` - Lightweight bootstrapper (~2 KB) that downloads the full installer

## What the Installer Does

1. **Downloads files** - Transfers all AtlasOS and library files to your game filesystem
2. **Installs startup hook** - Creates `/etc/startup.lua` to auto-launch AtlasOS at boot
3. **Backs up existing startup** - Previous startup script saved to `/etc/startup.lua.atlasos_backup`
4. **Verifies installation** - Checks all required files are present
5. **Launches AtlasOS** - Automatically starts the desktop environment

## File Breakdown

| File | Size | Purpose |
|------|------|---------|
| `atlasos-web-installer.lua` | ~235 KB | Complete standalone installer with all bundled files |
| `bootstrap.lua` | ~2 KB | Lightweight bootstrapper that downloads the main installer |
| `index.html` | — | Browser interface for this directory |

## Bundled Contents

The installer bundles 48 files:
- **AtlasOS/** - Core OS, desktop, shell, built-in apps, and UI components
- **lib/** - Shared libraries (drawing, colors, themes, settings, etc.)

## Installation Paths (Virtual Filesystem)

Files are installed to these locations in your game:

```
/home/AtlasOS/       (desktop shell, apps, UI, installer)
/home/lib/           (shared libraries)
/etc/startup.lua     (auto-launch hook)
```

## Troubleshooting

### "httpget not found"
Your game may not have HTTP support. Check the LuaMade documentation or try alternative installation methods.

### "permission denied" or "filesystem error"
Ensure your game has filesystem access via:
- `fs.read()` - to read files
- `fs.write()` - to write files

### Installation failed partway through
The installer verifies required files at the end. If a file is missing, it will report which one(s).

### Previous startup script preserved
Your original startup is automatically backed up to `/etc/startup.lua.atlasos_backup` - you can restore it if needed.

## Browser Usage

You can also access this directory from a web browser at:
```
https://YOURUSERNAME.github.io/AtlasOS/
```

This displays an HTML interface with download links and instructions.

## Deployment & Updates

The GitHub Actions workflows automatically:
- **Build** the installer whenever code changes (web-installer.yml)
- **Deploy to GitHub Pages** on every push to main (deploy-to-pages.yml)
- **Create releases** when you tag with `v*` (release-web-installer.yml)

To deploy to your fork:

1. **Enable GitHub Pages** in your repository settings
   - Go to Settings → Pages
   - Set source to "GitHub Actions"

2. **Update the username** in:
   - `dist/index.html` - Change `YOURUSERNAME` to your GitHub username
   - `dist/bootstrap.lua` - Change `YOURUSERNAME` to your GitHub username
   - The in-game installation command you tell users

3. **Push to trigger deployment**
   ```bash
   git push origin main
   ```

## Need Help?

- Check the [main AtlasOS README](../AtlasOS/README.md) for in-game usage
- Review LuaMade documentation: https://garretreichenbach.github.io/Logiscript/
- Open an issue on GitHub with your error message
