--[[
  AtlasOS theme management: dark/light mode persistence and styling.
  Themes stored in /etc/AtlasOS/theme.json
]]

local json = require("json")
local PATH = "/etc/AtlasOS/theme.json"

local DEFAULT_THEME = {
  mode = "light",
  colors = {
    light = {
      bg = "white",
      fg = "black",
      highlight_bg = "bright_white",
      highlight_fg = "black",
      taskbar_bg = "bright_white",
      taskbar_fg = "black",
      window_bg = "white",
      window_title_bg = "bright_white",
      window_title_fg = "black",
      window_border_fg = "black",
    },
    dark = {
      bg = "black",
      fg = "bright_white",
      highlight_bg = "bright_black",
      highlight_fg = "bright_white",
      taskbar_bg = "bright_black",
      taskbar_fg = "bright_white",
      window_bg = "black",
      window_title_bg = "bright_black",
      window_title_fg = "bright_white",
      window_border_fg = "bright_white",
    }
  }
}

local function parse_raw(raw)
  if type(raw) ~= "string" or raw == "" then
    return DEFAULT_THEME
  end
  local ok, data = pcall(json.decode, raw)
  if not ok or type(data) ~= "table" then
    return DEFAULT_THEME
  end

  -- Validate mode
  if data.mode ~= "light" and data.mode ~= "dark" then
    data.mode = DEFAULT_THEME.mode
  end

  -- Merge with defaults to ensure all color fields exist
  if not data.colors then data.colors = {} end
  for mode, colors in pairs(DEFAULT_THEME.colors) do
    if not data.colors[mode] then data.colors[mode] = {} end
    for key, val in pairs(colors) do
      if not data.colors[mode][key] then
        data.colors[mode][key] = val
      end
    end
  end

  return data
end

local function read()
  local raw = fs.read and fs.read(PATH) or ""
  return parse_raw(raw)
end

local atlastheme = {}

--- Load current theme from disk
function atlastheme.load()
  return read()
end

--- Save theme to disk (mode: "light" or "dark")
function atlastheme.save(mode)
  if mode ~= "light" and mode ~= "dark" then
    mode = DEFAULT_THEME.mode
  end
  local t = read()
  t.mode = mode
  if fs.makeDir then pcall(fs.makeDir, "/etc/AtlasOS") end
  if fs.write then
    fs.write(PATH, json.encode(t))
  end
  return t
end

--- Toggle between light and dark mode
function atlastheme.toggle()
  local t = read()
  local new_mode = (t.mode == "light") and "dark" or "light"
  return atlastheme.save(new_mode)
end

--- Get current theme mode
function atlastheme.mode()
  return read().mode
end

--- Get color palette for current mode
function atlastheme.get_colors()
  local t = read()
  return t.colors[t.mode] or DEFAULT_THEME.colors[t.mode]
end

--- Apply theme to desktop window
function atlastheme.apply_desktop(desk)
  if not desk then return end
  local colors = atlastheme.get_colors()
  desk.bg_fg = colors.fg
  desk.bg_bg = colors.bg
  if desk.taskbar then
    desk.taskbar.bg = colors.taskbar_bg
    desk.taskbar.fg = colors.taskbar_fg
  end
end

--- Style a window frame with theme colors
function atlastheme.style_window(win, title)
  if not win then return end
  local colors = atlastheme.get_colors()
  win.title_bg = colors.window_title_bg
  win.title_fg = colors.window_title_fg
  win.client_bg = colors.window_bg
  win.client_fg = colors.fg
  win.border_fg = colors.window_border_fg
  if title then win.title = title end
end

return atlastheme

