# AtlasOS

**AtlasOS shell:** bottom **taskbar** — **Start [S]** | **search** | fixed **Files / Console** | **your pins** | **Settings** | **Trash**. Middle row (3-line bar): **host · cwd**; bottom row: **left** — computer / **sector** / **system**; **right** — **time + date** (`util.now` + `os.date` when available). **Status** is shown on the bar (no window required); pin the Status app if you want the full panel.

## Install on a LuaMade computer

LuaMade runs **`/etc/startup.lua`** at terminal boot when that file exists ([Startup behavior](https://garretreichenbach.github.io/Logiscript/markdown/core/luamade.html#startup-behavior)).

### Web install via `httpget`

Build the single-file installer from this repo:

```bash
python3 scripts/build_web_installer.py
```

That writes **`dist/atlasos-web-installer.lua`**. Keep that generated file committed when installer sources change; the repository workflow rebuilds it and fails if it drifts from the checked-in copy. Host that file on a web server that LuaMade can reach (for example GitHub raw content or GitHub Pages if the domain is trusted by the server).

- **Rolling/latest channel:** use the `main` branch `dist/atlasos-web-installer.lua` URL shown below.
- **Version-pinned channel:** tag a release like `v1.0.0`; the release workflow rebuilds the installer and uploads the same file as a GitHub Release asset so you can host a stable versioned download URL instead of tracking `main`.

For the simplest in-game install, fetch it straight into **`/etc/startup.lua`** and reboot once:

```text
httpget https://raw.githubusercontent.com/garretreichenbach/AtlasOS/main/dist/atlasos-web-installer.lua /etc/startup.lua
reboot
```

On that next boot, the generated installer unpacks **`AtlasOS/`** into **`/home/AtlasOS/`** and **`Lib/`** into **`/home/lib/`**, rewrites **`/etc/startup.lua`** to the normal AtlasOS boot hook, then launches the first-run setup immediately.

If you need to preserve an existing custom startup script, use the safer two-step flow instead so the installer can back it up to **`/etc/startup.lua.atlasos_backup`** before replacing it:

```text
httpget https://raw.githubusercontent.com/garretreichenbach/AtlasOS/main/dist/atlasos-web-installer.lua /tmp/atlasos-web-installer.lua
run /tmp/atlasos-web-installer.lua
```

1. Copy this repo into the computer’s virtual FS (either layout works):
   - **Full install:** **`Lib/`** → **`/home/lib/`**, **`AtlasOS/`** → **`/home/AtlasOS/`**
   - **Install-from-media:** put the same two folders on a mounted volume (e.g. **`/disk/AtlasOS`**, **`/disk/Lib`**) — the first-run loader **copies** them into **`/home/`** while the progress bar advances. Checked roots include **`/install`**, **`/mnt`**, **`/media`**, **`/disk`**, **`/disk1`**, **`/floppy`**. Optionally set **`/etc/AtlasOS/staging_root.txt`** to a single line (absolute path) if your mount point is elsewhere.
2. Run **`run /home/AtlasOS/installer.lua`**. It checks paths, backs up any existing **`/etc/startup.lua`**, and writes a startup that runs **`installer_gate.lua`**: first boot shows a **copy/verify** loader (real file work, not a fake timer) then **setup** (username + light/dark theme), then writes **`/etc/AtlasOS/setup_complete`** and enters the desktop. Later boots skip setup. To run setup again, delete **`/etc/AtlasOS/setup_complete`** (and optionally **`/etc/AtlasOS/profile.json`** / **`theme.json`**) and reboot. **Updating from an older installer** (startup used to call **`boot_desktop.lua`** only): after copying new files, either run through setup once or create **`/etc/AtlasOS/setup_complete`** (e.g. `fs.write` / equivalent) so the gate skips the wizard.
3. **Reboot** the computer or open a new terminal session.

Without installing startup, you can still run **`run /home/AtlasOS/shell.lua`** then **`desktop`** for the UI only.

**`run /home/AtlasOS/installer.lua uninstall`** — restore the backup startup or remove AtlasOS hook. **`check`** — verify core files exist.

## Taskbar zones

- **Left (fixed):** Files, Console — not in Start menu groups; cannot unpin.
- **Middle:** Only apps you **`pin`** (e.g. Guide, Search, Editor).
- **Right (fixed):** Settings (second-to-last), Trash (last) — cannot unpin.
- **`tasknext` / `docknext`** — cycle highlight over the visible slots (narrow screens may hide some middle pins).
- **`go`** — open the highlighted slot’s window.

## Search (background)

Search runs in **small steps each `refresh`** (cooperative “background” until the mod exposes real threads).

- **`search <text>`** or **`find <text>`** — start name + file-content search under `/home` and `/etc`.
- **`search`** with no args — clear search.
- **`search_status`** — print hit lists in the console.

Taskbar search field shows the query and counts (name / in-file).

## Start menu

- **`start`** — open / close.
- Pins in **`/etc/AtlasOS/start_menu.json`** (`{ "version": 1, "groups": [ { "name": "Pinned", "ids": ["welcome", …] } ] }`) — **user apps only** (not the fixed taskbar icons). Legacy **`start_menu.txt`** is read once and migrated to JSON, then removed.
- **`pin <id> [Group]`** · **`unpin <id>`** · **`pin_group <Name>`**
- App ids: `welcome` (Guide window) `files` `settings` `console` `status` `trash` … — *pinning* `files`/`settings`/`trash`/`console` is ignored for the bar (those stay fixed left/right). **`status`** can be pinned if you want a **Status** window shortcut.

## Other commands

| Command | Action |
|---------|--------|
| `refresh` | Redraw (+ advances search) |
| `theme` | Light / dark (same as Settings → Personalization) |
| `devmode` | `on` / `off` — show `/home/AtlasOS` in Files (system tree) |
| `activities` | Window overview |
| `desktop` | Rebuild desktop + **input loop** (mouse / keys) |
| `save_layout` | Save layout + taskbar selection |
| `winnext` | Focus next visible window (same as **Tab** in desktop) |
| `welcome` / `help` | Focus **Guide** (system info + README) |
| `files` … `console` | Focus window (restores if minimized) |
| `cd` | Files app path |

## Window controls (`desktop` + Input API)

Title bar (right): **`_`** minimize · **`^`** maximize / **`v`** restore · **`x`** close. Drag by the **title** (not on buttons). **Click a window** to raise + focus. Minimized windows appear as **`[Title]`** on the row **above the taskbar** — click to restore. **Tab** cycles focus.

## Keyboard / text input

While **desktop** is running, printable keys and **Backspace** / **Delete** are **cancelled** (via `input.cancelEvent` / `cancelKeyEvent` on the mod) unless a text target is active — currently the **Editor** window when focused. Register more with `UI.extra_input_text_active = function() return … end`. Other keys (Esc, Tab, Enter, arrows, …) still drive the shell.

## Settings

The **Settings** window has a **left category list** (System, Personalization, Apps, Developer, About) and a **right pane** with controls. Click a category, then use buttons (theme, developer mode, open `/home/apps`, reload apps, save layout). Narrow windows show a resize hint.

## Developer mode

By default, **`/home/AtlasOS`** is **hidden** in Files (and `cd` there is blocked). Install apps under **`/home/apps`**. Turn **Developer mode** **ON** in **Settings** or **`devmode on`** to show and open the system tree. Persisted in **`/etc/AtlasOS/settings.txt`**.

## Editor

- **Editor** window (starts **minimized**; not on the fixed taskbar). Open from **Start** or `editor` / `runapp editor [path]`.
- **Ctrl+S** saves to the path in the title bar (default `/home/notes.txt`). Tab inserts two spaces; arrows / Enter / Backspace / Delete as usual.

## Start menu pins (default)

With **no** `start_menu.json` (and no migratable legacy `.txt`), every **user-pinnable** system app appears under **Pinned** (Guide, Search, Editor, Status, … — not Files/Console/Settings/Trash, which stay on fixed taskbar slots).

## System apps (`/home/AtlasOS/apps/`)

Every built-in (Guide via `welcome`, Files, Console, **Chat** — servers/channels on LuaMade **`net`**, …) is a folder with **`appinfo.json`** and usually a **`paint_module`** Lua file (some also use an **`entry`** script for `runapp`). Copy the repo **`AtlasOS/apps/`** tree to **`/home/AtlasOS/apps/`** and **`Lib/atlas_chat_net.lua`** to **`/home/lib/`**. If a package is missing, the taskbar still reserves slots (placeholder `?`) and default pins may show stubs until you install the folder. Chat uses [Network Interface API](https://garretreichenbach.github.io/Logiscript/markdown/io/networking.html) global channels (`openChannel` / `sendChannel` / `receiveChannel`).

## App packages

- Copy folders from **`AtlasOS/packages/`** to **`/home/apps/<name>/`** (each with **`appinfo.json`** + entry script).
- **`apps`** — list package apps · **`runapp <id>`** · **`reload_apps`**
- Spec: **`APPINFO.md`**

## Graphics (LuaMade bitmap `gfx`)

The desktop targets the current [Graphics API](https://garretreichenbach.github.io/Logiscript/markdown/graphics/gfx.html): **pixel** canvas, **layers**, and **`gfx.rect` / `gfx.line` / `gfx.point`** with normalized RGBA. AtlasOS keeps a **logical character grid** (windows, taskbar, hit-tests) and draws through **`/home/lib/atlasgfx.lua`**, which rasterizes an embedded **8×8** font (`font8x8_basic`) into cells. Optional `/etc/AtlasOS/gfx.conf` sets **`cell_scale`** (default `1.5`) to scale cell pixel size. On older hosts that still expose **`gfx.text`** / **`gfx.fillRect(..., " ")`**, atlasgfx passes calls through unchanged.

## Files

- LuaMade **`json`** — `require("json")` in settings/appinfo
- `/home/lib/appinfo.lua` — load `appinfo.json`
- `/home/lib/appkit.lua` — menu bar, dropdowns, toolbar row for window clients (see `APPINFO.md`)
- `/home/lib/startmenu.lua` — registry, groups, fixed-slot rules
- `/home/AtlasOS/ui.lua` — taskbar, search steps, windows
- `/home/.trash` — Trash taskbar icon focuses **Files** here (`appinfo` `args`); legacy layouts may still have a **Trash** window title (same explorer UI)

See **Install on a LuaMade computer** above for `installer.lua` and `/etc/startup.lua`.
