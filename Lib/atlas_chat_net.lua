--[[
  AtlasOS Chat — LuaMade net.* helpers (global channels).
  Docs: https://garretreichenbach.github.io/Logiscript/markdown/io/networking.html
]]

local json = require("json")

local M = {}

local function slug(s)
	s = tostring(s or ""):lower():gsub("[^%w%-_]", ""):sub(1, 20)
	if s == "" then s = "x" end
	return s
end

--- Password disambiguates two servers with the same display name (different net passwords).
local function server_key(name, password)
	local base = slug(name)
	local p = tostring(password or "")
	if p == "" then return base end
	local h = 0
	for i = 1, math.min(#p, 64) do
		h = (h * 31 + p:byte(i)) % 999983
	end
	return base .. "-" .. tostring(h)
end

--- Global channel name for AtlasOS chat (server + channel slug + optional pass mix-in).
function M.channel_name(server_display, password, channel_display)
	local sk = server_key(server_display, password)
	local ck = slug(channel_display)
	return "aoc.chat.v1." .. sk .. "." .. ck
end

function M.msg_content(m)
	if not m then return nil end
	if m.getContent then
		local ok, c = pcall(m.getContent, m)
		if ok and c ~= nil then return c end
	end
	if m.getData then
		local ok, c = pcall(m.getData, m)
		if ok and c ~= nil then return c end
	end
	return nil
end

function M.msg_sender(m)
	if not m then return "?" end
	if m.getSender then
		local ok, s = pcall(m.getSender, m)
		if ok and type(s) == "string" and s ~= "" then return s end
	end
	return "?"
end

function M.encode_chat(nick, text)
	return json.encode({
		v = 1,
		k = "chat",
		n = tostring(nick or "guest"):sub(1, 32),
		t = tostring(text or ""):sub(1, 500),
	})
end

function M.decode_chat(raw)
	if type(raw) ~= "string" or raw == "" then return nil end
	local ok, t = pcall(json.decode, raw)
	if not ok or type(t) ~= "table" or t.k ~= "chat" then return nil end
	return {
		nick = type(t.n) == "string" and t.n or "?",
		text = type(t.t) == "string" and t.t or "",
	}
end

return M
