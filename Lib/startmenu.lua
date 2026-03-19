--[[
  Start menu + taskbar. App metadata loads from appinfo.json only:
    /home/AtlasOS/apps/<folder>/appinfo.json  (system, defined load order)
    + any extra folders under /home/AtlasOS/apps
    /home/apps/<folder>/appinfo.json       (user; cannot override system ids)

  Left (fixed):  files, console, status  |  Right: settings, trash
  Persist: /etc/AtlasOS/start_menu.txt
]]

local PATH = "/etc/AtlasOS/start_menu.txt"
local AtlasOS_APPS = "/home/AtlasOS/apps"
--- Folders to load first (order); id comes from each appinfo.json.
local SYSTEM_FOLDER_ORDER = {
  "welcome",
  "files",
  "console",
  "status",
  "settings",
  "trash",
  "search",
  "editor",
}

local startmenu = {}

startmenu.registry = {}
startmenu._AtlasOS_search = nil
--- Ids registered from /home/AtlasOS/apps (user /home/apps may not replace these)
startmenu._system_ids = {}
--- folder name in SYSTEM_FOLDER_ORDER -> app id (e.g. search -> taskbar_search)
startmenu._AtlasOS_folder_id = {}

local TB_SLOT_W, TB_STEP = 6, 7

function startmenu.icon_lines(meta)
  if not meta then return { "?" } end
  if type(meta.icon) == "table" then
    local o = {}
    for i = 1, #meta.icon do
      o[#o + 1] = tostring(meta.icon[i])
    end
    return #o > 0 and o or { "?" }
  end
  local s = meta.icon
  if type(s) ~= "string" or s == "" then return { "?" } end
  local lines = {}
  for line in s:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then return { s } end
  return lines
end

function startmenu.icon_taskbar_lines(meta, th)
  if meta.icon_compact and type(meta.icon_compact) == "string" then
    local s = meta.icon_compact
    if #s > TB_SLOT_W then s = s:sub(1, TB_SLOT_W) end
    return { s }, 1
  end
  local lines = startmenu.icon_lines(meta)
  local max_rows = (th >= 3) and 2 or 1
  local out = {}
  for i = 1, math.min(max_rows, #lines) do
    local L = lines[i]
    if #L > TB_SLOT_W then L = L:sub(1, TB_SLOT_W) end
    out[#out + 1] = L
  end
  if #out == 0 then out[1] = "?" end
  return out, #out
end

function startmenu.taskbar_icon_step()
  return TB_STEP
end

local WINDOW_FOR_SLOT = {
  files = "Files",
  console = "Console",
  status = "Status",
  settings = "Settings",
  trash = "Trash",
}

local function register_from_app(app)
  if app.AtlasOS and app.AtlasOS.role == "search_engine" and type(app.AtlasOS.search_engine) == "string" then
    startmenu._AtlasOS_search = { package_dir = app.package_dir, module = app.AtlasOS.search_engine }
  end
  startmenu.registry[app.id] = {
    label = app.name,
    icon = app.icon,
    icon_compact = app.icon_compact,
    icon_fg = app.icon_fg,
    icon_bg = app.icon_bg,
    icon_row_fg = app.icon_row_fg,
    icon_taskbar_sel_fg = app.icon_taskbar_sel_fg,
    window = app.window,
    description = app.description or "",
    entry = app.entry,
    args = app.args or {},
    package_dir = app.package_dir,
    paint_module = app.AtlasOS and app.AtlasOS.paint_module,
  }
end

local function ensure_taskbar_slot(id)
  if startmenu.registry[id] then return end
  local w = WINDOW_FOR_SLOT[id]
  if not w then return end
  startmenu.registry[id] = {
    label = w,
    icon = "?",
    window = w,
    description = "Install " .. AtlasOS_APPS .. "/" .. id .. "/appinfo.json",
    entry = nil,
    args = {},
    package_dir = "",
  }
  startmenu._system_ids[id] = true
end

function startmenu.refresh_packages()
  for k in pairs(startmenu.registry) do
    startmenu.registry[k] = nil
  end
  startmenu._AtlasOS_search = nil
  for k in pairs(startmenu._system_ids) do
    startmenu._system_ids[k] = nil
  end
  for k in pairs(startmenu._AtlasOS_folder_id) do
    startmenu._AtlasOS_folder_id[k] = nil
  end

  local ok, appinfo = pcall(dofile, "/home/lib/appinfo.lua")
  if not ok or not appinfo or not appinfo.load_package or not appinfo.scan then
    return
  end

  local seen_id = {}

  for _, folder in ipairs(SYSTEM_FOLDER_ORDER) do
    local dir = AtlasOS_APPS .. "/" .. folder
    local app = appinfo.load_package(dir)
    if app then
      register_from_app(app)
      seen_id[app.id] = true
      startmenu._system_ids[app.id] = true
      startmenu._AtlasOS_folder_id[folder] = app.id
    end
  end

  for _, app in ipairs(appinfo.scan(AtlasOS_APPS)) do
    if not seen_id[app.id] then
      register_from_app(app)
      seen_id[app.id] = true
      startmenu._system_ids[app.id] = true
    end
  end

  for _, id in ipairs(startmenu.TASKBAR_LEFT) do
    ensure_taskbar_slot(id)
  end
  for _, id in ipairs(startmenu.TASKBAR_RIGHT) do
    ensure_taskbar_slot(id)
  end

  local PIN_DEFAULT = {
    welcome = "Guide",
    editor = "Editor",
  }
  for id, title in pairs(PIN_DEFAULT) do
    if not startmenu.registry[id] then
      startmenu.registry[id] = {
        label = title,
        icon = "?",
        window = title,
        description = "Add package: " .. AtlasOS_APPS .. "/" .. id,
        entry = nil,
        args = {},
        package_dir = "",
      }
      startmenu._system_ids[id] = true
    end
  end

  for _, app in ipairs(appinfo.scan("/home/apps")) do
    if app.AtlasOS and app.AtlasOS.role == "search_engine" and type(app.AtlasOS.search_engine) == "string" then
      startmenu._AtlasOS_search = { package_dir = app.package_dir, module = app.AtlasOS.search_engine }
    end
    if not startmenu._system_ids[app.id] then
      register_from_app(app)
    end
  end
end

startmenu.refresh_packages()

startmenu.TASKBAR_LEFT = { "files", "console", "status" }
startmenu.TASKBAR_RIGHT = { "settings", "trash" }

function startmenu.is_taskbar_fixed(id)
  for _, x in ipairs(startmenu.TASKBAR_LEFT) do
    if x == id then return true end
  end
  for _, x in ipairs(startmenu.TASKBAR_RIGHT) do
    if x == id then return true end
  end
  return false
end

function startmenu.can_user_pin(id)
  if not startmenu.registry[id] then return false end
  return not startmenu.is_taskbar_fixed(id)
end

local function scrub_groups(groups)
  for _, g in ipairs(groups) do
    for i = #g.ids, 1, -1 do
      if startmenu.is_taskbar_fixed(g.ids[i]) then table.remove(g.ids, i) end
    end
  end
end

function startmenu.default_groups()
  local ids = {}
  local seen = {}
  local function try_add(id)
    if not id or seen[id] then return end
    if startmenu.registry[id] and startmenu.can_user_pin(id) then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  for _, folder in ipairs(SYSTEM_FOLDER_ORDER) do
    local id = startmenu._AtlasOS_folder_id[folder] or folder
    try_add(id)
  end
  local extra = {}
  for id in pairs(startmenu.registry) do
    if startmenu._system_ids[id] and not seen[id] and startmenu.can_user_pin(id) then
      extra[#extra + 1] = id
    end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do
    try_add(id)
  end
  if #ids == 0 then
    try_add("welcome")
  end
  return { { name = "Pinned", ids = ids } }
end

function startmenu.load()
  local raw = fs.read(PATH)
  if not raw or raw == "" then return startmenu.default_groups() end
  local groups = {}
  local cur = nil
  for line in raw:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$") or ""
    if line == "" or line == "v1" then
    elseif line:match("^group%s+") then
      cur = { name = line:match("^group%s+(.+)$") or "Pinned", ids = {} }
      groups[#groups + 1] = cur
    elseif cur and startmenu.registry[line] and startmenu.can_user_pin(line) then
      cur.ids[#cur.ids + 1] = line
    end
  end
  scrub_groups(groups)
  if #groups == 0 then return startmenu.default_groups() end
  return groups
end

function startmenu.save(groups)
  scrub_groups(groups)
  fs.makeDir("/etc/AtlasOS")
  local lines = { "v1" }
  for _, g in ipairs(groups) do
    lines[#lines + 1] = "group " .. g.name
    for _, id in ipairs(g.ids) do
      if startmenu.can_user_pin(id) then lines[#lines + 1] = id end
    end
  end
  fs.write(PATH, table.concat(lines, "\n"))
end

local function remove_id(groups, id)
  for _, g in ipairs(groups) do
    for i = #g.ids, 1, -1 do
      if g.ids[i] == id then table.remove(g.ids, i) end
    end
  end
end

local function find_group(groups, name)
  for _, g in ipairs(groups) do
    if g.name == name then return g end
  end
  return nil
end

function startmenu.pin(id, group_name)
  if not startmenu.can_user_pin(id) then
    return false, "reserved (taskbar left/right)"
  end
  local groups = startmenu.load()
  remove_id(groups, id)
  group_name = group_name or "Pinned"
  local g = find_group(groups, group_name)
  if not g then
    g = { name = group_name, ids = {} }
    groups[#groups + 1] = g
  end
  g.ids[#g.ids + 1] = id
  startmenu.save(groups)
  return true
end

function startmenu.unpin(id)
  if not startmenu.can_user_pin(id) then
    return false, "cannot unpin taskbar icon"
  end
  local groups = startmenu.load()
  remove_id(groups, id)
  startmenu.save(groups)
  return true
end

function startmenu.new_group(name)
  if not name or name == "" then return false end
  local groups = startmenu.load()
  if find_group(groups, name) then return false, "group exists" end
  groups[#groups + 1] = { name = name, ids = {} }
  startmenu.save(groups)
  return true
end

function startmenu.flatten_user_pins(max_n)
  max_n = max_n or 16
  local groups = startmenu.load()
  local out = {}
  local seen = {}
  for _, g in ipairs(groups) do
    for _, id in ipairs(g.ids) do
      if startmenu.registry[id] and startmenu.can_user_pin(id) and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
        if #out >= max_n then return out end
      end
    end
  end
  return out
end

function startmenu.taskbar_slots()
  local s = {}
  for _, id in ipairs(startmenu.TASKBAR_LEFT) do
    s[#s + 1] = id
  end
  for _, id in ipairs(startmenu.flatten_user_pins(14)) do
    s[#s + 1] = id
  end
  for _, id in ipairs(startmenu.TASKBAR_RIGHT) do
    s[#s + 1] = id
  end
  return s
end

function startmenu.all_app_ids()
  local t = {}
  for id in pairs(startmenu.registry) do
    t[#t + 1] = id
  end
  table.sort(t)
  return t
end

function startmenu.run_package(id)
  local m = startmenu.registry[id]
  if not m or not m.entry or not m.package_dir or m.package_dir == "" then
    return false, "not an installed package app (needs appinfo.json + entry)"
  end
  local path = m.entry
  if path:sub(1, 1) ~= "/" then
    path = m.package_dir .. "/" .. path
  end
  if not fs.read(path) then
    return false, "entry not found: " .. path
  end
  local argv = {}
  for j = 1, #(m.args or {}) do
    argv[j] = tostring(m.args[j])
  end
  _G.AtlasOS_APP = { id = id, package_dir = m.package_dir, args = argv }
  local ok, err = pcall(dofile, path)
  _G.AtlasOS_APP = nil
  if not ok then
    return false, tostring(err)
  end
  return true
end

return startmenu
