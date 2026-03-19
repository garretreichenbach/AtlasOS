--[[
  widgets.lua — UI helpers on gfx + a window’s client rect.
  Standalone (no require of window.lua); uses same client geometry as window.new.

  local W = dofile("/home/lib/widgets.lua")
  W.log_paint(win, lines, first_visible_line_1based)
  idx = W.log_tail_index(lines, win:client_h())
  W.button(win, col, row, width, label [, fg, bg])
  W.hrule(win, row [, char])
  W.label_block(win, col, row, { "a", "b" })
]]

local widgets = {}

local function draw_text_line(win, rel_col, rel_row, text)
  local cw, ch = win:client_w(), win:client_h()
  rel_col, rel_row = math.floor(rel_col or 0), math.floor(rel_row or 0)
  if rel_row < 0 or rel_row >= ch or rel_col < 0 or rel_col >= cw then return end
  local maxc = cw - rel_col
  text = tostring(text)
  if #text > maxc then text = text:sub(1, maxc) end
  gfx.setColor(win.client_fg, win.client_bg)
  gfx.text(win:client_x() + rel_col, win:client_y() + rel_row, text)
end

local function draw_text_lines(win, lines, start_line)
  lines = lines or {}
  start_line = math.max(1, math.floor(start_line or 1))
  local ch, cw = win:client_h(), win:client_w()
  if ch < 1 or cw < 1 then return end
  gfx.setColor(win.client_fg, win.client_bg)
  for row = 0, ch - 1 do
    local line = lines[start_line + row]
    if line then
      line = tostring(line)
      if #line > cw then line = line:sub(1, cw) end
      gfx.text(win:client_x(), win:client_y() + row, line)
    end
  end
end

function widgets.log_paint(win, lines, first_line)
  draw_text_lines(win, lines, first_line)
end

function widgets.log_tail_index(lines, visible_rows)
  local n = #(lines or {})
  visible_rows = math.max(1, math.floor(visible_rows or 1))
  if n <= visible_rows then return 1 end
  return n - visible_rows + 1
end

function widgets.button(win, col, row, width, label, fg, bg)
  fg, bg = fg or "bright_white", bg or "blue"
  local cx, cy = win:client_x(), win:client_y()
  local cw, ch = win:client_w(), win:client_h()
  col, row = math.floor(col), math.floor(row)
  width = math.max(3, math.floor(width))
  if row < 0 or row >= ch or col < 0 or col + width > cw then return end
  label = tostring(label or "")
  local inner = width - 2
  if #label > inner then label = label:sub(1, inner) end
  local s = "[" .. label .. string.rep(" ", inner - #label) .. "]"
  gfx.setColor(fg, bg)
  gfx.fillRect(cx + col, cy + row, width, 1, " ")
  gfx.text(cx + col, cy + row, s)
end

function widgets.hrule(win, row, ch)
  ch = (ch and tostring(ch):sub(1, 1)) or "-"
  local cw = win:client_w()
  if cw < 1 then return end
  row = math.floor(row)
  if row < 0 or row >= win:client_h() then return end
  gfx.setColor(win.client_fg, win.client_bg)
  gfx.text(win:client_x(), win:client_y() + row, string.rep(ch, cw))
end

function widgets.label_block(win, col, row, text_lines)
  col, row = math.floor(col), math.floor(row)
  for i, line in ipairs(text_lines or {}) do
    draw_text_line(win, col, row + i - 1, line)
  end
end

--- Draw a list of items (strings or {text, dir=true}); start_index 1-based into items, max_visible rows, dest_row 0-based.
function widgets.list_box(win, items, start_index, max_visible, dest_row)
  items = items or {}
  start_index = math.max(1, math.floor(start_index or 1))
  max_visible = math.max(0, math.floor(max_visible or win:client_h()))
  dest_row = math.max(0, math.floor(dest_row or 0))
  local cw = win:client_w()
  for i = 0, max_visible - 1 do
    local item = items[start_index + i]
    if not item then break end
    local text = type(item) == "table" and (item.text or "") or tostring(item)
    local prefix = (type(item) == "table" and item.dir) and "[d] " or "    "
    if #text > cw - #prefix then text = text:sub(1, cw - #prefix) end
    draw_text_line(win, 0, dest_row + i, prefix .. text)
  end
end

--- Short path for display (basename or / for root).
function widgets.path_display(path, max_len)
  path = tostring(path or "")
  max_len = math.max(5, max_len or 40)
  if #path <= max_len then return path end
  if path:match("^/") then return ".." .. path:sub(-(max_len - 2)) end
  return ".." .. path:sub(-(max_len - 2))
end

return widgets
