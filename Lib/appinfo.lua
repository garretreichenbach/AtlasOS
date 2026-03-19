--[[
  AtlasOS installable app packages: appinfo.json per package directory.
  See /home/AtlasOS/APPINFO.md (or repo AtlasOS/APPINFO.md).
]]

local json = dofile("/home/lib/json.lua")

local appinfo = {}

--- @param package_dir string Absolute dir containing appinfo.json (no trailing slash required)
--- @return table|nil app  nil if missing/invalid
--- @return string|nil err
function appinfo.load_package(package_dir)
  package_dir = (package_dir or ""):gsub("/+$", "")
  if package_dir == "" then return nil, "empty dir" end
  local path = package_dir .. "/appinfo.json"
  local raw = fs.read(path)
  if not raw or raw == "" then return nil, "no appinfo.json" end
  local ok, t = pcall(json.decode, raw)
  if not ok or type(t) ~= "table" then
    return nil, "invalid json: " .. tostring(t)
  end
  local id = t.id
  if type(id) ~= "string" or id == "" or not id:match("^[%w_%-]+$") then
    id = package_dir:match("/([^/]+)$") or "app"
  end
  local name = t.name
  if type(name) ~= "string" or name == "" then name = id end
  local entry = t.entry
  if type(entry) ~= "string" or entry == "" then
    return nil, "entry required (lua file path)"
  end
  local args = t.args
  if args ~= nil then
    if type(args) ~= "table" then return nil, "args must be array" end
    for j = 1, #args do
      if type(args[j]) ~= "string" and type(args[j]) ~= "number" then
        return nil, "args must be strings or numbers"
      end
    end
  else
    args = {}
  end
  --- Multiline string (\\n) or JSON array of strings for ASCII-art tiles.
  local icon = t.icon
  if type(icon) == "table" then
    local lines = {}
    for i = 1, #icon do
      if type(icon[i]) == "string" then lines[#lines + 1] = icon[i] end
    end
    icon = #lines > 0 and lines or { "?" }
  elseif type(icon) == "string" and icon ~= "" then
    -- keep full string (newlines allowed)
  else
    icon = "?"
  end
  local desc = t.description
  if type(desc) ~= "string" then desc = "" end
  local window = t.window
  if window ~= nil and type(window) ~= "string" then window = nil end
  local version = t.version
  if version ~= nil and type(version) ~= "string" and type(version) ~= "number" then version = nil end

  local icon_compact = t.icon_compact
  if type(icon_compact) ~= "string" then icon_compact = nil end

  local icon_fg = type(t.icon_fg) == "string" and t.icon_fg ~= "" and t.icon_fg or nil
  local icon_bg = type(t.icon_bg) == "string" and t.icon_bg ~= "" and t.icon_bg or nil
  local icon_taskbar_sel_fg =
    type(t.icon_taskbar_sel_fg) == "string" and t.icon_taskbar_sel_fg ~= "" and t.icon_taskbar_sel_fg or nil
  local icon_row_fg = nil
  if type(t.icon_row_fg) == "table" then
    local rr = {}
    for j = 1, #t.icon_row_fg do
      rr[j] = type(t.icon_row_fg[j]) == "string" and t.icon_row_fg[j] or nil
    end
    icon_row_fg = rr
  end

  return {
    id = id,
    name = name,
    description = desc,
    icon = icon, -- string or array of strings
    icon_compact = icon_compact,
    icon_fg = icon_fg,
    icon_bg = icon_bg,
    icon_row_fg = icon_row_fg,
    icon_taskbar_sel_fg = icon_taskbar_sel_fg,
    version = version,
    entry = entry,
    args = args,
    window = window,
    package_dir = package_dir,
    AtlasOS = type(t.AtlasOS) == "table" and t.AtlasOS or nil,
    _raw = t,
  }
end

--- Scan immediate subdirs of root for valid packages.
function appinfo.scan(root)
  root = (root or "/home/apps"):gsub("/+$", "")
  local out = {}
  local ok, names = pcall(fs.list, root)
  if not ok or not names then return out end
  for _, name in ipairs(names) do
    local dir = root .. "/" .. name
    local isDir = false
    if fs.isDir then pcall(function() isDir = fs.isDir(dir) end) end
    if isDir then
      local app, err = appinfo.load_package(dir)
      if app then
        out[#out + 1] = app
      end
    end
  end
  table.sort(out, function(a, b) return a.id:lower() < b.id:lower() end)
  return out
end

return appinfo
