--[[
  window.lua — window chrome + desktop (LuaMade gfx via atlas_draw).

  Desktop: add / remove / bring_to_front / set_focus / focus_next / focus_prev
  Title bar: minimize (_), maximize (^/v), close (x). hit_chrome(win, cx, cy).
  Text: draw_text_line, draw_text_lines (clipped to client area)
]]

local draw = dofile("/home/lib/atlas_draw.lua")
local atlas_color = dofile("/home/lib/atlas_color.lua")
local window = {}

-- Pixel conversion helpers (cell coords are 1-based, pixel coords are 0-based)
local CW = draw.cell_w
local CH = draw.cell_h
local function C(token) return atlas_color.resolve(token) end

local function clamp_title(s, maxLen)
  s = tostring(s or "")
  if #s <= maxLen then return s end
  if maxLen < 3 then return s:sub(1, maxLen) end
  return s:sub(1, maxLen - 2) .. ".."
end

local function index_of(t, win)
  for i = 1, #t do
    if t[i] == win then return i end
  end
  return nil
end

local Win = {}

function Win:client_x()
  return self.x + 1
end

function Win:client_y()
  return self.y + 2
end

function Win:client_w()
  return self.w - 2
end

function Win:client_h()
  return self.h - 3
end

function Win:set_focused(v)
  self.focused = not not v
end

--- How many title-bar control columns (1=close only, 2=+max, 3=+min).
local function title_btn_count(w)
  w = math.floor(w or 0)
  if w >= 10 then return 3 end
  if w >= 7 then return 2 end
  return 1
end

-- ── Window Chrome GUI (Phase 2.4) ───────────────────────────────────────────
--- Build gui components for a window's chrome (bg, border, title, buttons, client area).
local function build_win_gui(win)
  local P = gui.Panel
  local T = gui.Text
  local B = gui.Button
  local mgr = gui.GUIManager.new()
  mgr:setBackgroundColor(0, 0, 0, 0)

  local chrome = P.new(0, 0, 0, 0)
  local titlebar = P.new(0, 0, 0, 0)
  titlebar:setBorderColor(0, 0, 0, 0)
  local title_txt = T.new(0, 0, "")
  title_txt:setScale(1)
  local btn_close = B.new(0, 0, 0, 0, "x", function() end)
  local btn_max = B.new(0, 0, 0, 0, "v", function() end)
  local btn_min = B.new(0, 0, 0, 0, "_", function() end)
  local client = P.new(0, 0, 0, 0)
  client:setBorderColor(0, 0, 0, 0)

  mgr:addComponent(chrome)
  mgr:addComponent(titlebar)
  mgr:addComponent(title_txt)
  mgr:addComponent(btn_close)
  mgr:addComponent(btn_max)
  mgr:addComponent(btn_min)
  mgr:addComponent(client)

  mgr:setLayoutCallback(function(m, _pw, _ph)
    local x, y, w, h = win.x, win.y, win.w, win.h
    local btn = title_btn_count(w)
    local tmax = math.max(1, w - 4 - btn)
    local prefix = win.focused and "*" or " "

    chrome:setPosition((x-1)*CW, (y-1)*CH)
    chrome:setSize(w*CW, h*CH)
    chrome:setBackgroundColor(C(win.body_bg))
    chrome:setBorderColor(C(win.body_fg))

    titlebar:setPosition(x*CW, y*CH)
    titlebar:setSize((w-2)*CW, CH)
    titlebar:setBackgroundColor(C(win.title_bg))

    title_txt:setText(prefix .. clamp_title(win.title, tmax))
    title_txt:setColor(C(win.title_fg))
    title_txt:setPosition((x+1)*CW, y*CH)

    btn_close:setPosition((x+w-3)*CW, y*CH)
    btn_close:setSize(CW, CH)
    btn_close:setLabel("x")
    btn_close:setNormalColor(C(win.title_bg))

    if btn >= 2 then
      btn_max:setVisible(true)
      btn_max:setPosition((x+w-4)*CW, y*CH)
      btn_max:setSize(CW, CH)
      btn_max:setLabel(win.maximized and "v" or "^")
      btn_max:setNormalColor(C(win.title_bg))
    else
      btn_max:setVisible(false)
    end

    if btn >= 3 then
      btn_min:setVisible(true)
      btn_min:setPosition((x+w-5)*CW, y*CH)
      btn_min:setSize(CW, CH)
      btn_min:setLabel("_")
      btn_min:setNormalColor(C(win.title_bg))
    else
      btn_min:setVisible(false)
    end

    local cw, ch = win:client_w(), win:client_h()
    if cw >= 1 and ch >= 1 then
      client:setVisible(true)
      client:setPosition(x*CW, (y+1)*CH)
      client:setSize(cw*CW, ch*CH)
      client:setBackgroundColor(C(win.client_bg))
    else
      client:setVisible(false)
    end
  end)

  win._win_mgr = mgr
end

function Win:paint()
  if self.minimized then return end
  if not self._win_mgr then
    build_win_gui(self)
  end
  self._win_mgr:update(0)
  self._win_mgr:draw()
end

--- Hit on title bar / frame. Returns "close"|"max"|"min"|"drag"|"client"|nil (nil = outside).
function window.hit_chrome(win, cx, cy)
  if win.minimized then return nil end
  cx, cy = math.floor(cx or 0), math.floor(cy or 0)
  if cx < win.x or cy < win.y or cx > win.x + win.w - 1 or cy > win.y + win.h - 1 then
    return nil
  end
  if cy == win.y + 1 and cx >= win.x + 1 and cx <= win.x + win.w - 2 then
    local btn = title_btn_count(win.w)
    local xr = win.x + win.w - 2
    if cx == xr then return "close" end
    if btn >= 2 and cx == xr - 1 then return "max" end
    if btn >= 3 and cx == xr - 2 then return "min" end
    local drag_end = xr - btn
    if cx >= win.x + 2 and cx <= drag_end and drag_end >= win.x + 2 then return "drag" end
    return nil
  end
  if cy >= win.y + 2 then return "client" end
  return nil
end

function window.new(o)
  o = o or {}
  local w = math.max(4, math.floor(o.w or 20))
  local h = math.max(3, math.floor(o.h or 8))
  local t = {
    x = math.max(1, math.floor(o.x or 1)),
    y = math.max(1, math.floor(o.y or 1)),
    w = w,
    h = h,
    title = o.title or "Window",
    border = o.border or "#",
    title_fg = o.title_fg or "bright_white",
    title_bg = o.title_bg or "blue",
    body_fg = o.body_fg or "white",
    body_bg = o.body_bg or "black",
    client_fg = o.client_fg or "white",
    client_bg = o.client_bg or "black",
    focused = o.focused == true,
    minimized = o.minimized == true,
    maximized = o.maximized == true,
    _restore = nil,
  }
  return setmetatable(t, { __index = Win })
end

--- Single line at (rel_col, rel_row) inside client; truncated to fit.
function window.draw_text_line(win, rel_col, rel_row, text, fg, bg)
  if win.minimized then return end
  local cw, ch = win:client_w(), win:client_h()
  rel_col, rel_row = math.floor(rel_col or 0), math.floor(rel_row or 0)
  if rel_row < 0 or rel_row >= ch or rel_col < 0 or rel_col >= cw then return end
  local maxc = cw - rel_col
  text = tostring(text)
  if #text > maxc then text = text:sub(1, maxc) end
  draw.text(win:client_x() + rel_col, win:client_y() + rel_row, text, fg or win.client_fg, bg or win.client_bg)
end

--- Fill client with lines[start_line], lines[start_line+1], … (1-based index).
function window.draw_text_lines(win, lines, start_line)
  if win.minimized then return end
  lines = lines or {}
  start_line = math.max(1, math.floor(start_line or 1))
  local ch, cw = win:client_h(), win:client_w()
  if ch < 1 or cw < 1 then return end
  for row = 0, ch - 1 do
    local line = lines[start_line + row]
    if line then
      line = tostring(line)
      if #line > cw then line = line:sub(1, cw) end
      draw.text(win:client_x(), win:client_y() + row, line, win.client_fg, win.client_bg)
    end
  end
end

-- ——— Desktop ———

function window.Desktop.new(bg_fg, bg_bg, fill)
  return {
    _windows = {},
    _focus = nil,
    bg_fg = bg_fg or "white",
    bg_bg = bg_bg or "blue",
    fill = fill or " ",
  }
end

function window.Desktop.add(d, win)
  d._windows[#d._windows + 1] = win
  if #d._windows == 1 then
    window.Desktop.set_focus(d, win)
  end
end

--- Clean up gui components for a window (called on window removal).
function window.win_gui_cleanup(win)
  win._win_mgr = nil
end

function window.Desktop.remove(d, win)
  local i = index_of(d._windows, win)
  if not i then return false end
  window.win_gui_cleanup(win)  -- Clean up gui components before removal
  table.remove(d._windows, i)
  if d._focus == win then
    d._focus = d._windows[math.min(i, #d._windows)] or d._windows[#d._windows]
    for j = 1, #d._windows do
      d._windows[j]:set_focused(d._windows[j] == d._focus)
    end
  end
  return true
end

function window.Desktop.remove_at(d, index)
  local win = d._windows[index]
  if win then return window.Desktop.remove(d, win) end
  return false
end

function window.Desktop.bring_to_front(d, win)
  local i = index_of(d._windows, win)
  if not i or i == #d._windows then return end
  table.remove(d._windows, i)
  d._windows[#d._windows + 1] = win
  window.Desktop.set_focus(d, win)
end

function window.Desktop.set_focus(d, win)
  if not win then
    d._focus = nil
    for j = 1, #d._windows do
      d._windows[j]:set_focused(false)
    end
    return
  end
  if not index_of(d._windows, win) then return end
  d._focus = win
  for j = 1, #d._windows do
    d._windows[j]:set_focused(d._windows[j] == win)
  end
end

function window.Desktop.focused(d)
  return d._focus
end

function window.Desktop.focus_next(d)
  local n = #d._windows
  if n == 0 then return end
  local vis = {}
  for j = 1, n do
    if not d._windows[j].minimized then vis[#vis + 1] = d._windows[j] end
  end
  if #vis == 0 then
    d._focus = nil
    for j = 1, n do
      d._windows[j]:set_focused(false)
    end
    return
  end
  local fi = 1
  for j = 1, #vis do
    if vis[j] == d._focus then fi = j break end
  end
  local next_w = vis[(fi % #vis) + 1]
  window.Desktop.set_focus(d, next_w)
  window.Desktop.bring_to_front(d, next_w)
end

function window.Desktop.focus_prev(d)
  local n = #d._windows
  if n == 0 then return end
  local vis = {}
  for j = 1, n do
    if not d._windows[j].minimized then vis[#vis + 1] = d._windows[j] end
  end
  if #vis == 0 then
    d._focus = nil
    for j = 1, n do
      d._windows[j]:set_focused(false)
    end
    return
  end
  local fi = 1
  for j = 1, #vis do
    if vis[j] == d._focus then fi = j break end
  end
  local prev_w = vis[fi - 1]
  if not prev_w then prev_w = vis[#vis] end
  window.Desktop.set_focus(d, prev_w)
  window.Desktop.bring_to_front(d, prev_w)
end

--- Paint only a region (wallpaper + windows). Skips minimized windows.
function window.Desktop.paint_region(d, gx, gy, gw, gh)
  gx, gy = math.max(1, math.floor(gx)), math.max(1, math.floor(gy))
  gw, gh = math.max(1, math.floor(gw)), math.max(1, math.floor(gh))
  draw.fillRect(gx, gy, gw, gh, d.bg_bg)
  for i = 1, #d._windows do
    if not d._windows[i].minimized then
      d._windows[i]:paint()
    end
  end
end

function window.Desktop.paint(d, gw, gh)
  if not gw or not gh then
    local cw, ch = draw.canvas_cells()
    if cw and ch then
      gw, gh = cw, ch
    end
  end
  gw = gw or 80
  gh = gh or 24
  window.Desktop.paint_region(d, 1, 1, gw, gh)
end

return window
