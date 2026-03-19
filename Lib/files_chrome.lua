--[[
  Files / explorer appkit menubar + toolbar; optional “Empty trash” when cwd is TRASH_DIR.
]]

local M = {}

--- Update shell chrome only when `in_trash` changes so open menus are not cleared every frame.
function M.sync_files_shell(shell, in_trash)
	if shell._atlas_in_trash == in_trash then return end
	shell._atlas_in_trash = in_trash
	local file_items = {
		{ label = "Up", id = "files:up" },
		{ label = "Home", id = "files:home" },
		{ label = "Apps folder", id = "files:apps" },
		{ label = "Refresh", id = "files:refresh" },
	}
	if in_trash then
		file_items[#file_items + 1] = { label = "Empty trash", id = "files:empty_trash" }
	end
	shell:set_menubar({ { label = "File", items = file_items } })
	local tb = {
		{ label = "Up", id = "files:up", w = 6 },
		{ label = "Home", id = "files:home", w = 8 },
		{ label = "Apps", id = "files:apps", w = 8 },
		{ label = "Refresh", id = "files:refresh", w = 10 },
	}
	if in_trash then
		tb[#tb + 1] = { label = "Empty", id = "files:empty_trash", w = 8 }
	end
	shell:set_toolbar(tb)
end

return M
