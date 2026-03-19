--[[
  AtlasOS settings persisted under /etc/AtlasOS/settings.json
  developer_mode — when false, Files hides /home/AtlasOS (users use /home/apps).
]]

local json = require("json")
local PATH = "/etc/AtlasOS/settings.json"

local function parse_raw(raw)
  if type(raw) ~= "string" or raw == "" then
    return { developer_mode = false }
  end
  local ok, data = pcall(json.decode, raw)
  if not ok or type(data) ~= "table" then
    return { developer_mode = false }
  end
  return { developer_mode = not not data.developer_mode }
end

local function read()
  local raw = fs.read and fs.read(PATH) or ""
  return parse_raw(raw)
end

local atlassettings = {}

function atlassettings.load()
  return read()
end

function atlassettings.save(t)
  t = t or read()
  if fs.makeDir then pcall(fs.makeDir, "/etc/AtlasOS") end
  if fs.write then
    fs.write(
      PATH,
      json.encode({ developer_mode = t.developer_mode and true or false })
    )
  end
end

function atlassettings.developer_mode()
  return read().developer_mode
end

function atlassettings.set_developer_mode(on)
  local t = read()
  t.developer_mode = not not on
  atlassettings.save(t)
  return t.developer_mode
end

function atlassettings.toggle_developer_mode()
  local t = read()
  t.developer_mode = not t.developer_mode
  atlassettings.save(t)
  return t.developer_mode
end

return atlassettings
