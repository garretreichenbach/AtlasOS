--[[
  Empty /home/.trash using LuaMade fs (fs.delete / fs.remove) with recursive dirs.
]]

local paths = dofile("/home/lib/desktop_paths.lua")

local M = {}

local function delete_one(path)
	path = paths.normalize(path)
	local isDir = false
	if fs.isDir then pcall(function() isDir = fs.isDir(path) end) end
	if isDir then
		local ok, names = pcall(fs.list, path)
		if ok and names then
			for _, n in ipairs(names) do
				delete_one(paths.join(path, n))
			end
		end
	end
	if fs.delete then
		pcall(fs.delete, path)
	elseif fs.remove then
		pcall(fs.remove, path)
	end
end

--- Remove all children of the trash folder (folder itself is kept).
function M.empty_trash(root)
	root = paths.normalize(root or paths.TRASH_DIR)
	pcall(fs.makeDir, root)
	local ok, names = pcall(fs.list, root)
	if not ok or not names then return false end
	for _, n in ipairs(names) do
		delete_one(paths.join(root, n))
	end
	return true
end

return M
