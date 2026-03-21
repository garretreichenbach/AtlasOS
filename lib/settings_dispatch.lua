--[[
  Settings window command tags (theme, dev mode, nav, layout). Keeps UI.settings_dispatch thin.
]]

local M = {}

function M.dispatch(ctx, tag)
	if not tag then return end
	local UI = ctx.UI
	local atlastheme = ctx.atlastheme
	local startmenu = ctx.startmenu
	local paths = ctx.paths
	if tag:sub(1, 4) == "cat:" then
		UI._settings_cat = tag:sub(5)
		return
	end
	if tag == "theme:light" then
		pcall(atlastheme.save, "light")
		M.reload_desktop(ctx)
	elseif tag == "theme:dark" then
		pcall(atlastheme.save, "dark")
		M.reload_desktop(ctx)
	elseif tag == "dev:toggle" then
		UI.toggle_developer_mode()
		if paths.is_AtlasOS_tree(paths.normalize(UI.files_dir or "")) then
			UI.files_dir = "/home"
		end
	elseif tag == "nav:apps" then
		UI.files_set_dir("/home/apps")
		UI.focus_window_by_title("Files")
	elseif tag == "cmd:reload_apps" then
		startmenu.refresh_packages()
		UI.invalidate_packages()
	elseif tag == "cmd:save_layout" then
		UI.layout_save()
		_G.AtlasOS_log = _G.AtlasOS_log or {}
		_G.AtlasOS_log[#_G.AtlasOS_log + 1] = "[Settings] Layout saved."
	end
end

function M.reload_desktop(ctx)
	local UI = ctx.UI
	local window = ctx.window
	UI.desk = nil
	UI._canvas_key = nil
	UI.build_desktop()
	if UI.desk and UI.desk._windows then
		for _, w in ipairs(UI.desk._windows) do
			if w.title == "Settings" then
				window.Desktop.bring_to_front(UI.desk, w)
				window.Desktop.set_focus(UI.desk, w)
				break
			end
		end
	end
end

return M
