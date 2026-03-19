# Graphics (LuaMade official)

Global **`gfx`**: [Text Graphics API](https://garretreichenbach.github.io/Logiscript/markdown/graphics/text-graphics.html).

AtlasOS uses **`gfx.setCellScale`** (global) and **`gfx.setPixelScale(x,y,sx,sy)`** on taskbar icons, Start menu tiles, and the search field so those glyphs use more overlay pixels per cell — see `/etc/AtlasOS/gfx.conf` (`icon_pixel_scale`, `taskbar_icon_pixel_scale`, `search_pixel_scale`).

## Lib modules

### `json.lua`
| API | |
|-----|---|
| `json.decode(str)` | Parse JSON → Lua tables / scalars. |
| `json.encode(val)` | Lua value → JSON string. |

### `atlassettings.lua`
| API | |
|-----|-----|
| `atlassettings.developer_mode()` | Whether Files shows `/home/AtlasOS`. |
| `atlassettings.set_developer_mode(bool)` / `toggle_developer_mode()` | Persist to `/etc/AtlasOS/settings.txt`. |

### `appinfo.lua`
| API | |
|-----|---|
| `appinfo.load_package(dir)` | Read `dir/appinfo.json`, validate. |
| `appinfo.scan("/home/apps")` | List valid packages. |

See **`AtlasOS/APPINFO.md`** for package schema.

### `window.lua`
| API | |
|-----|---|
| `window.new({ x,y,w,h, title, border, …colors })` | `:paint()` `:client_*()` `:set_focused(bool)` |
| `window.draw_text_line(win, col, row, text)` | Clipped to client |
| `window.draw_text_lines(win, lines, start_line)` | 1-based line index |
| `Desktop.new(fg, bg, fill)` | |
| `Desktop.add / remove / remove_at` | |
| `Desktop.bring_to_front(d, win)` | |
| `Desktop.set_focus(d, win)` | Title `*` on focused |
| `Desktop.focus_next(d)` / `focus_prev(d)` | Cycle + bring to front |
| `Desktop.focused(d)` | |
| `Desktop.paint(d)` | |

New windows default **unfocused**; first `add` focuses that window.

### `widgets.lua`
| API | |
|-----|---|
| `log_paint(win, lines, first_line)` | Scrollable log region |
| `log_tail_index(lines, visible_rows)` | 1-based index for tail |
| `button(win, col, row, width, label [, fg, bg])` | One-row `[ label ]` |
| `hrule(win, row [, char])` | Full-width line |
| `label_block(win, col, row, { "…" })` | Multiline |

## Demos
- `demo_gfx.lua` — raw `gfx`
- `demo_windows.lua` — two windows
- `demo_widgets.lua` — log + buttons + focus

Use `term.setAutoPrompt(false)` before repeated `gfx.render()`.

**`input.cancelKeyEvent(e)`** — forwards to mod `cancelEvent(e)` / `consumeEvent` / `cancelKeyEvent` / `discardKeyEvent`. AtlasOS uses it for stray typing when no text field is focused.
