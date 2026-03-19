--[[
  AtlasOS settings persisted under /etc/AtlasOS/settings.txt
  developer_mode — when false, Files hides /home/AtlasOS (users use /home/apps).
]]

local PATH = "/etc/AtlasOS/settings.txt"

local function parse_raw(raw)
  local dev = false
  if type(raw) == "string" then
    if raw:match("developer_mode%s*=%s*1")
      or raw:lower():match("developer_mode%s*=%s*true") then
      dev = true
    end
  end
  return { developer_mode = dev }
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
      "developer_mode=" .. (t.developer_mode and "1" or "0") .. "\n"
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
