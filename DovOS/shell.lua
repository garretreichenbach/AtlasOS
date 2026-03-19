--[[
  DovOS — boots into Ubuntu-like desktop. Terminal commands = fallback until input API.
]]

if not _G.DovOS_log then _G.DovOS_log = {} end
local MAX_LOG = 200
local _print = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  local line = table.concat(parts, "\t")
  _G.DovOS_log[#_G.DovOS_log + 1] = line
  while #_G.DovOS_log > MAX_LOG do table.remove(_G.DovOS_log, 1) end
  _print(...)
end

-- One registry shared with ui.lua (avoid double-loading startmenu).
_G.startmenu = _G.startmenu or dofile("/home/lib/startmenu.lua")
_G.startmenu.refresh_packages()
local UI = dofile("/home/dovos/ui.lua")
local dovtheme = dofile("/home/lib/dovtheme.lua")
local startmenu = _G.startmenu

_G.DovOS_editor_open = function(path)
  if UI.editor_open then UI.editor_open(path) end
  pcall(function() UI.redraw() end)
end

term.registerCommand("reload_apps", function()
  startmenu.refresh_packages()
  if UI.invalidate_packages then UI.invalidate_packages() end
  print("Apps: /home/dovos/apps + /home/apps")
  UI.redraw()
end)

term.registerCommand("apps", function()
  local n = 0
  for _, id in ipairs(startmenu.all_app_ids()) do
    local m = startmenu.registry[id]
    if m.entry then
      n = n + 1
      local ic = m.icon
      if type(ic) == "table" then ic = ic[1] or "?"
      elseif type(ic) == "string" then ic = ic:match("^([^\r\n]+)") or ic
      else ic = "?" end
      print(string.format("  %-16s  %s  %s", id, ic:sub(1, 12), m.label or id))
      if (m.description or "") ~= "" then print("      " .. m.description) end
    end
  end
  if n == 0 then print("  (no package apps — add /home/apps/<name>/appinfo.json)") end
  print("System apps: /home/dovos/apps/*/appinfo.json")
end)

term.registerCommand("runapp", function(args)
  local id = args and args[1]
  if not id then print("runapp <app_id>  — see: apps") return end
  local ok, err = startmenu.run_package(id)
  if ok then print("App finished: " .. id) else print("Error: " .. tostring(err)) end
end)

term.registerCommand("desktop", function()
  UI.desk = nil
  UI.activities_open = false
  UI.start_open = false
  UI.boot()
  UI.run_loop()
end)

term.registerCommand("start", function()
  UI.toggle_start()
end)

term.registerCommand("pin", function(args)
  local id = args and args[1]
  local grp = args and args[2]
  if not id then print("pin <app_id> [Group]") return end
  local ok, err = startmenu.pin(id, grp)
  print(ok and ("Pinned " .. id) or tostring(err))
  UI.redraw()
end)

term.registerCommand("unpin", function(args)
  local id = args and args[1]
  if not id then print("unpin <app_id>") return end
  local ok, err = startmenu.unpin(id)
  print(ok and ("Unpinned " .. id) or tostring(err or "failed"))
  UI.redraw()
end)

term.registerCommand("pin_group", function(args)
  local name = args and args[1]
  if not name then print("pin_group <Name>") return end
  local ok, err = startmenu.new_group(name)
  print(ok and ("Group " .. name) or tostring(err or "exists"))
end)

term.registerCommand("go", function()
  local slots = UI.taskbar_slots_visible()
  local id = slots[UI.taskbar_sel]
  if id then UI.launch_app(id) else print("No pin at slot") end
end)

term.registerCommand("refresh", function()
  UI.redraw()
end)

term.registerCommand("activities", function()
  UI.toggle_activities()
end)

term.registerCommand("theme", function()
  dovtheme.toggle()
  UI.desk = nil
  UI.boot()
end)

term.registerCommand("devmode", function(args)
  local ok, ds = pcall(dofile, "/home/lib/dovsettings.lua")
  if not ok or not ds then
    print("dovsettings.lua missing")
    return
  end
  local a = args and args[1] and tostring(args[1]):lower()
  if a == "on" or a == "1" or a == "true" then
    ds.set_developer_mode(true)
    print("Developer mode: ON")
  elseif a == "off" or a == "0" or a == "false" then
    ds.set_developer_mode(false)
    print("Developer mode: OFF")
  else
    print("Developer mode: " .. (ds.developer_mode() and "ON" or "OFF"))
    print("  devmode on | devmode off")
  end
  UI.redraw()
end)

local function taskbar_advance()
  local slots = UI.taskbar_slots_visible()
  local n = #slots
  if n < 1 then return end
  UI.taskbar_sel = (UI.taskbar_sel % n) + 1
  UI.redraw()
end
term.registerCommand("tasknext", taskbar_advance)
term.registerCommand("docknext", taskbar_advance)

term.registerCommand("winnext", function()
  UI.focus_next_window()
end)

local function search_cmd(args)
  local parts = {}
  for i = 1, #(args or {}) do parts[#parts + 1] = args[i] end
  local needle = table.concat(parts, " ")
  if needle == "" then
    UI.search_clear()
    print("Search cleared.")
  else
    UI.search_begin(needle)
    print("Searching (runs while desktop refreshes): " .. needle)
  end
  UI.redraw()
end
term.registerCommand("search", search_cmd)
term.registerCommand("find", search_cmd)

term.registerCommand("search_status", function()
  local api = UI.search_api and UI.search_api() or nil
  if not api or not api.get_state then print("Search API unavailable") return end
  local s = api.get_state()
  print("Query: " .. (s.needle ~= "" and s.needle or "(none)"))
  print("Name hits: " .. #s.name_hits .. "  in-file: " .. #s.content_hits .. (s.busy and "  (busy)" or ""))
  for i = 1, math.min(12, #s.name_hits) do print("  " .. s.name_hits[i]) end
  for i = 1, math.min(8, #s.content_hits) do print("  @" .. s.content_hits[i]) end
end)

term.registerCommand("save_layout", function()
  UI.layout_save()
  print("Layout saved to " .. "/etc/dovos/layout.txt")
end)

term.registerCommand("welcome", function()
  UI.focus_window_by_title_one_of("Guide", "Welcome", "Help")
end)
term.registerCommand("files", function()
  UI.focus_window_by_title("Files")
end)
term.registerCommand("settings", function()
  UI.focus_window_by_title("Settings")
end)
term.registerCommand("help", function()
  UI.focus_window_by_title_one_of("Guide", "Welcome", "Help")
  print("start  tasknext  go  pin  unpin  pin_group")
  print("search|find <text>  search_status  search (no args)=clear")
  print("apps  runapp <id>  reload_apps")
  print("refresh  theme  devmode  activities  desktop  save_layout  cd")
end)
term.registerCommand("console", function()
  UI.focus_window_by_title("Console")
end)
term.registerCommand("editor", function(args)
  local p = args and args[1]
  if _G.DovOS_editor_open then
    _G.DovOS_editor_open(p)
  else
    print("editor [path]  — needs DovOS shell")
  end
end)

term.registerCommand("cd", function(args)
  local path = args and args[1]
  if not path or path == "" then
    print("Cwd: " .. (UI.files_dir or "/home"))
    return
  end
  if path == ".." then
    local d = UI.files_dir or "/home"
    d = d:gsub("/+$", "")
    local up = d:match("^(.+)/")
    UI.files_set_dir(up or "/")
  else
    local base = UI.files_dir or "/home"
    if path:sub(1, 1) == "/" then base = "" end
    local full = base:match("/$") and (base .. path) or (base .. "/" .. path)
    if fs.normalizePath then full = fs.normalizePath(full) end
    if fs.exists(full) then
      UI.files_set_dir(full)
      print("Files: " .. full)
    else
      print("No such path: " .. full)
    end
  end
end)

term.registerCommand("dovos", function()
  print("DovOS — start menu + taskbar  |  start  tasknext  go  pin")
end)

term.setAutoPrompt(true)
UI.boot()
