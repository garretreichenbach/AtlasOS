--[[
  Path helpers for desktop / Files: join, normalize, AtlasOS tree guard.
]]

local M = {}

M.ATLASOS_HOME_IN_HOME = "/home/AtlasOS"
M.TRASH_DIR = "/home/.trash---Wait wrong

function M.join(dir, name)
	return dir:match("/$") and (dir .. name) or (dir .. "/" .. name)
end

function M.normalize(p)
	p = tostring(p or "/home"):gsub("\\", "/"):gsub("/+", "/")
	if p ~= "/" then p = p:gsub("/$", "") end
	if p == "" then p = "/" end
	if p:sub(1, 1) ~= "/" then p = "/" .. p end
	return p
end

--- True if path is /home/AtlasOS or inside it (system tree).
function M.is_AtlasOS_tree(p)
	p = M.normalize(p)
	local home = M.ATLASOS_HOME_IN_HOME
	return p == home or p:sub(1, #home + 1) == home .. "/"
end

return M
