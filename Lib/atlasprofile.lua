--[[
  Display name / username under /etc/AtlasOS/profile.json (setup wizard + prompt).
]]

local json = require("json")
local PATH = "/etc/AtlasOS/profile.json"

local function parse_raw(raw)
	if type(raw) ~= "string" or raw == "" then
		return { username = "user" }
	end
	local ok, data = pcall(json.decode, raw)
	if not ok or type(data) ~= "table" then
		return { username = "user" }
	end
	local u = data.username
	if type(u) ~= "string" or u == "" then u = "user" end
	return { username = u:sub(1, 32) }
end

local function read()
	local raw = fs.read and fs.read(PATH) or ""
	return parse_raw(raw)
end

local M = {}

function M.load()
	return read()
end

function M.display_name()
	return read().username
end

--- Trimmed printable ASCII / basic Latin; 1..32 chars; default "user".
function M.save_username(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	name = name:gsub("[\000-\031]", "")
	if name == "" then name = "user" end
	name = name:sub(1, 32)
	local t = read()
	t.username = name
	if fs.makeDir then pcall(fs.makeDir, "/etc/AtlasOS") end
	if fs.write then
		fs.write(PATH, json.encode({ username = name }))
	end
	return name
end

return M
