# AtlasOS Graphics Migration Plan
## From `atlasgfx` to `gfx_2d` + `gui_lib`

---

## Overview

This plan replaces all manual graphics calls and the `atlasgfx` adapter with the new
`gfx_2d` drawing API and `gui_lib` component system provided by LuaMade. The migration
is split into two phases:

- **Phase 1** — Replace the low-level drawing plumbing (canvas setup, frame management,
  primitives) so all existing code draws through `gfx_2d` directly instead of through
  `atlasgfx`. The cell-grid abstraction is dropped; all coords move to pixels.
- **Phase 2** — Replace manually-painted UI surfaces (installer, desktop taskbar, start
  menu, windows, apps) with `gui_lib` components, using responsive layout and built-in
  scaling.

---

## API Reference Summary

### `gfx_2d` — low-level pixel drawing

| Purpose | Call |
|---|---|
| Set canvas size | `gfx_2d.setCanvasSize(w, h)` |
| Auto-scale to viewport | `gfx_2d.setAutoScale(true)` |
| Canvas pixel dimensions | `gfx_2d.getWidth()` / `gfx_2d.getHeight()` |
| Physical viewport size | `gfx_2d.getViewportWidth()` / `gfx_2d.getViewportHeight()` |
| Logical→physical scale | `gfx_2d.getScaleX()` / `gfx_2d.getScaleY()` |
| Clear canvas | `gfx_2d.clear()` |
| Batch (anti-flicker) | `gfx_2d.beginBatch()` / `gfx_2d.commitBatch()` |
| Layers | `gfx_2d.createLayer(name, order)`, `gfx_2d.setLayer(name)`, `gfx_2d.clearLayer(name)` |
| Filled rect | `gfx_2d.rect(x, y, w, h, r, g, b, a, true)` |
| Outline rect | `gfx_2d.rect(x, y, w, h, r, g, b, a, false)` |
| Text | `gfx_2d.text(x, y, str, r, g, b, a, scale)` — scale is integer 1–16 |
| Line | `gfx_2d.line(x1, y1, x2, y2, r, g, b, a [, thickness])` |
| Point | `gfx_2d.point(x, y, r, g, b, a)` |

Colors are normalized floats `[0.0, 1.0]` per RGBA channel.

### `gui_lib` — component system

| Component | Constructor |
|---|---|
| Manager (event loop) | `GUIManager.new()` |
| Panel (container) | `Panel.new(x, y, w, h [, title])` |
| Button | `Button.new(x, y, w, h, label, onPress)` |
| Text label | `Text.new(x, y, content)` |
| Horizontal row layout | `HorizontalLayout.new(x, y, h [, spacing])` |
| Vertical column layout | `VerticalLayout.new(x, y, w [, spacing])` |
| Modal dialog | `ModalDialog.new(title, message)` |

Responsive sizing:
```lua
comp:setRelativeRect(rx, ry, rw, rh)          -- fractions [0,1] of canvas
mgr:setLayoutCallback(fn(mgr, w, h))           -- called each frame on resize
comp:setLayoutCallback(fn(self, w, h))
```

---

## Phase 1 — Replace Drawing Plumbing

### 1.1 Introduce `atlas_color.lua` (new small helper)

Create `lib/atlas_color.lua`. Extract the `NAMED` and `NUM` palette tables from
`atlasgfx.lua` and expose a single function:

```lua
-- returns r, g, b, a as normalized floats [0,1]
atlas_color.resolve(c)   -- c may be string name, number (256-color), or {r,g,b,a} table
```

This replaces `color_to_rgba` inside `atlasgfx` and lets every caller convert AtlasOS
color tokens to `gfx_2d`-compatible values without pulling in `atlasgfx`.

### 1.2 Introduce `atlas_draw.lua` (thin pixel-coord wrapper)

Create `lib/atlas_draw.lua`. This is a **temporary** bridge that exposes the same
surface the rest of the codebase calls today (`fillRect`, `rect`, `text`,
`cell_to_pixel`, `pixel_to_cell`), but implemented directly on top of `gfx_2d` and
`atlas_color` with no cell-size state beyond what callers pass in.

Key implementation notes:
- Drop the 1-based cell grid. All coordinates are pixels from this point forward.
  Callers that still pass cell coords will be updated in Phase 2.
- `begin_frame()` → `gfx_2d.beginBatch()` + `gfx_2d.clear()`
- `end_frame()` (new) → `gfx_2d.commitBatch()`  ← add calls everywhere `redraw()` ends
- Text rendering uses `gfx_2d.text()` with a configurable integer `scale` (default `2`),
  replacing the manual 8×8 bitmap font loop and `font8x8_basic.lua`.
- Remove `init()`, `set_canvas_from_cells()`, `canvas_cells()` — callers move to
  `gfx_2d` directly (see 1.3).

### 1.3 Replace canvas management in `ui.lua` and `installer_ui.lua`

Both files contain a `sync_canvas()` / `size_set()` pattern that calls
`atlasgfx.init()` and `atlasgfx.set_canvas_from_cells()`.

Replace with:
```lua
-- Enable auto-scaling so gfx_2d handles viewport scaling automatically.
gfx_2d.setAutoScale(true)
-- Set the logical canvas to the desired pixel resolution.
-- Use getViewportWidth/Height to compute a DPI-aware size,
-- or use a fixed logical resolution and let auto-scale handle it.
local vw = gfx_2d.getViewportWidth()
local vh = gfx_2d.getViewportHeight()
gfx_2d.setCanvasSize(vw, vh)   -- 1:1 with viewport, auto-scale handles DPI
```

Remove `GFX_CONF_PATH` / `read_gfx_conf()` / `cell_scale` config parsing from both
files — the scale concept moves to `gfx_2d.setAutoScale` + the UI scale methods
(see 1.4).

Also remove from `installer.lua` the `"/home/lib/atlasgfx.lua"` entry in the install
file list.

### 1.4 Replace UI scale handling with `gfx_2d` scale methods

Anywhere the code reads `atlasgfx.cell_w` / `atlasgfx.cell_h` to figure out pixel
density (e.g. `guide_paint.lua` lines 49–51), replace with:

```lua
local sx = gfx_2d.getScaleX()   -- logical-to-physical multiplier
local sy = gfx_2d.getScaleY()
```

Use `gfx_2d.getViewportWidth()` / `gfx_2d.getViewportHeight()` for anything that
needs the physical render area, and `gfx_2d.getWidth()` / `gfx_2d.getHeight()` for
the logical canvas.

### 1.5 Replace mouse hit-testing

`atlasgfx.pixel_to_cell_rel()` is currently called in `ui.lua:771` and
`installer_ui.lua:250` to convert raw `uiX`/`uiY` pixel events to cell coordinates.

With pixel-native coordinates this becomes a no-op or trivial clamping helper.
`gui_lib` components handle their own hit testing via `comp:pointInBounds(px, py)`,
so callers that use `GUIManager` no longer need this at all (Phase 2). For Phase 1,
retain a simple helper:

```lua
-- coord is already in logical pixels; just return it
local function ui_px(uiX, uiY) return uiX, uiY end
```

### 1.6 Update all `atlasgfx` call sites to `atlas_draw`

Files to update (mechanical find-and-replace of `dofile("/home/lib/atlasgfx.lua")`
→ `dofile("/home/lib/atlas_draw.lua")` and update any coord math that assumed cell
units):

| File | atlasgfx calls to migrate |
|---|---|
| `lib/window.lua` | `fillRect`, `rect`, `text` (window chrome + desktop bg + canvas_cells) |
| `lib/widgets.lua` | `text` (draw_text_line, draw_text_lines, button) |
| `AtlasOS/ui.lua` | `fillRect`, `rect`, `text` (taskbar, start menu) + canvas init |
| `AtlasOS/installer_ui.lua` | `begin_frame`, `fillRect`, `text` + canvas init |
| `AtlasOS/apps/editor/editor_paint.lua` | `text` |
| `AtlasOS/apps/chat/chat_paint.lua` | `fillRect`, `text` (via context) |
| `AtlasOS/apps/settings/settings_ui.lua` | `fillRect`, `text` |
| `AtlasOS/apps/welcome/guide_paint.lua` | `cell_w`, `cell_h` references |
| `AtlasOS/apps/search/search_engine.lua` | `draw_taskbar` signature takes `ag` facade |

`ui.lua` also passes `atlasgfx` in the context table (`ctx.atlasgfx`) to
`builtin_window_paint`, `chat_paint`, `guide_paint`, and `search_engine`. Update
the context key to `draw` (or `gfx`) and pass the new `atlas_draw` module.

### 1.7 Delete `lib/atlasgfx.lua` and `lib/font8x8_basic.lua`

Once all call sites are updated and tested, remove both files. The 8×8 bitmap font
is superseded by `gfx_2d.text()`.

---

## Phase 2 — Migrate to `gui_lib` Components

Phase 2 replaces manually-painted surfaces with `gui_lib` components. Work
surface-by-surface so each can be tested independently.

### 2.1 Installer UI (`installer_ui.lua`)

The installer has three discrete screens: loading, error, setup. Each maps cleanly
to a `GUIManager` + `Panel` + `Text`/`Button` layout.

**Loading screen:**
```
GUIManager
  └─ Panel (full canvas, blue bg)
       ├─ Text "AtlasOS"           (centered, title scale)
       ├─ Text <load_title>        (centered)
       ├─ Text <load_detail>       (left-aligned)
       ├─ Panel progress-bar bg    (white, relative width)
       │    └─ Panel progress fill (green, width = fraction × bar_w)
       └─ Text "XX%"               (centered below bar)
```

Use `mgr:setLayoutCallback` to recompute bar widths each frame from `state.progress`.

**Setup screen:**
```
GUIManager
  └─ Panel (full canvas, theme bg)
       ├─ Text "Welcome to AtlasOS"
       ├─ Text "Username"
       ├─ Text <username_display>  (simulated input field)
       ├─ Text "Theme"
       ├─ Button "[ Light ]"       (onPress → state.theme = "light")
       ├─ Button "[ Dark ]"        (onPress → state.theme = "dark")
       ├─ Button "[  Continue — Enter  ]"  (onPress → finish_setup())
       └─ Text <hint>
```

Mouse event handling for theme chips and continue button moves to button `onPress`
callbacks; `handle_mouse` can be removed. Key handling for Tab/Enter/Backspace
remains in the event loop but drives focus via `btn:setEnabled` + manual focus state.

Replace `gfx.conf` / `cell_scale` with `gfx_2d.setAutoScale(true)` (see 1.3).

### 2.2 Desktop Taskbar (`ui.lua` → `UI.draw_taskbar`)

Replace manual row-of-text rendering with a `HorizontalLayout`:

```
HorizontalLayout (bottom strip, height = TASKBAR_H px)
  ├─ Button "[S]"         (start menu toggle)
  ├─ Panel  search bar    (Text placeholder; will expand in 2.5)
  ├─ Button <app slot>…   (one per taskbar pin, setNormalColor / setHoverColor)
  ├─ Text   status line   (center, setRelativeRect for flexible gap)
  └─ Text   clock/world   (right-aligned)
```

App slot buttons use `btn:setHoverColor` / `btn:setNormalColor` for selected state
instead of manual `fillRect` highlight. Icon rows inside slots use `btn:setLabel`.

### 2.3 Start Menu (`ui.lua` → `UI.draw_start_menu`)

Replace with a `Panel` (absolute-positioned, rendered on "overlay" layer):

```
Panel (px, py, pw, ph, title=nil)   -- setLayer("overlay")
  ├─ Text "Search apps and files…"
  ├─ Text "── Pinned (groups) ──"
  ├─ (per group) Text <group name>
  │    └─ HorizontalLayout of Buttons (one per app tile)
  ├─ Text "── All apps ──"
  └─ (per app) HorizontalLayout (icon Button + Text label)
```

App tile Buttons use `setNormalColor` for the tile background and `setLabelScale`
for the multi-row icon text.

### 2.4 Window Chrome (`lib/window.lua`)

The current `win:draw()` paints a title bar and border manually. Replace with a
`Panel` per window:

```
Panel (x, y, w, h, title=win.title)
  ├─ panel:setBorderColor(body_fg rgba)
  ├─ panel:setBackgroundColor(body_bg rgba)
  ├─ panel:setTitleScale(2)
  ├─ Button "_"   (minimize, top-right area)
  ├─ Button "^/v" (maximize toggle)
  └─ Button "x"   (close)
```

Window dragging continues via `mgr:setMouseOffset` + hit-test on title bar area.
Client content area remains a child zone where app paint callbacks render via
`atlas_draw` (or their own `gui_lib` components).

### 2.5 `lib/widgets.lua`

Replace the `draw_text_line` / `draw_text_lines` pattern with `gui_lib` Text
components owned by each caller, or retain `atlas_draw.text()` calls since widgets
is a thin helper. Evaluate on a case-by-case basis:

- `widgets.log_paint` — keep as `atlas_draw.text()` rows (scrollable log doesn't
  benefit from a Text component)
- `widgets.button` — replace with `gui_lib.Button`; simplifies hover/pressed state
- `widgets.hrule` — replace with `gfx_2d.line()`

### 2.6 App paint callbacks (chat, editor, settings, guide)

Each app paint callback currently receives `atlasgfx` via `ctx`. After Phase 1 they
receive `atlas_draw`. In Phase 2 each can be progressively upgraded:

| App | Recommended approach |
|---|---|
| **editor** (`editor_paint.lua`) | Keep line-by-line `atlas_draw.text()` — a code editor is a scrollable text grid, not a widget tree |
| **chat** (`chat_paint.lua`) | Server/channel sidebars → `VerticalLayout` of `Button`s; message area → scrollable `Text`; input → custom `Component` |
| **settings** (`settings_ui.lua`) | Replace manual `text`/`fillRect` with `VerticalLayout` + `Text` + `Button` |
| **guide/welcome** (`guide_paint.lua`) | Replace with `Text` (multi-line, word-wrap via `setLayout`) |
| **console** (`console_paint.lua`) | Keep as scrollable `atlas_draw.text()` rows (same as editor rationale) |
| **status** (`status_paint.lua`) | Replace with `HorizontalLayout` of `Text` labels |

---

## UI Scale Integration

Wherever the current code reads `atlasgfx.cell_w` / `cell_h` or `cell_scale` from
`gfx.conf`, replace with `gfx_2d` scale methods:

```lua
-- Logical canvas size
local cw = gfx_2d.getWidth()
local ch = gfx_2d.getHeight()

-- Physical viewport (for DPI-aware sizing decisions)
local vw = gfx_2d.getViewportWidth()
local vh = gfx_2d.getViewportHeight()

-- Scaling factor (use to size text scale, padding, icon sizes)
local sx = gfx_2d.getScaleX()   -- e.g. 2.0 on a HiDPI display
local sy = gfx_2d.getScaleY()

-- Recommended text scale: round up to nearest integer
local text_scale = math.max(1, math.floor(sy + 0.5))
```

Use `mgr:setLayoutCallback` so all component positions/sizes recompute whenever the
canvas is resized (terminal window resize):

```lua
mgr:setLayoutCallback(function(m, w, h)
  taskbar:setSize(w, TASKBAR_H)
  taskbar:setPosition(0, h - TASKBAR_H)
  desktop:setSize(w, h - TASKBAR_H)
  -- recalculate text_scale from gfx_2d.getScaleY() here too
end)
```

`gfx.conf` and `read_gfx_conf()` can be removed from all files once auto-scale is
active and `setLayoutCallback` handles resize.

---

## Files Affected Summary

| File | Phase 1 changes | Phase 2 changes |
|---|---|---|
| `lib/atlasgfx.lua` | replaced by `atlas_draw.lua` | deleted |
| `lib/font8x8_basic.lua` | unused after Phase 1 | deleted |
| `lib/atlas_color.lua` | **new** | — |
| `lib/atlas_draw.lua` | **new** (gfx_2d wrapper) | thinned / removed |
| `lib/window.lua` | swap atlasgfx → atlas_draw | window chrome → gui_lib Panel |
| `lib/widgets.lua` | swap atlasgfx → atlas_draw | button → gui_lib Button |
| `lib/builtin_window_paint.lua` | swap ctx.atlasgfx → ctx.draw | — |
| `AtlasOS/ui.lua` | canvas init → gfx_2d; swap calls | taskbar + start menu → gui_lib |
| `AtlasOS/installer_ui.lua` | canvas init → gfx_2d; swap calls | all screens → gui_lib |
| `AtlasOS/installer.lua` | remove atlasgfx from install list | — |
| `AtlasOS/apps/editor/editor_paint.lua` | swap atlasgfx → atlas_draw | keep as-is |
| `AtlasOS/apps/chat/chat_paint.lua` | swap ctx.atlasgfx → ctx.draw | sidebars + input → gui_lib |
| `AtlasOS/apps/settings/settings_ui.lua` | swap atlasgfx → atlas_draw | → gui_lib |
| `AtlasOS/apps/welcome/guide_paint.lua` | remove cell_w/cell_h refs | → gui_lib Text |
| `AtlasOS/apps/search/search_engine.lua` | update draw_taskbar signature | — |
| `AtlasOS/apps/console/console_paint.lua` | swap atlasgfx → atlas_draw | keep as-is |
| `AtlasOS/apps/status/status_paint.lua` | swap atlasgfx → atlas_draw | → gui_lib |

---

## Suggested Implementation Order

1. `lib/atlas_color.lua` (no dependencies, unblocks everything)
2. `lib/atlas_draw.lua` (depends on atlas_color + gfx_2d)
3. `lib/widgets.lua` swap (isolated, easy to test)
4. `lib/window.lua` swap (enables window rendering to work)
5. `AtlasOS/ui.lua` canvas init + call site swap
6. `AtlasOS/installer_ui.lua` canvas init + call site swap
7. All app paint files swap
8. Delete `atlasgfx.lua` + `font8x8_basic.lua`
9. Phase 2 surfaces, one per PR: installer → desktop taskbar → start menu → windows → apps
