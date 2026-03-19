# AtlasOS app packages (`appinfo.json`)

Installable apps live under **`/home/apps/<package_name>/`**. Each package **must** include **`appinfo.json`** at the package root.

## Required fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Display name (Start menu, `apps`). |

## Optional fields

| Field | Type | Description |
|-------|------|-------------|
| `entry` | string | Script for **`runapp`** (path relative to package or absolute). **Omit** if **`AtlasOS.paint_module`** is set: the desktop loads the painter; **`runapp`** still succeeds and focuses **`window`** when given. |
| `id` | string | App id for pins / `runapp`. Default: parent folder name. Use only `[A-Za-z0-9_-]`. **Must not** collide with built-ins: `welcome`, `files`, `settings`, `console`, `status`, `trash`, `editor`, `search`. |
| `description` | string | Short blurb (`apps`, future UI). |
| `icon` | string **or** string[] | **ASCII / Unicode art:** multiline string (`\n` between rows) or JSON array of row strings. Start menu tiles use up to **4×12** cells; taskbar shows up to **2 rows × 6** columns (trimmed). |
| `icon_compact` | string | Optional **single-row** taskbar glyph (≤6 chars) when full art is too tall/wide. |
| `icon_fg` | string | Default **foreground** color for every icon row (LuaMade names: `bright_cyan`, `yellow`, `red`, …). |
| `icon_bg` | string | Optional **background** behind icon glyphs (taskbar + Start tile). |
| `icon_row_fg` | string[] | Per-row foreground (1-based index matches `icon` rows); overrides `icon_fg` for that row. |
| `icon_taskbar_sel_fg` | string | Foreground when the taskbar slot is **selected** (highlight bar); default `black`. |
| `version` | string / number | Metadata only. |
| `args` | array | Strings/numbers passed to the app as **`_G.AtlasOS_APP.args`** (table of strings). Also used when **`window`** is set (see below). |
| `window` | string | Built-in window title to **focus** after launch (taskbar / `runapp`). If **`window`** is **`"Files"`**, the first **`args`** entry (if non-empty) is treated as a directory and passed to **`UI.files_set_dir`** before the window is focused (same mechanism as the Trash taskbar icon). |
| `AtlasOS` | object | Reserved for future flags (e.g. sandbox, permissions). |

## AtlasOS system packages (`/home/AtlasOS/apps/`)

**All** taskbar + Start menu metadata comes from **`appinfo.json`** here. There are no hard-coded app lists in `startmenu.lua` beyond folder load order:

`welcome` (Guide) → `files` → `console` → `status` → `settings` → `trash` → `search` → `editor`

Then any **other** subfolder of `/home/AtlasOS/apps/` is loaded (by id). User packages under `/home/apps/` **cannot** replace ids registered from `/home/AtlasOS/apps/`.

| `AtlasOS` field | Purpose |
|---------------|---------|
| **`paint_module`** | Lua file relative to package; factory `function(ctx) return function(win) … end end` paints a **built-in window** (e.g. **Files** `explorer.lua`, **Guide** `guide_paint.lua`, **Status** `status_paint.lua`, **Console** `console_paint.lua`, **Settings** `settings_ui.lua`). |
| **`role`**: `"search_engine"` | This package supplies taskbar search. |
| **`search_engine`** | Lua module path (e.g. `search_engine.lua`) returning `{ clear, begin, step, get_state, draw_taskbar }`. |

Example layout:

- `/home/AtlasOS/apps/files/appinfo.json` + `explorer.lua` (entry + `paint_module`)
- `/home/AtlasOS/apps/welcome/appinfo.json` + `guide_paint.lua` (`paint_module` only)
- `/home/AtlasOS/apps/status/appinfo.json` + `status_paint.lua` (`paint_module` only)
- `/home/AtlasOS/apps/console/appinfo.json` + `console_paint.lua` (`paint_module` only)
- `/home/AtlasOS/apps/settings/appinfo.json` + `settings_ui.lua` (entry + `paint_module`)
- `/home/AtlasOS/apps/search/appinfo.json` + `search_engine.lua` + `main.lua` (or entry-only)

A package in **`/home/apps/`** with `role: search_engine` **replaces** the taskbar search implementation (last scan wins).

## Runtime

When the app **`entry`** script is executed (`runapp`):

- **`_G.AtlasOS_APP`** is set to `{ id, package_dir, args }` where `args` is an array of strings from `appinfo.args`.
- After the script returns, `AtlasOS_APP` is cleared.

If there is **no** `entry`, **`runapp <id>`** still succeeds for packages with **`paint_module`** and/or **`window`**, focuses the window, and does not run a script.

Use **`runapp <id>`** from the terminal or launch from the Start menu / taskbar (if pinned).

## Example `appinfo.json`

```json
{
  "id": "demo",
  "name": "Demo App",
  "description": "Sample packaged app",
  "icon": "+",
  "version": "1.0",
  "entry": "main.lua",
  "args": ["--verbose"]
}
```

## Libraries

- LuaMade **`json`** — `require("json")` for `decode` / `encode`.
- **`/home/lib/appinfo.lua`** — `appinfo.load_package(dir)`, `appinfo.scan("/home/apps")`.
- **`/home/lib/appkit.lua`** — Menu bar, dropdowns, and toolbar row for **paint_module** windows (or any code that paints a `window` client). Sets `win._appkit_shell` and receives clicks via the desktop (`handle_click` in client coords). Example:

```lua
local appkit = dofile("/home/lib/appkit.lua")
local shell = appkit.shell({
  on_command = function(id, ctx)
    if id == "quit" then _G.AtlasOS_log[#_G.AtlasOS_log+1] = "Quit" end
  end,
})
shell:set_menubar({
  { label = "File", items = {
    { label = "New", id = "new" },
    { label = "Quit", id = "quit" },
  }},
})
shell:set_toolbar({ { label = "Save", id = "save", w = 8 } })

-- inside paint(win):
shell:attach(win)
shell:paint_decorations(win)
local y0, ch = shell:content_row(), shell:content_height(win)
window.draw_text_line(win, 0, y0, "Content starts row " .. tostring(y0))
-- … draw more using rows y0 .. y0+ch-1 …
shell:paint_dropdown(win)  -- last, so the menu draws over content
```

Refresh the registry after adding packages: **`reload_apps`** (or restart shell).
