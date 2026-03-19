# DovOS

**Windows 11–style shell:** bottom **taskbar** — **Start [S]** | **search** | fixed **Files / Console / Status** | **your pins** | **Settings** | **Trash**. Bottom strip: **left** — computer block name · **sector** · **system** (LuaMade `Entity` API); **right** — **time + date** (`util.now` + `os.date` when available).

## Taskbar zones

- **Left (fixed):** Files, Console, Status — not in Start menu groups; cannot unpin.
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
- Pins in **`/etc/dovos/start_menu.txt`** — **user apps only** (not the fixed taskbar icons).
- **`pin <id> [Group]`** · **`unpin <id>`** · **`pin_group <Name>`**
- App ids: `welcome` (Guide window) `files` `settings` `console` `status` `trash` … — *pinning* `files`/`settings`/`trash`/`console`/`status` is ignored for the bar (those stay fixed left/right).

## Other commands

| Command | Action |
|---------|--------|
| `refresh` | Redraw (+ advances search) |
| `theme` | Light / dark (same as Settings → Personalization) |
| `devmode` | `on` / `off` — show `/home/dovos` in Files (system tree) |
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

By default, **`/home/dovos`** is **hidden** in Files (and `cd` there is blocked). Install apps under **`/home/apps`**. Turn **Developer mode** **ON** in **Settings** or **`devmode on`** to show and open the system tree. Persisted in **`/etc/dovos/settings.txt`**.

## Editor

- **Editor** window (starts **minimized**; not on the fixed taskbar). Open from **Start** or `editor` / `runapp editor [path]`.
- **Ctrl+S** saves to the path in the title bar (default `/home/notes.txt`). Tab inserts two spaces; arrows / Enter / Backspace / Delete as usual.

## Start menu pins (default)

With **no** `/etc/dovos/start_menu.txt`, every **user-pinnable** system app appears under **Pinned** (Guide, Search, Editor, … — not Files/Console/Status/Settings/Trash, which stay on the taskbar).

## System apps (`/home/dovos/apps/`)

Every built-in (Guide via `welcome`, Files, Console, Status, Settings, Trash, Search, …) is a folder with **`appinfo.json`** + **`main.lua`**. Copy the full repo **`DovOS/apps/`** tree to **`/home/dovos/apps/`**. If a package is missing, the taskbar still reserves slots (placeholder `?`) and default pins may show stubs until you install the folder.

## App packages

- Copy folders from **`DovOS/packages/`** to **`/home/apps/<name>/`** (each with **`appinfo.json`** + entry script).
- **`apps`** — list package apps · **`runapp <id>`** · **`reload_apps`**
- Spec: **`APPINFO.md`**

## Canvas / sharper graphics (LuaMade)

DovOS uses the **`canvas`** gfx backend (overlay layers) and **`gfx.setCellScale`** so each character cell can use more screen pixels — see [Text Graphics API](https://garretreichenbach.github.io/Logiscript/markdown/graphics/text-graphics.html).

- **Defaults** (override in `/etc/dovos/gfx.conf`): `cell_scale=1.5`, plus **`setPixelScale`** regions — **`icon_pixel_scale`** (Start tiles), **`taskbar_icon_pixel_scale`**, **`search_pixel_scale`** for extra-crisp icons and search without changing layout.
- Example: copy **`gfx.conf.example`** → **`/etc/dovos/gfx.conf`**.
- If the server disables canvas (`gfx_canvas_backend_enabled=false`), fall back with `gfx.setBackend("terminal")` in a custom boot script — DovOS only calls `setBackend("canvas")` when available.
- **Guide** window shows **cell scale** when `gfx.getCellScale` exists, plus **`/home/dovos/README.txt`** when present.

## Files

- `/home/lib/json.lua` — JSON parse/stringify
- `/home/lib/appinfo.lua` — load `appinfo.json`
- `/home/lib/startmenu.lua` — registry, groups, fixed-slot rules
- `/home/dovos/ui.lua` — taskbar, search steps, windows
- `/home/.trash` — Trash window lists this folder

**Installer:** `installer.lua` may lag the repo; copy updated `ui.lua` / `shell.lua` / `window.lua` / `startmenu.lua` manually if needed.
