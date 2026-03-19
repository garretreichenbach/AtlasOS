--[[
  DovOS desktop: bottom taskbar + Start menu (pinned / grouped apps).
]]

local dovtheme = dofile("/home/lib/dovtheme.lua")
local dovsettings = nil
do
  local ok, m = pcall(dofile, "/home/lib/dovsettings.lua")
  dovsettings = ok and m or {
    developer_mode = function() return false end,
    toggle_developer_mode = function() return false end,
    set_developer_mode = function() end,
  }
end
local window = dofile("/home/lib/window.lua")
local widgets = dofile("/home/lib/widgets.lua")
local input = dofile("/home/lib/input.lua")
local startmenu = _G.startmenu or dofile("/home/lib/startmenu.lua")
_G.startmenu = startmenu

local LAYOUT_PATH = "/etc/dovos/layout.txt"
local GFX_CONF_PATH = "/etc/dovos/gfx.conf"
local VERSION = "0.3.2"

-- Default canvas (cells) before first gfx.setSize; avoid trusting 64x24 default from mod.
local CANVAS_DEFAULT_W, CANVAS_DEFAULT_H = 150, 100

--- gfx.conf: cell_scale, per-region icon pixel scale (LuaMade setPixelScale). See gfx.conf.example.
local function read_gfx_conf()
  local conf = {
    cell_scale = 1.5,
    icon_pixel_scale = 2.0,
    taskbar_icon_pixel_scale = 1.75,
    search_pixel_scale = 1.25,
  }
  if not fs or not fs.read then return conf end
  local ok, raw = pcall(fs.read, GFX_CONF_PATH)
  if not ok or not raw or tostring(raw):gsub("%s", "") == "" then return conf end
  for line in tostring(raw):gmatch("[^\r\n]+") do
    local function num(pat)
      local v = line:match(pat)
      if v then
        local n = tonumber(v)
        if n then return math.max(0.5, math.min(4.0, n)) end
      end
      return nil
    end
    local n = num("^%s*cell_scale%s*=%s*([0-9.]+)%s*$") or num("^%s*scale%s*=%s*([0-9.]+)%s*$")
    if n then conf.cell_scale = n end
    n = num("^%s*icon_pixel_scale%s*=%s*([0-9.]+)%s*$")
    if n then conf.icon_pixel_scale = n end
    n = num("^%s*taskbar_icon_pixel_scale%s*=%s*([0-9.]+)%s*$")
    if n then conf.taskbar_icon_pixel_scale = n end
    n = num("^%s*search_pixel_scale%s*=%s*([0-9.]+)%s*$")
    if n then conf.search_pixel_scale = n end
  end
  return conf
end

--- Apply setPixelScale to a cell rectangle (higher = sharper glyphs in same grid).
local function gfx_rect_pixel_scale(x0, y0, w, h, sx, sy)
  if not gfx or type(gfx.setPixelScale) ~= "function" or w < 1 or h < 1 then return end
  sx = math.max(0.5, math.min(4.0, sx or 1))
  sy = math.max(0.5, math.min(4.0, sy or sx))
  if sx <= 1.001 and sy <= 1.001 then return end
  local x1, y1 = x0 + w - 1, y0 + h - 1
  for y = y0, y1 do
    for x = x0, x1 do
      pcall(gfx.setPixelScale, x, y, sx, sy)
    end
  end
end

local function gfx_rect_pixel_scale_reset(x0, y0, w, h)
  if not gfx or type(gfx.setPixelScale) ~= "function" or w < 1 or h < 1 then return end
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      pcall(gfx.setPixelScale, x, y, 1, 1)
    end
  end
end

--- Per-row / per-app icon colors (appinfo icon_fg, icon_bg, icon_row_fg, icon_taskbar_sel_fg).
local function gfx_icon_row_style(meta, row_idx, default_fg, default_bg, taskbar_selected)
  local fg, bg = default_fg, default_bg
  if meta then
    local rr = meta.icon_row_fg
    if type(rr) == "table" and rr[row_idx] and tostring(rr[row_idx]) ~= "" then
      fg = tostring(rr[row_idx])
    elseif type(meta.icon_fg) == "string" and meta.icon_fg ~= "" then
      fg = meta.icon_fg
    end
  end
  if taskbar_selected then
    local sfg = meta and meta.icon_taskbar_sel_fg
    if type(sfg) == "string" and sfg ~= "" then
      fg = sfg
    else
      fg = "black"
    end
    return fg, 28
  end
  if meta and type(meta.icon_bg) == "string" and meta.icon_bg ~= "" then
    bg = meta.icon_bg
  end
  return fg, bg
end

-- get: canvas width/height in character cells.
-- set: gfx.setSize (LuaMade Text Graphics / canvas overlays).
local function size_get()
  if UI._gfx_sized and gfx and type(gfx.getWidth) == "function" and type(gfx.getHeight) == "function" then
    local ok, gw, gh = pcall(function()
      return gfx.getWidth(), gfx.getHeight()
    end)
    if ok and type(gw) == "number" and type(gh) == "number" and gw >= 8 and gh >= 8 then
      return math.floor(gw), math.floor(gh)
    end
  end
  return CANVAS_DEFAULT_W, CANVAS_DEFAULT_H
end

local function size_set(w, h)
  w = math.max(1, math.min(240, math.floor(w or CANVAS_DEFAULT_W)))
  h = math.max(1, math.min(120, math.floor(h or CANVAS_DEFAULT_H)))
  if gfx and type(gfx.setSize) == "function" then
    local ok = pcall(gfx.setSize, w, h)
    if ok then UI._gfx_sized = true end
  else
    UI._gfx_sized = true
  end
end

local UI = {
  _size_get = size_get,
  _size_set = size_set,
  _gfx_sized = false,
  _gfx_backend_canvas = false,
  W = CANVAS_DEFAULT_W,
  H = CANVAS_DEFAULT_H,
  TASKBAR_H = math.max(1, math.min(10, math.floor(CANVAS_DEFAULT_H * 0.15 + 0.5))),
  desk = nil,
  start_open = false,
  activities_open = false,
  taskbar_sel = 1,
  files_dir = "/home",
  _drag = nil,
  _min_strip = {},
}

local function path_join(dir, name)
  return dir:match("/$") and (dir .. name) or (dir .. "/" .. name)
end

local DOVOS_HOME = "/home/dovos"

local function path_normalize(p)
  p = tostring(p or "/home"):gsub("\\", "/"):gsub("/+", "/")
  if p ~= "/" then p = p:gsub("/$", "") end
  if p == "" then p = "/" end
  if p:sub(1, 1) ~= "/" then p = "/" .. p end
  return p
end

--- True if path is /home/dovos or inside it (system DovOS tree).
local function path_is_dovos_tree(p)
  p = path_normalize(p)
  return p == DOVOS_HOME or p:sub(1, #DOVOS_HOME + 1) == DOVOS_HOME .. "/"
end

function UI.developer_mode_enabled()
  return dovsettings.developer_mode and dovsettings.developer_mode() or false
end

function UI.toggle_developer_mode()
  if dovsettings.toggle_developer_mode then
    return dovsettings.toggle_developer_mode()
  end
  return false
end

--- Hide system DovOS tree from Files when not developer: no `dovos` under /home.
function UI.files_show_list_entry(parent_dir, entry_name, is_dir)
  if UI.developer_mode_enabled() then return true end
  if not is_dir then return true end
  if path_normalize(parent_dir) == "/home" and entry_name == "dovos" then
    return false
  end
  return true
end

function UI.files_effective_dir()
  local d = path_normalize(UI.files_dir or "/home")
  if path_is_dovos_tree(d) and not UI.developer_mode_enabled() then
    return "/home"
  end
  return d
end

UI._search_api_cached = nil
UI._files_painter = nil

local function search_offline_api()
  return {
    clear = function() end,
    begin = function() end,
    step = function() end,
    get_state = function()
      return { needle = "", needle_display = "", name_hits = {}, content_hits = {}, busy = false }
    end,
    draw_taskbar = function(gfx, opt)
      gfx.setColor("black", "white")
      gfx.fillRect(opt.x, opt.y0, opt.sw, math.max(1, opt.th >= 3 and 2 or 1), " ")
      gfx.text(opt.x, opt.y0, "[search missing]")
    end,
  }
end

function UI.search_api()
  if UI._search_api_cached then return UI._search_api_cached end
  local candidates = {}
  if startmenu._dovos_search and startmenu._dovos_search.package_dir and startmenu._dovos_search.module then
    candidates[#candidates + 1] = startmenu._dovos_search.package_dir .. "/" .. startmenu._dovos_search.module
  end
  candidates[#candidates + 1] = "/home/dovos/apps/search/search_engine.lua"
  for _, p in ipairs(candidates) do
    local ok, m = pcall(function()
      if not fs.read(p) then return nil end
      return dofile(p)
    end)
    if ok and type(m) == "table" and m.begin and m.step and m.draw_taskbar then
      UI._search_api_cached = m
      return m
    end
  end
  UI._search_api_cached = search_offline_api()
  return UI._search_api_cached
end

function UI.invalidate_packages()
  UI._search_api_cached = nil
  UI._files_painter = nil
  UI._editor_painter = nil
  UI._settings_painter = nil
end

function UI.search_clear()
  UI.search_api().clear()
end

function UI.search_begin(needle)
  UI.search_api().begin(needle)
end

function UI.search_step(budget)
  UI.search_api().step(budget)
end

--- Slots actually drawn (user pins may be truncated if taskbar is narrow).
function UI.taskbar_slots_visible()
  UI.update_size()
  local W = UI.W
  local settings_x = math.max(22, W - 24)
  local lc = #startmenu.TASKBAR_LEFT
  local step = startmenu.taskbar_icon_step()
  -- Room: Start+gap + search + gap + icons (step cols each) + ≥1 user pin
  local max_sw = settings_x - 7 - 1 - step * lc - step
  local search_w = math.min(28, math.max(4, math.floor(W * 0.20), max_sw))
  if search_w < 4 then search_w = 4 end
  if 7 + search_w + 1 + step * lc > settings_x - 2 then
    search_w = math.max(4, settings_x - 7 - 1 - step * lc - 1)
  end
  local x = 7 + search_w + 1
  local slots = {}
  for _, id in ipairs(startmenu.TASKBAR_LEFT) do
    slots[#slots + 1] = id
    x = x + step
  end
  for _, id in ipairs(startmenu.flatten_user_pins(14)) do
    if x + step > settings_x - 2 then break end
    slots[#slots + 1] = id
    x = x + step
  end
  for _, id in ipairs(startmenu.TASKBAR_RIGHT) do
    slots[#slots + 1] = id
  end
  return slots, search_w, settings_x
end

function UI.workspace_rect()
  local th = math.max(1, UI.TASKBAR_H)
  return 1, 1, UI.W, UI.H - th
end

function UI.update_size()
  local w, h = UI._size_get()
  -- Taskbar needs ~54 cols for Start + search + 3 left icons + Settings + Trash + clock
  UI.W = math.max(54, math.floor(w or 80))
  UI.H = math.max(12, math.floor(h or 24))
  -- 3 rows: icons+search, search stats / filler, entity+date (QoL dock strip)
  UI.TASKBAR_H = (UI.H >= 22) and 3 or math.max(2, math.min(3, math.floor(UI.H * 0.10 + 0.5)))
end

local REF_W, REF_H = 80, 24
local REF_TASKBAR = 2
local function ref_workspace()
  return 1, 1, REF_W, REF_H - REF_TASKBAR
end

--- Fractional def: xf,yf,wf,hf in 0..1 of workspace. Legacy: absolute x,y,w,h scaled from REF canvas.
local function resolve_window_rect(def, wx, wy, ww, wh)
  local minw, minh = math.max(6, math.floor(ww * 0.12)), math.max(3, math.floor(wh * 0.12))
  if def.xf then
    local x = wx + math.floor((def.xf or 0) * ww)
    local y = wy + math.floor((def.yf or 0) * wh)
    local rw = math.max(minw, math.floor((def.wf or 0.25) * ww))
    local rh = math.max(minh, math.floor((def.hf or 0.25) * wh))
    x = math.max(wx, math.min(x, wx + ww - rw))
    y = math.max(wy, math.min(y, wy + wh - rh))
    return x, y, rw, rh
  end
  local rwx, rwy, rww, rwh = ref_workspace()
  local x = wx + math.floor(((def.x - rwx) / rww) * ww)
  local y = wy + math.floor(((def.y - rwy) / rwh) * wh)
  local rw = math.max(minw, math.floor((def.w / rww) * ww))
  local rh = math.max(minh, math.floor((def.h / rwh) * wh))
  x = math.max(wx, math.min(x, wx + ww - rw))
  y = math.max(wy, math.min(y, wy + wh - rh))
  return x, y, rw, rh
end

local function clock_str()
  if console and console.getTime then
    local ms = console.getTime()
    local s = math.floor(ms / 1000) % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
  end
  return "--:--"
end

--- Format Sector / System / vectors from LuaMade Entity API.
local function fmt_world_obj(o)
  if o == nil then return "—" end
  local ty = type(o)
  if ty == "string" or ty == "number" then return tostring(o) end
  if ty == "table" then
    local x, y, z = o.x, o.y, o.z
    if type(x) == "number" and type(y) == "number" and type(z) == "number" then
      return string.format("%d,%d,%d", math.floor(x), math.floor(y), math.floor(z))
    end
    if o.getName then
      local ok, n = pcall(o.getName, o)
      if ok and n and tostring(n) ~= "" then return tostring(n) end
    end
  end
  local ok, s = pcall(tostring, o)
  if ok and s and not s:match("^table: 0x") then return s end
  return "—"
end

--- Block/computer name, sector coords/name, system (LuaMade: entity.getSector / getSystem).
local function dock_world_line()
  local comp = "computer"
  local sector, sys = "—", "—"
  if console and console.getBlock then
    local ok, block = pcall(function() return console.getBlock() end)
    if ok and block then
      if block.getInfo then
        local ok2, info = pcall(block.getInfo, block)
        if ok2 and info and info.getName then
          comp = tostring(info.getName() or comp)
        end
      end
      if block.getEntity then
        local ok2, ent = pcall(block.getEntity, block)
        if ok2 and ent then
          if ent.getSector then
            local ok3, v = pcall(ent.getSector, ent)
            if ok3 and v ~= nil then sector = fmt_world_obj(v) end
          end
          if ent.getSystem then
            local ok3, v = pcall(ent.getSystem, ent)
            if ok3 and v ~= nil then sys = fmt_world_obj(v) end
          end
        end
      end
    end
  end
  return comp .. "  ·  " .. sector .. "  ·  " .. sys
end

--- Wall clock via util.now(); fallback console.getTime (session) if os.date missing.
local function dock_datetime_str()
  local ms
  if util and util.now then
    local ok, v = pcall(util.now)
    if ok and type(v) == "number" then ms = v end
  end
  if not ms and console and console.getTime then
    ms = console.getTime()
  end
  if not ms then return "--:--   —" end
  local sec = math.floor(ms / 1000)
  if os and os.date then
    return os.date("%H:%M", sec) .. "  " .. os.date("%Y-%m-%d", sec)
  end
  local s = sec % 86400
  return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60)) .. "  (no os.date)"
end

local function hostname()
  if console and console.getBlock then
    local ok, block = pcall(function() return console.getBlock() end)
    if ok and block and block.getInfo then
      local ok2, info = pcall(block.getInfo, block)
      if ok2 and info and info.getName then
        return info.getName() or "computer"
      end
    end
  end
  return "computer"
end

function UI.device_name()
  return hostname()
end

function UI.settings_dispatch(tag)
  if not tag then return end
  if tag:sub(1, 4) == "cat:" then
    UI._settings_cat = tag:sub(5)
    return
  end
  if tag == "theme:light" then
    pcall(dovtheme.save, "light")
    UI._theme_reload_desktop()
  elseif tag == "theme:dark" then
    pcall(dovtheme.save, "dark")
    UI._theme_reload_desktop()
  elseif tag == "dev:toggle" then
    UI.toggle_developer_mode()
    if path_is_dovos_tree(path_normalize(UI.files_dir or "")) then
      UI.files_dir = "/home"
    end
  elseif tag == "nav:apps" then
    UI.files_set_dir("/home/apps")
    UI.focus_window_by_title("Files")
  elseif tag == "cmd:reload_apps" then
    startmenu.refresh_packages()
    UI.invalidate_packages()
  elseif tag == "cmd:save_layout" then
    UI.layout_save()
    _G.DovOS_log = _G.DovOS_log or {}
    _G.DovOS_log[#_G.DovOS_log + 1] = "[Settings] Layout saved."
  end
end

function UI._theme_reload_desktop()
  UI.desk = nil
  UI._canvas_key = nil
  UI.build_desktop()
  if UI.desk and UI.desk._windows then
    for _, w in ipairs(UI.desk._windows) do
      if w.title == "Settings" then
        window.Desktop.bring_to_front(UI.desk, w)
        window.Desktop.set_focus(UI.desk, w)
        break
      end
    end
  end
end

function UI.layout_load()
  local raw = fs.read(LAYOUT_PATH)
  if not raw then return nil end
  local out = { theme = nil, taskbar_sel = 1, windows = {} }
  for line in raw:gmatch("[^\r\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "theme" and (v == "light" or v == "dark") then out.theme = v end
    if k == "dock_sel" or k == "taskbar_sel" then out.taskbar_sel = math.floor(tonumber(v) or 1) end
    local title, xf, yf, wf, hf = line:match("^([%w]+)%s+f%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)$")
    if title and xf then
      out.windows[#out.windows + 1] = {
        title = title,
        xf = tonumber(xf), yf = tonumber(yf), wf = tonumber(wf), hf = tonumber(hf),
      }
    else
      local t2, x, y, w, h = line:match("^([%w]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      if t2 and x then
        out.windows[#out.windows + 1] = {
          title = t2,
          x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h),
        }
      end
    end
  end
  return out
end

function UI.layout_save()
  fs.makeDir("/etc/dovos")
  local t = dovtheme.load()
  UI.update_size()
  local wx, wy, ww, wh = UI.workspace_rect()
  local lines = {
    "layout_version=2",
    "theme=" .. t.mode,
    "taskbar_sel=" .. tostring(UI.taskbar_sel),
  }
  if UI.desk and UI.desk._windows then
    for _, win in ipairs(UI.desk._windows) do
      if ww > 0 and wh > 0 then
        local xf = (win.x - wx) / ww
        local yf = (win.y - wy) / wh
        local wf = win.w / ww
        local hf = win.h / wh
        lines[#lines + 1] = string.format(
          "%s f %.4f %.4f %.4f %.4f",
          win.title or "Window", xf, yf, wf, hf
        )
      end
    end
  end
  fs.write(LAYOUT_PATH, table.concat(lines, "\n"))
end

-- Default layout: fractions of workspace (wx..wx+ww, wy..wy+wh)
local default_layout = {
  { title = "Guide", xf = 0.03, yf = 0.06, wf = 0.52, hf = 0.62 },
  { title = "Status", xf = 0.50, yf = 0.08, wf = 0.46, hf = 0.38 },
  { title = "Files", xf = 0.03, yf = 0.10, wf = 0.34, hf = 0.52 },
  { title = "Settings", xf = 0.40, yf = 0.32, wf = 0.56, hf = 0.40 },
  { title = "Console", xf = 0.06, yf = 0.58, wf = 0.86, hf = 0.36 },
  { title = "Trash", xf = 0.62, yf = 0.52, wf = 0.34, hf = 0.28 },
}

function UI.build_desktop()
  UI.update_size()
  local layout = UI.layout_load()
  if layout and layout.theme then
    dovtheme.save(layout.theme)
  end
  if layout and layout.taskbar_sel then
    local slots = UI.taskbar_slots_visible()
    UI.taskbar_sel = math.max(1, math.min(layout.taskbar_sel, math.max(1, #slots)))
  end

  UI.desk = window.Desktop.new()
  dovtheme.apply_desktop(UI.desk)

  local wx, wy, ww, wh = UI.workspace_rect()
  local wins = (layout and layout.windows and #layout.windows > 0) and layout.windows or default_layout

  for i, def in ipairs(wins) do
    local x, y, rw, rh = resolve_window_rect(def, wx, wy, ww, wh)
    local w = window.new({
      x = x, y = y, w = rw, h = rh, title = def.title,
      minimized = def.minimized == true,
    })
    dovtheme.style_window(w, def.title)
    window.Desktop.add(UI.desk, w)
    if i == 1 then window.Desktop.set_focus(UI.desk, w) end
  end
  local foc = window.Desktop.focused(UI.desk)
  if foc and foc.minimized then
    for _, w in ipairs(UI.desk._windows) do
      if not w.minimized then
        window.Desktop.set_focus(UI.desk, w)
        break
      end
    end
  end

  local has_editor = false
  for _, w in ipairs(UI.desk._windows) do
    if w.title == "Editor" then
      has_editor = true
      break
    end
  end
  if not has_editor then
    local x, y, rw, rh = resolve_window_rect({
      title = "Editor",
      xf = 0.50,
      yf = 0.08,
      wf = 0.46,
      hf = 0.52,
    }, wx, wy, ww, wh)
    local ed = window.new({
      x = x, y = y, w = rw, h = rh, title = "Editor",
      minimized = true,
    })
    dovtheme.style_window(ed, "Editor")
    window.Desktop.add(UI.desk, ed)
  end
end

--- System overview + README user guide (replaces separate Welcome / Help windows).
local function paint_guide(win)
  local t = dovtheme.load()
  local scale_line = "Canvas: " .. tostring(UI.W) .. "x" .. tostring(UI.H)
  if gfx and type(gfx.getCellScale) == "function" then
    local ok, sc = pcall(gfx.getCellScale)
    if ok and type(sc) == "table" and sc[1] and sc[2] then
      scale_line = scale_line .. string.format("  cell scale %.2fx%.2f", sc[1], sc[2])
    end
  end
  local lines = {
    "--- System ---",
    "DovOS " .. VERSION .. " (Custom OS for LuaMade Computers)",
    scale_line,
    "Theme: " .. t.mode,
    "Host: " .. hostname(),
    "",
    "--- Quick tips ---",
    "start  — Start menu",
    "tasknext / go — taskbar pins",
    "Title: _ min  ^ max  x close  drag title",
    "Tab — next window  |  minimized row above taskbar",
    "pin / unpin  ·  save_layout",
    "",
  }
  local raw = fs.read("/home/dovos/README.txt")
  if not raw or raw == "" then
    raw = "No README at /home/dovos/README.txt — run `help` in console for commands."
  end
  lines[#lines + 1] = "--- User guide (README) ---"
  for line in (raw .. ""):gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  widgets.log_paint(win, lines, 1)
end

local function paint_status(win)
  window.draw_text_lines(win, {
    clock_str(),
    "Host: " .. hostname(),
    "",
    "Cwd: " .. (fs.getCurrentDir and fs.getCurrentDir() or "/home"),
    "",
    "Network: —",
    "Ship: —",
    "",
    "Input API: pending",
  }, 1)
end

local function paint_files_fallback(win)
  local dir = UI.files_effective_dir()
  if path_normalize(UI.files_dir or "") ~= dir then
    UI.files_dir = dir
  end
  local list = {}
  if dir ~= "/" and dir ~= "" then
    list[#list + 1] = { text = "..", dir = true }
  end
  local ok, names = pcall(fs.list, dir)
  if ok and names then
    for _, name in ipairs(names) do
      local full = path_join(dir, name)
      local isDir = false
      if fs.isDir then pcall(function() isDir = fs.isDir(full) end) end
      if UI.files_show_list_entry(dir, name, isDir) then
        list[#list + 1] = { text = name, dir = isDir }
      end
    end
  else
    list[#list + 1] = "(cannot list)"
  end
  window.draw_text_line(win, 0, 0, widgets.path_display(dir, win:client_w() - 2))
  widgets.hrule(win, 1, "-")
  widgets.list_box(win, list, 1, win:client_h() - 2, 2)
end

local function get_files_painter()
  if UI._files_painter then return UI._files_painter end
  local m = startmenu.registry.files
  if m and m.package_dir and m.paint_module then
    local path = m.package_dir .. "/" .. m.paint_module
    local ok, factory = pcall(dofile, path)
    if ok and type(factory) == "function" then
      local paint = factory({ UI = UI, widgets = widgets, window = window })
      if type(paint) == "function" then
        UI._files_painter = paint
        return paint
      end
    end
  end
  UI._files_painter = paint_files_fallback
  return UI._files_painter
end

local function paint_files(win)
  get_files_painter()(win)
end

local function paint_settings_fallback(win)
  window.draw_text_lines(win, {
    "Settings",
    "Install: /home/dovos/apps/settings/settings_ui.lua",
    "theme  devmode  save_layout",
  }, 1)
end

local function get_settings_painter()
  if UI._settings_painter then return UI._settings_painter end
  local m = startmenu.registry.settings
  if m and m.package_dir and m.paint_module then
    local path = m.package_dir .. "/" .. m.paint_module
    local ok, factory = pcall(dofile, path)
    if ok and type(factory) == "function" then
      local paint = factory({
        UI = UI,
        widgets = widgets,
        window = window,
        dovtheme = dovtheme,
        VERSION = VERSION,
      })
      if type(paint) == "function" then
        UI._settings_painter = paint
        return paint
      end
    end
  end
  UI._settings_painter = paint_settings_fallback
  return UI._settings_painter
end

local function paint_settings(win)
  get_settings_painter()(win)
end

local function paint_console(win)
  local log = _G.DovOS_log or {}
  local start = widgets.log_tail_index(log, win:client_h())
  widgets.log_paint(win, log, start)
end

local function editor_split_lines(raw)
  if raw == nil or raw == "" then return { "" } end
  local t = {}
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    t[#t + 1] = line
  end
  return t
end

function UI.editor_ensure()
  if UI._editor then return end
  UI._editor = {
    path = "/home/notes.txt",
    lines = { "" },
    cur_line = 1,
    cur_col = 0,
    scroll = 1,
    dirty = false,
  }
  UI.editor_load(UI._editor.path)
end

function UI.editor_load(path)
  if not path or path == "" then path = "/home/notes.txt" end
  UI.editor_ensure()
  local raw = fs.read(path)
  UI._editor.lines = editor_split_lines(raw)
  if #UI._editor.lines == 0 then UI._editor.lines = { "" } end
  UI._editor.path = path
  UI._editor.cur_line = 1
  UI._editor.cur_col = 0
  UI._editor.scroll = 1
  UI._editor.dirty = false
end

function UI.editor_save()
  UI.editor_ensure()
  local st = UI._editor
  local path = st.path or "/home/notes.txt"
  local par = path:match("^(.+)/[^/]+$") or "/"
  pcall(fs.makeDir, par)
  local ok = pcall(fs.write, path, table.concat(st.lines, "\n"))
  if ok then st.dirty = false end
  return ok
end

function UI.editor_open(path)
  UI.editor_ensure()
  if path and tostring(path) ~= "" then
    UI.editor_load(tostring(path))
  end
  UI.focus_window_by_title("Editor")
end

--- Returns true if key was consumed (Editor focused).
function UI.editor_handle_key(e)
  UI.editor_ensure()
  local st = UI._editor
  local key = tonumber(e.key) or 0
  local ctrl = e.ctrl == true
  local ch = e.char

  if ctrl and (key == 83 or (type(ch) == "string" and ch:lower() == "s")) then
    UI.editor_save()
    return true
  end

  if key == 15 then
    local line = st.lines[st.cur_line] or ""
    local c = st.cur_col
    st.lines[st.cur_line] = line:sub(1, c) .. "  " .. line:sub(c + 1)
    st.cur_col = c + 2
    st.dirty = true
    return true
  end

  if key == 28 or key == 257 then
    local line = st.lines[st.cur_line] or ""
    local c = st.cur_col
    local rest = line:sub(c + 1)
    st.lines[st.cur_line] = line:sub(1, c)
    table.insert(st.lines, st.cur_line + 1, rest)
    st.cur_line = st.cur_line + 1
    st.cur_col = 0
    st.dirty = true
    return true
  end

  if key == 259 then
    local line = st.lines[st.cur_line] or ""
    local c = st.cur_col
    if c > 0 then
      st.lines[st.cur_line] = line:sub(1, c - 1) .. line:sub(c + 1)
      st.cur_col = c - 1
      st.dirty = true
    elseif st.cur_line > 1 then
      local prev = st.lines[st.cur_line - 1] or ""
      st.cur_col = #prev
      st.lines[st.cur_line - 1] = prev .. line
      table.remove(st.lines, st.cur_line)
      st.cur_line = st.cur_line - 1
      st.dirty = true
    end
    return true
  end

  if key == 261 then
    local line = st.lines[st.cur_line] or ""
    local c = st.cur_col
    if c < #line then
      st.lines[st.cur_line] = line:sub(1, c) .. line:sub(c + 2)
      st.dirty = true
    elseif st.cur_line < #st.lines then
      st.lines[st.cur_line] = line .. (st.lines[st.cur_line + 1] or "")
      table.remove(st.lines, st.cur_line + 1)
      st.dirty = true
    end
    return true
  end

  local function is_left(k) return k == 263 or k == 203 end
  local function is_right(k) return k == 262 or k == 205 or k == 204 end
  local function is_up(k) return k == 265 or k == 200 end
  local function is_down(k) return k == 264 or k == 208 end

  if is_left(key) then
    if st.cur_col > 0 then
      st.cur_col = st.cur_col - 1
    elseif st.cur_line > 1 then
      st.cur_line = st.cur_line - 1
      st.cur_col = #(st.lines[st.cur_line] or "")
    end
    return true
  end
  if is_right(key) then
    local line = st.lines[st.cur_line] or ""
    if st.cur_col < #line then
      st.cur_col = st.cur_col + 1
    elseif st.cur_line < #st.lines then
      st.cur_line = st.cur_line + 1
      st.cur_col = 0
    end
    return true
  end
  if is_up(key) and st.cur_line > 1 then
    st.cur_line = st.cur_line - 1
    st.cur_col = math.min(st.cur_col, #(st.lines[st.cur_line] or ""))
    return true
  end
  if is_down(key) and st.cur_line < #st.lines then
    st.cur_line = st.cur_line + 1
    st.cur_col = math.min(st.cur_col, #(st.lines[st.cur_line] or ""))
    return true
  end

  if type(ch) == "string" and ch ~= "" and not ctrl then
    local b = string.byte(ch, 1)
    if b and b >= 32 then
      local line = st.lines[st.cur_line] or ""
      local c = st.cur_col
      st.lines[st.cur_line] = line:sub(1, c) .. ch .. line:sub(c + 1)
      st.cur_col = c + #ch
      st.dirty = true
      return true
    end
  end

  return false
end

local function get_editor_painter()
  if UI._editor_painter then return UI._editor_painter end
  local m = startmenu.registry.editor
  if m and m.package_dir and m.paint_module then
    local path = m.package_dir .. "/" .. m.paint_module
    local ok, factory = pcall(dofile, path)
    if ok and type(factory) == "function" then
      local paint = factory({ UI = UI, widgets = widgets, window = window })
      if type(paint) == "function" then
        UI._editor_painter = paint
        return paint
      end
    end
  end
  UI._editor_painter = function(win)
    window.draw_text_lines(win, { "(Editor — install /home/dovos/apps/editor)", "" }, 1)
  end
  return UI._editor_painter
end

local function paint_editor(win)
  get_editor_painter()(win)
end

local function paint_trash(win)
  pcall(fs.makeDir, "/home/.trash")
  local dir = "/home/.trash"
  local list = {}
  if dir ~= "/" and dir ~= "" then
    list[#list + 1] = { text = "..", dir = true }
  end
  local ok, names = pcall(fs.list, dir)
  if ok and names then
    for _, name in ipairs(names) do
      local full = path_join(dir, name)
      local isDir = false
      if fs.isDir then pcall(function() isDir = fs.isDir(full) end) end
      list[#list + 1] = { text = name, dir = isDir }
    end
  else
    list[#list + 1] = "(empty or n/a)"
  end
  window.draw_text_line(win, 0, 0, widgets.path_display("Trash — " .. dir, win:client_w() - 2))
  widgets.hrule(win, 1, "-")
  widgets.list_box(win, list, 1, win:client_h() - 2, 2)
end

UI.paint_window_content = {
  Guide = paint_guide,
  --- Legacy window titles (saved layouts); same content as Guide.
  Welcome = paint_guide,
  Help = paint_guide,
  Status = paint_status,
  Files = paint_files,
  Settings = paint_settings,
  Console = paint_console,
  Trash = paint_trash,
  Editor = paint_editor,
}

function UI.launch_app(id)
  local meta = startmenu.registry[id]
  if not meta then return end
  if startmenu.is_taskbar_fixed(id) and meta.window then
    UI.focus_window_by_title(meta.window)
    return
  end
  if meta.entry and meta.package_dir then
    local ok, err = startmenu.run_package(id)
    if ok then
      if meta.window then
        UI.focus_window_by_title(meta.window)
      else
        UI.focus_window_by_title("Console")
      end
    else
      _G.DovOS_log = _G.DovOS_log or {}
      _G.DovOS_log[#_G.DovOS_log + 1] = "[app] " .. tostring(err)
    end
    UI.redraw()
    return
  end
  if meta.window then UI.focus_window_by_title(meta.window) end
end

function UI.toggle_start()
  UI.start_open = not UI.start_open
  UI.redraw()
end

--- Hit-test taskbar (cell coords). Returns "start", "search", 1-based slot index, or nil.
function UI.taskbar_hit(cx, cy)
  UI.update_size()
  local y0 = UI.H - UI.TASKBAR_H + 1
  local th = UI.TASKBAR_H
  if cy < y0 or cy > y0 + th - 1 then return nil end
  local start_h = (th >= 3) and 2 or th
  if cx >= 2 and cx <= 5 and cy <= y0 + start_h - 1 then return "start" end
  local slots, search_w, settings_x = UI.taskbar_slots_visible()
  local trash_x = UI.W - 19
  local step = startmenu.taskbar_icon_step()
  local slot_w = 6
  if cx >= 7 and cx <= 7 + search_w - 1 then return "search" end
  local x = 7 + search_w + 1
  for i = 1, #slots do
    local sx
    if i <= #slots - 2 then
      sx = 7 + search_w + 1 + (i - 1) * step
    elseif i == #slots - 1 then
      sx = settings_x
    else
      sx = trash_x
    end
    if cx >= sx and cx <= sx + slot_w - 1 then return i end
  end
  return nil
end

--- Hit-test start menu panel (cell coords). Returns "panel", "search" (top row), or nil.
function UI.start_menu_hit(cx, cy)
  if not UI.start_open then return nil end
  local th = UI.TASKBAR_H
  local pw = math.min(50, math.max(36, math.floor(UI.W * 0.52)))
  local ph = math.min(UI.H - th - 2, math.max(14, math.floor(UI.H * 0.68)))
  local py = UI.H - th - ph + 1
  local px = 2
  if cx < px or cx > px + pw - 1 or cy < py or cy > py + ph - 1 then return nil end
  if cy <= py + 1 then return "search" end
  return "panel"
end

--- Handle one input event (key or mouse). GLFW: ESC=1, ENTER=28, LEFT=203, RIGHT=205, TAB=15.
function UI.handle_event(e)
  if e.type == "key" then
    local key = e.key
    local down = (e.down == true)
    if not down then return end
    local fw = UI.desk and window.Desktop.focused(UI.desk)
    if fw and fw.title == "Editor" and not fw.minimized then
      if UI.editor_handle_key(e) then
        UI.redraw()
        return
      end
    end
    if key == 1 then
      UI.start_open = false
      UI.activities_open = false
      UI.redraw()
      return
    end
    if key == 15 and UI.desk then
      window.Desktop.focus_next(UI.desk)
      UI.redraw()
      return
    end
    if key == 28 then
      local slots = UI.taskbar_slots_visible()
      local id = slots[UI.taskbar_sel]
      if id then UI.launch_app(id) end
      UI.redraw()
      return
    end
    if key == 203 or key == 205 then
      local slots = UI.taskbar_slots_visible()
      local n = #slots
      if n >= 1 then
        if key == 203 then
          UI.taskbar_sel = (UI.taskbar_sel - 2 + n) % n + 1
        else
          UI.taskbar_sel = (UI.taskbar_sel % n) + 1
        end
        UI.redraw()
      end
      return
    end
  end
  if e.type == "mouse" then
    local cx, cy = input.pixel_to_cell(e.x, e.y, UI.W, UI.H)
    local left = (e.button == "left")

    if UI._drag and e.type == "mouse" then
      if left and e.released == true then
        UI._drag = nil
        UI.redraw()
        return
      end
      if e.wheel and e.wheel ~= 0 then
        return
      end
      if e.button == "right" or e.button == "middle" then
        return
      end
      if e.button ~= "left" and e.button ~= "none" then
        return
      end
      local w = UI._drag.win
      if w and not w.maximized and not w.minimized then
        local wx, wy, ww, wh = UI.workspace_rect()
        w.x = math.max(wx, math.min(wx + ww - w.w, cx - UI._drag.offx))
        w.y = math.max(wy, math.min(wy + wh - w.h, cy - UI._drag.offy))
      end
      UI.redraw()
      return
    end

    if not (left and e.pressed == true) then return end

    local hit = UI.taskbar_hit(cx, cy)
    if hit == "start" then
      UI.toggle_start()
      return
    end
    if hit == "search" then
      if UI.start_open then UI.start_open = false end
      UI.redraw()
      return
    end
    if type(hit) == "number" then
      local slots = UI.taskbar_slots_visible()
      if slots[hit] then
        UI.taskbar_sel = hit
        UI.launch_app(slots[hit])
        UI.start_open = false
        UI.redraw()
      end
      return
    end

    if UI.start_open and UI.start_menu_hit(cx, cy) then
      return
    end
    if UI.start_open then
      UI.start_open = false
      UI.redraw()
      return
    end

    if UI.activities_open then
      return
    end

    local mw = UI.minimized_strip_hit(cx, cy)
    if mw then
      mw.minimized = false
      window.Desktop.bring_to_front(UI.desk, mw)
      window.Desktop.set_focus(UI.desk, mw)
      UI.redraw()
      return
    end

    local win = UI.top_window_at(cx, cy)
    if win then
      local zone = window.hit_chrome(win, cx, cy)
      if zone == "close" then
        window.Desktop.remove(UI.desk, win)
        UI.redraw()
        return
      end
      if zone == "max" then
        UI.window_toggle_maximize(win)
        window.Desktop.bring_to_front(UI.desk, win)
        window.Desktop.set_focus(UI.desk, win)
        UI.redraw()
        return
      end
      if zone == "min" then
        UI.window_minimize(win)
        UI.redraw()
        return
      end
      if zone == "drag" then
        window.Desktop.bring_to_front(UI.desk, win)
        window.Desktop.set_focus(UI.desk, win)
        UI._drag = { win = win, offx = cx - win.x, offy = cy - win.y }
        UI.redraw()
        return
      end
      if zone == "client" then
        if win.title == "Settings" then
          local rcx = cx - win:client_x()
          local rcy = cy - win:client_y()
          for _, z in ipairs(UI._settings_zones or {}) do
            if rcx >= z.x0 and rcx <= z.x1 and rcy >= z.y0 and rcy <= z.y1 then
              UI.settings_dispatch(z.tag)
              window.Desktop.bring_to_front(UI.desk, win)
              window.Desktop.set_focus(UI.desk, win)
              UI.redraw()
              return
            end
          end
        end
        window.Desktop.bring_to_front(UI.desk, win)
        window.Desktop.set_focus(UI.desk, win)
        UI.redraw()
        return
      end
    end
  end
end

function UI.draw_taskbar()
  local t = dovtheme.load()
  local tb = t.mode == "dark" and "black" or 22
  local fg = "bright_white"
  local y0 = UI.H - UI.TASKBAR_H + 1
  local th = UI.TASKBAR_H
  local y_icon = y0
  local y_dock = y0 + th - 1
  gfx.setColor(fg, tb)
  gfx.fillRect(1, y0, UI.W, th, " ")
  -- Reset per-cell scale on taskbar band (icons will raise scale locally).
  gfx_rect_pixel_scale_reset(1, y0, UI.W, th)

  local gconf = UI._gfx_conf or read_gfx_conf()
  local tb_ips = gconf.taskbar_icon_pixel_scale

  local slots, search_w, settings_x = UI.taskbar_slots_visible()
  local trash_x = UI.W - 19
  if UI.taskbar_sel > #slots then UI.taskbar_sel = math.max(1, #slots) end

  local x = 2
  local start_h = (th >= 3) and 2 or th
  if UI.start_open then
    gfx.setColor("bright_white", 28)
    gfx.fillRect(x, y0, 4, start_h, " ")
  end
  gfx.setColor(fg, tb)
  gfx.text(x + 1, y_icon, "[")
  gfx.text(x + 2, y_icon, "S")
  gfx.text(x + 3, y_icon, "]")
  x = 7

  local sw = search_w
  UI.search_api().draw_taskbar(gfx, {
    x = x,
    y0 = y0,
    sw = sw,
    th = th,
    tb = tb,
    fg = fg,
    accent = 28,
    search_pixel_scale = gconf.search_pixel_scale,
  })

  x = 7 + sw + 1
  local si = 0
  local slot_w = 6
  local step = startmenu.taskbar_icon_step()
  local function draw_slot_at(sx, id)
    si = si + 1
    local m = startmenu.registry[id]
    if not m then return end
    local lines, nrows = startmenu.icon_taskbar_lines(m, th)
    gfx_rect_pixel_scale(sx, y_icon, slot_w, nrows, tb_ips, tb_ips)
    local sel = (si == UI.taskbar_sel)
    if sel then
      gfx.setColor("bright_white", 28)
      gfx.fillRect(sx, y_icon, slot_w, nrows, " ")
    end
    for i = 1, nrows do
      local L = lines[i] or ""
      local pad = math.max(0, math.floor((slot_w - #L) / 2))
      local ifg, ibg = gfx_icon_row_style(m, i, fg, tb, sel)
      gfx.setColor(ifg, ibg)
      gfx.text(sx + pad, y_icon + i - 1, L)
    end
  end

  for _, id in ipairs(startmenu.TASKBAR_LEFT) do
    draw_slot_at(x, id)
    x = x + step
  end
  for _, id in ipairs(startmenu.flatten_user_pins(14)) do
    if x + step > settings_x - 2 then break end
    draw_slot_at(x, id)
    x = x + step
  end
  for i, id in ipairs(startmenu.TASKBAR_RIGHT) do
    local sx = (i == 1) and settings_x or trash_x
    draw_slot_at(sx, id)
  end

  if th >= 3 then
    local gap_x = 7 + sw + 1
    local gap_w = settings_x - gap_x - 1
    if gap_w >= 7 then
      gfx.setColor(28, tb)
      local lab = "DovOS"
      gfx.text(gap_x + math.max(0, math.floor((gap_w - #lab) / 2)), y0 + 1, lab)
    end
  end

  local dt = dock_datetime_str()
  local world = dock_world_line()
  gfx.setColor(28, tb)
  gfx.text(UI.W - #dt, y_dock, dt)
  local room = UI.W - #dt - 4
  if room >= 8 then
    local wline = world
    if #wline > room then wline = wline:sub(1, room - 1) .. "…" end
    gfx.text(2, y_dock, wline)
  end
end

function UI.draw_start_menu()
  if not UI.start_open then return end
  local th = UI.TASKBAR_H
  local pw = math.min(50, math.max(36, math.floor(UI.W * 0.52)))
  local ph = math.min(UI.H - th - 2, math.max(14, math.floor(UI.H * 0.68)))
  local py = UI.H - th - ph + 1
  local px = 2
  local panel_bg = dovtheme.load().mode == "dark" and "black" or "white"
  local panel_fg = dovtheme.load().mode == "dark" and "white" or "black"
  local gconf = UI._gfx_conf or read_gfx_conf()
  local icon_ips = gconf.icon_pixel_scale
  gfx.setColor(panel_fg, panel_bg)
  gfx.fillRect(px, py, pw, ph, " ")
  gfx_rect_pixel_scale_reset(px, py, pw, ph)
  gfx.setColor(22, panel_bg)
  gfx.rect(px, py, pw, ph, "#")
  gfx.setColor(panel_fg, panel_bg)
  local row = py + 1
  gfx.text(px + 1, row, " Search apps and files...")
  row = row + 2
  gfx.setColor(22, panel_bg)
  gfx.text(px + 1, row, "── Pinned (groups) ──")
  row = row + 1
  gfx.setColor(panel_fg, panel_bg)
  local groups = startmenu.load()
  local tile_w, gap = 14, 1
  local icon_rows = 4
  local tile_h = icon_rows + 1
  local cols = math.max(2, math.floor((pw - 3) / (tile_w + gap)))
  local function tile_icon_block(meta, max_w, nrows)
    local raw = startmenu.icon_lines(meta)
    while #raw > nrows do table.remove(raw) end
    for i = 1, #raw do
      if #raw[i] > max_w then raw[i] = raw[i]:sub(1, max_w) end
    end
    local blank = string.rep(" ", max_w)
    local top = math.floor((nrows - #raw) / 2)
    local out = {}
    for _ = 1, top do out[#out + 1] = blank end
    for i = 1, #raw do out[#out + 1] = raw[i] .. string.rep(" ", max_w - #raw[i]) end
    while #out < nrows do out[#out + 1] = blank end
    return out
  end
  for _, g in ipairs(groups) do
    if row >= py + ph - 8 then break end
    gfx.setColor(28, panel_bg)
    gfx.text(px + 1, row, g.name)
    row = row + 1
    local col = 0
    for _, id in ipairs(g.ids) do
      local m = startmenu.registry[id]
      if m and row + tile_h <= py + ph - 6 then
        local tx = px + 2 + col * (tile_w + gap)
        local iw = tile_w - 2
        gfx.setColor(22, panel_bg)
        gfx.fillRect(tx, row, tile_w, tile_h, " ")
        local block = tile_icon_block(m, iw, icon_rows)
        gfx_rect_pixel_scale(tx + 1, row, iw, icon_rows, icon_ips, icon_ips)
        for r = 1, icon_rows do
          local ifg, ibg = gfx_icon_row_style(m, r, "bright_white", 22, false)
          gfx.setColor(ifg, ibg)
          gfx.text(tx + 1, row + r - 1, block[r])
        end
        gfx_rect_pixel_scale_reset(tx + 1, row, iw, icon_rows)
        gfx.setColor(panel_fg, panel_bg)
        local lab = m.label:sub(1, iw)
        gfx.text(tx + 1, row + icon_rows, lab .. string.rep(" ", iw - #lab))
        col = col + 1
        if col >= cols then
          col = 0
          row = row + tile_h + 1
        end
      end
    end
    if col > 0 then row = row + tile_h + 1 end
    row = row + 1
  end
  gfx.setColor(22, panel_bg)
  gfx.text(px + 1, row, "── All apps ──")
  row = row + 1
  gfx.setColor(panel_fg, panel_bg)
  for _, id in ipairs(startmenu.all_app_ids()) do
    if row >= py + ph - 3 then break end
    local m = startmenu.registry[id]
    local mark = (startmenu.icon_lines(m)[1] or "?"):sub(1, 8)
    local mx = px + 2
    local ifg, ibg = gfx_icon_row_style(m, 1, panel_fg, panel_bg, false)
    gfx.setColor(ifg, ibg)
    gfx.text(mx, row, mark)
    gfx.setColor(panel_fg, panel_bg)
    gfx.text(mx + #mark, row, "  " .. m.label .. "  (" .. id .. ")")
    row = row + 1
  end
  gfx.setColor(28, panel_bg)
  gfx.text(px + 1, py + ph - 2, "pin user apps only  find|search <text>")
end

function UI.draw_activities_overlay()
  if not UI.activities_open then return end
  local mx = math.max(3, math.floor(UI.W * 0.04))
  local my = math.max(2, math.floor(UI.H * 0.06))
  local ow, oh = UI.W - 2 * mx, UI.H - 2 * my
  gfx.setColor("white", "black")
  gfx.fillRect(mx, my, ow, oh, " ")
  gfx.setColor(22, "white")
  gfx.rect(mx, my, ow, oh, "#")
  gfx.setColor("black", "white")
  local ix = mx + 2
  local iy = my + 1
  gfx.text(ix, iy, " Activities")
  gfx.text(ix, iy + 2, "Search: ______ (keyboard API)")
  gfx.text(ix, iy + 4, "Windows:")
  local row = iy + 6
  if UI.desk and UI.desk._windows then
    for _, w in ipairs(UI.desk._windows) do
      if row >= my + oh - 3 then break end
      local tag = w.minimized and " (min)" or ""
      gfx.text(ix + 2, row, "- " .. (w.title or "Window") .. tag)
      row = row + 1
    end
  end
  gfx.text(ix, my + oh - 2, "Esc when keys work")
end

function UI.redraw()
  UI.update_size()
  UI._size_set(UI.W, UI.H)
  -- LuaMade canvas overlays: higher cell scale = more screen pixels per character (sharper UI).
  if not UI._gfx_backend_canvas and gfx and type(gfx.setBackend) == "function" then
    pcall(gfx.setBackend, "canvas")
    UI._gfx_backend_canvas = true
  end
  UI._gfx_conf = read_gfx_conf()
  local sc = UI._gfx_conf.cell_scale
  if gfx and type(gfx.setCellScale) == "function" then
    pcall(gfx.setCellScale, sc, sc)
  end
  if gfx.getPixelWidth and gfx.getPixelHeight then
    local ok, pw, ph = pcall(function()
      return gfx.getPixelWidth(), gfx.getPixelHeight()
    end)
    if ok and pw and ph and pw > 0 and ph > 0 then
      input.set_canvas_pixels(pw, ph)
    end
  end
  gfx.setAnsiEnabled(true)
  local key = UI.W .. "x" .. UI.H
  if UI.desk and UI._canvas_key ~= key then
    UI.desk = nil
  end
  if not UI.desk then
    UI.build_desktop()
    UI._canvas_key = key
  end
  UI.search_step(24)
  local wx, wy, ww, wh = UI.workspace_rect()
  window.Desktop.paint_region(UI.desk, wx, wy, ww, wh)
  for _, w in ipairs(UI.desk._windows) do
    if not w.minimized then
      local paint = UI.paint_window_content[w.title]
      if paint then paint(w) end
    end
  end
  UI.draw_minimized_strip()
  UI.draw_taskbar()
  UI.draw_start_menu()
  UI.draw_activities_overlay()
  gfx.render()
end

function UI.toggle_activities()
  UI.activities_open = not UI.activities_open
  UI.redraw()
end

--- Focus the first window matching any of the titles (Guide vs legacy Welcome/Help).
function UI.focus_window_by_title_one_of(...)
  local order = { ... }
  if not UI.desk then return end
  for _, title in ipairs(order) do
    for _, w in ipairs(UI.desk._windows) do
      if w.title == title then
        w.minimized = false
        window.Desktop.bring_to_front(UI.desk, w)
        window.Desktop.set_focus(UI.desk, w)
        UI.redraw()
        return
      end
    end
  end
end

function UI.focus_window_by_title(title)
  if not UI.desk then return end
  for _, w in ipairs(UI.desk._windows) do
    if w.title == title then
      w.minimized = false
      window.Desktop.bring_to_front(UI.desk, w)
      window.Desktop.set_focus(UI.desk, w)
      UI.redraw()
      return
    end
  end
end

function UI.top_window_at(cx, cy)
  if not UI.desk or not UI.desk._windows then return nil end
  for i = #UI.desk._windows, 1, -1 do
    local w = UI.desk._windows[i]
    if not w.minimized and cx >= w.x and cy >= w.y and cx <= w.x + w.w - 1 and cy <= w.y + w.h - 1 then
      return w
    end
  end
  return nil
end

function UI.window_toggle_maximize(w)
  if not w or w.minimized then return end
  local wx, wy, ww, wh = UI.workspace_rect()
  if w.maximized then
    if w._restore then
      w.x, w.y, w.w, w.h = w._restore.x, w._restore.y, w._restore.w, w._restore.h
    end
    w.maximized = false
    w._restore = nil
  else
    w._restore = { x = w.x, y = w.y, w = w.w, h = w.h }
    w.x, w.y, w.w, w.h = wx, wy, ww, wh
    w.maximized = true
  end
end

function UI.window_minimize(w)
  if not w then return end
  if w.maximized and w._restore then
    w.x, w.y, w.w, w.h = w._restore.x, w._restore.y, w._restore.w, w._restore.h
    w.maximized = false
    w._restore = nil
  end
  w.minimized = true
  window.Desktop.focus_next(UI.desk)
end

function UI.draw_minimized_strip()
  UI._min_strip = {}
  if not UI.desk then return end
  local y0 = UI.H - UI.TASKBAR_H
  local has = false
  for _, w in ipairs(UI.desk._windows) do
    if w.minimized then has = true break end
  end
  if not has then return end
  local t = dovtheme.load()
  local bg = t.mode == "dark" and 235 or 252
  gfx.setColor(28, bg)
  gfx.fillRect(1, y0, UI.W, 1, " ")
  gfx.setColor("bright_white", 22)
  local x = 2
  gfx.text(1, y0, " ")
  for _, w in ipairs(UI.desk._windows) do
    if w.minimized then
      local seg = "[" .. (w.title:sub(1, 12)) .. "]"
      if x + #seg > UI.W then break end
      gfx.text(x, y0, seg)
      UI._min_strip[#UI._min_strip + 1] = { w = w, x0 = x, x1 = x + #seg - 1 }
      x = x + #seg + 2
    end
  end
end

function UI.minimized_strip_hit(cx, cy)
  local y0 = UI.H - UI.TASKBAR_H
  if cy ~= y0 then return nil end
  for _, r in ipairs(UI._min_strip or {}) do
    if cx >= r.x0 and cx <= r.x1 then return r.w end
  end
  return nil
end

function UI.focus_next_window()
  if not UI.desk then return end
  window.Desktop.focus_next(UI.desk)
  UI.redraw()
end

function UI.files_set_dir(path)
  path = path_normalize(path or "/home")
  if path_is_dovos_tree(path) and not UI.developer_mode_enabled() then
    _G.DovOS_log = _G.DovOS_log or {}
    _G.DovOS_log[#_G.DovOS_log + 1] =
      "[Files] /home/dovos is hidden. Use /home/apps or enable Developer mode."
    path = "/home"
  end
  UI.files_dir = path
  UI.redraw()
end

function UI.boot()
  if not _G.DovOS_log then _G.DovOS_log = {} end
  if path_is_dovos_tree(path_normalize(UI.files_dir or "")) and not UI.developer_mode_enabled() then
    UI.files_dir = "/home"
  end
  UI.build_desktop()
  UI.redraw()
end

--- True when a focused control should receive typing (Editor, future search field, …).
--- Optional: set UI.extra_input_text_active = function() return bool end
function UI.input_text_active()
  if type(UI.extra_input_text_active) == "function" and UI.extra_input_text_active() then
    return true
  end
  local d = UI.desk
  if not d then return false end
  local fw = window.Desktop.focused(d)
  return fw and not fw.minimized and fw.title == "Editor"
end

--- Keys that only make sense in a text field; cancel via input.cancelKeyEvent when not editing.
local function key_expects_text_target(e)
  if e.type ~= "key" then return false end
  if e.ctrl or e.alt then return false end
  if type(e.char) == "string" and e.char ~= "" then
    local b = string.byte(e.char, 1)
    if b and b >= 32 then return true end
  end
  local k = tonumber(e.key) or 0
  if k == 14 or k == 259 then return true end
  if k == 261 then return true end
  return false
end

--- Run input loop (blocking). Polls mod input, handles key/mouse, redraws on events.
function UI.run_loop()
  while true do
    local events = input.poll_all()
    if #events == 0 then
      local one = input.waitFor(16)
      if one then events = { one } end
    end
    for _, ev in ipairs(events) do
      if not ev then
      elseif ev.type == "key" and key_expects_text_target(ev) and not UI.input_text_active() then
        input.cancelKeyEvent(ev)
      else
        UI.handle_event(ev)
      end
    end
    if #events > 0 then UI.redraw() end
  end
end

return UI
