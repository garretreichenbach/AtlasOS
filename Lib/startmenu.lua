--[[
  Start menu + taskbar. App metadata loads from appinfo.json only:
    /home/AtlasOS/apps/<folder>/appinfo.json  (system, defined load order)
    + any extra folders under /home/AtlasOS/apps
    /home/apps/<folder>/appinfo.json       (user; cannot override system ids)

  Left (fixed):  files, console  |  Right: settings, trash  (host · cwd in taskbar gap; Status app optional)
  Persist: /etc/AtlasOS/start_menu.json  (legacy: start_menu.txt, auto-migrated once)
]]

local json = require("json")
local PATH_JSON = "/etc/AtlasOS/start_menu.json"
local PATH_LEGACY = "/etc/AtlasOS/start_menu.txt"
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
  "chat",
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
  trash = "Files",
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

startmenu.TASKBAR_LEFT = { "files", "console" }
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

local function parse_legacy_txt(raw)
  local groups = {}
  local cur = nil
  for line in tostring(raw or ""):gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$") or ""
    if line == "" or line == "v1" then
    elseif line:match("^group%s+") then
      cur = { name = line:match("^group%s+(.+)$") or "Pinned", ids = {} }
      groups[#groups + 1] = cur
    elseif cur and startmenu.registry[line] and startmenu.can_user_pin(line) then
      cur.ids[#cur.ids + 1] = line
    end
  end
  return groups
end

local function groups_from_json(t)
  if type(t) ~= "table" then return {} end
  local arr = t.groups
  if type(arr) ~= "table" then return {} end
  local groups = {}
  for _, g in ipairs(arr) do
    if type(g) == "table" and type(g.name) == "string" and g.name ~= "" then
      local ids = {}
      if type(g.ids) == "table" then
        for _, id in ipairs(g.ids) do
          if type(id) == "string" and startmenu.registry[id] and startmenu.can_user_pin(id) then
            ids[#ids + 1] = id
          end
        end
      end
      groups[#groups + 1] = { name = g.name, ids = ids }
    end
  end
  return groups
end

local function try_remove_legacy()
  if fs.delete then pcall(fs.delete, PATH_LEGACY) end
  if fs.remove then pcall(fs.remove, PATH_LEGACY) end
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
  if fs.read then
    local jraw = fs.read(PATH_JSON)
    if type(jraw) == "string" and jraw:gsub("%s", "") ~= "" then
      local ok, t = pcall(json.decode, jraw)
      if ok and type(t) == "table" then
        local groups = groups_from_json(t)
        scrub_groups(groups)
        if #groups > 0 then return groups end
      end
    end

    local traw = fs.read(PATH_LEGACY)
    if type(traw) == "string" and traw ~= "" then
      local groups = parse_legacy_txt(traw)
      scrub_groups(groups)
      if #groups > 0 then
        startmenu.save(groups)
        try_remove_legacy()
        return groups
      end
    end
  end
  return startmenu.default_groups()
end

function startmenu.save(groups)
  scrub_groups(groups)
  if not fs.makeDir or not fs.write then return end
  pcall(fs.makeDir, "/etc/AtlasOS")
  local out_groups = {}
  for _, g in ipairs(groups) do
    local ids = {}
    for _, id in ipairs(g.ids) do
      if startmenu.can_user_pin(id) then ids[#ids + 1] = id end
    end
    out_groups[#out_groups + 1] = { name = g.name, ids = ids }
  end
  local payload = { version = 1, groups = out_groups }
  local ok, encoded = pcall(json.encode, payload)
  if ok and type(encoded) == "string" then
    pcall(fs.write, PATH_JSON, encoded)
  end
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
  if not m or not m.package_dir or m.package_dir == "" then
    return false, "not an installed package app (needs appinfo.json)"
  end
  local argv = {}
  for j = 1, #(m.args or {}) do
    argv[j] = tostring(m.args[j])
  end
  local path = m.entry
  if type(path) == "string" and path ~= "" then
    if path:sub(1, 1) ~= "/" then
      path = m.package_dir .. "/" .. path
    end
    if not fs.read(path) then
      return false, "entry not found: " .. path
    end
    _G.AtlasOS_APP = { id = id, package_dir = m.package_dir, args = argv }
    local ok, err = pcall(dofile, path)
    _G.AtlasOS_APP = nil
    if not ok then
      return false, tostring(err)
    end
    return true
  end
  if m.paint_module or m.window then
    return true
  end
  return false, "no entry script (set entry or AtlasOS.paint_module / window)"
end

return startmenu
