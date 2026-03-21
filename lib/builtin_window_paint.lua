--[[
  Built-in AtlasOS window chrome + content painters (Guide, Status, Files fallback, etc.).
  Loaded by ui.lua with a dependency table; keeps desktop shell free of per-window paint blocks.
]]

local M = {}

--- @param ctx { UI, window, widgets, draw, appkit, atlastheme, VERSION, paths, deskutil, startmenu }
function M.create(ctx)
	local UI = ctx.UI
	local window = ctx.window
	local widgets = ctx.widgets
	local draw = ctx.draw
	local appkit = ctx.appkit
	local atlastheme = ctx.atlastheme
	local VERSION = ctx.VERSION
	local paths = ctx.paths
	local deskutil = ctx.deskutil
	local startmenu = ctx.startmenu
	local files_chrome = dofile("/home/lib/files_chrome.lua")
	local trash_util = dofile("/home/lib/trash_util.lua")

	local files_fallback_shell, settings_fallback_shell

	local function get_files_fallback_shell()
		if not files_fallback_shell then
			files_fallback_shell = appkit.shell({
				on_command = function(id)
					if id == "files:empty_trash" then
						if trash_util.empty_trash() then
							_G.AtlasOS_log = _G.AtlasOS_log or {}
							_G.AtlasOS_log[#_G.AtlasOS_log + 1] = "[Trash] Emptied."
						end
						UI.redraw()
					elseif id == "files:up" then
						local d = UI.files_effective_dir()
						if d ~= "/" and d ~= "" then
							local p = d:match("^(.+)/[^/]+$") or "/"
							UI.files_set_dir(p)
						end
					elseif id == "files:home" then
						UI.files_set_dir("/home")
					elseif id == "files:apps" then
						UI.files_set_dir("/home/apps")
					elseif id == "files:refresh" then
						UI.redraw()
					end
				end,
			})
			files_chrome.sync_files_shell(files_fallback_shell, false)
		end
		return files_fallback_shell
	end

	local function get_settings_fallback_shell()
		if not settings_fallback_shell then
			settings_fallback_shell = appkit.shell({
				on_command = function(id)
					UI.settings_dispatch(id)
				end,
			})
			settings_fallback_shell:set_menubar({
				{
					label = "Actions",
					items = {
						{ label = "Reload apps", id = "cmd:reload_apps" },
						{ label = "Save layout", id = "cmd:save_layout" },
					},
				},
			})
			settings_fallback_shell:set_toolbar({
				{ label = "Reload", id = "cmd:reload_apps", w = 10 },
				{ label = "Save", id = "cmd:save_layout", w = 8 },
			})
		end
		return settings_fallback_shell
	end

	local function paint_welcome_fallback(win)
		window.draw_text_lines(win, {
			"Guide",
			"Install: /home/AtlasOS/apps/welcome/guide_paint.lua",
			"",
		}, 1)
	end

	local function paint_status_fallback(win)
		window.draw_text_lines(win, {
			"Status",
			"Install: /home/AtlasOS/apps/status/status_paint.lua",
			"",
		}, 1)
	end

	local function get_welcome_painter()
		if UI._welcome_painter then return UI._welcome_painter end
		local m = startmenu.registry.welcome
		if m and m.package_dir and m.paint_module then
			local modpath = m.package_dir .. "/" .. m.paint_module
			local ok, factory = pcall(dofile, modpath)
			if ok and type(factory) == "function" then
				local paint = factory({
					UI = UI,
					widgets = widgets,
					window = window,
					draw = draw,
					atlastheme = atlastheme,
					VERSION = VERSION,
					deskutil = deskutil,
				})
				if type(paint) == "function" then
					UI._welcome_painter = paint
					return paint
				end
			end
		end
		UI._welcome_painter = paint_welcome_fallback
		return UI._welcome_painter
	end

	local function paint_guide(win)
		get_welcome_painter()(win)
	end

	local function get_status_painter()
		if UI._status_painter then return UI._status_painter end
		local m = startmenu.registry.status
		if m and m.package_dir and m.paint_module then
			local modpath = m.package_dir .. "/" .. m.paint_module
			local ok, factory = pcall(dofile, modpath)
			if ok and type(factory) == "function" then
				local paint = factory({
					UI = UI,
					window = window,
					deskutil = deskutil,
				})
				if type(paint) == "function" then
					UI._status_painter = paint
					return paint
				end
			end
		end
		UI._status_painter = paint_status_fallback
		return UI._status_painter
	end

	local function paint_status(win)
		get_status_painter()(win)
	end

	local function paint_files_fallback(win)
		local dir = UI.files_effective_dir()
		if paths.normalize(UI.files_dir or "") ~= dir then
			UI.files_dir = dir
		end
		local list = {}
		if dir ~= "/" and dir ~= "" then
			list[#list + 1] = { text = "..", dir = true }
		end
		local ok, names = pcall(fs.list, dir)
		if ok and names then
			for _, name in ipairs(names) do
				local full = paths.join(dir, name)
				local isDir = false
				if fs.isDir then pcall(function() isDir = fs.isDir(full) end) end
				if UI.files_show_list_entry(dir, name, isDir) then
					list[#list + 1] = { text = name, dir = isDir }
				end
			end
		else
			list[#list + 1] = "(cannot list)"
		end

		local sh = get_files_fallback_shell()
		files_chrome.sync_files_shell(sh, paths.normalize(dir) == paths.normalize(paths.TRASH_DIR))
		sh:attach(win)
		sh:paint_decorations(win)
		local y0 = sh:content_row()
		local ch = win:client_h()
		if y0 + 2 > ch then
			sh:paint_dropdown(win)
			return
		end
		window.draw_text_line(win, 0, y0, widgets.path_display(dir, win:client_w() - 2))
		widgets.hrule(win, y0 + 1, "-")
		local list_h = math.max(0, ch - (y0 + 2))
		widgets.list_box(win, list, 1, list_h, y0 + 2)
		sh:paint_dropdown(win)
	end

	local function get_files_painter()
		if UI._files_painter then return UI._files_painter end
		local m = startmenu.registry.files
		if m and m.package_dir and m.paint_module then
			local modpath = m.package_dir .. "/" .. m.paint_module
			local ok, factory = pcall(dofile, modpath)
			if ok and type(factory) == "function" then
				local paint = factory({ UI = UI, widgets = widgets, window = window })
				if type(paint) == "function" then
					UI._files_painter = paint
					return paint
				end
			end
		end
		UI._files_painter = paint_files_fallback
		return UI._files_painter
	end

	local function paint_files(win)
		get_files_painter()(win)
	end

	local function paint_settings_fallback(win)
		local lines = {
			"Settings",
			"Install: /home/AtlasOS/apps/settings/settings_ui.lua",
			"theme  devmode  save_layout",
		}
		local sh = get_settings_fallback_shell()
		sh:attach(win)
		sh:paint_decorations(win)
		local y0 = sh:content_row()
		for i = 1, #lines do
			window.draw_text_line(win, 0, y0 + i - 1, lines[i])
		end
		sh:paint_dropdown(win)
	end

	local function get_settings_painter()
		if UI._settings_painter then return UI._settings_painter end
		local m = startmenu.registry.settings
		if m and m.package_dir and m.paint_module then
			local modpath = m.package_dir .. "/" .. m.paint_module
			local ok, factory = pcall(dofile, modpath)
			if ok and type(factory) == "function" then
				local paint = factory({
					UI = UI,
					widgets = widgets,
					window = window,
					atlastheme = atlastheme,
					VERSION = VERSION,
				})
				if type(paint) == "function" then
					UI._settings_painter = paint
					return paint
				end
			end
		end
		UI._settings_painter = paint_settings_fallback
		return UI._settings_painter
	end

	local function paint_settings(win)
		get_settings_painter()(win)
	end

	local function paint_console_fallback(win)
		window.draw_text_lines(win, {
			"Console",
			"Install: /home/AtlasOS/apps/console/console_paint.lua",
			"",
		}, 1)
	end

	local function get_console_painter()
		if UI._console_painter then return UI._console_painter end
		local m = startmenu.registry.console
		if m and m.package_dir and m.paint_module then
			local modpath = m.package_dir .. "/" .. m.paint_module
			local ok, factory = pcall(dofile, modpath)
			if ok and type(factory) == "function" then
				local paint = factory({
					UI = UI,
					widgets = widgets,
					window = window,
				})
				if type(paint) == "function" then
					UI._console_painter = paint
					return paint
				end
			end
		end
		UI._console_painter = paint_console_fallback
		return UI._console_painter
	end

	local function paint_console(win)
		get_console_painter()(win)
	end

	local function get_editor_painter()
		if UI._editor_painter then return UI._editor_painter end
		local m = startmenu.registry.editor
		if m and m.package_dir and m.paint_module then
			local modpath = m.package_dir .. "/" .. m.paint_module
			local ok, factory = pcall(dofile, modpath)
			if ok and type(factory) == "function" then
				local paint = factory({ UI = UI, widgets = widgets, window = window })
				if type(paint) == "function" then
					UI._editor_painter = paint
					return paint
				end
			end
		end
		UI._editor_painter = function(win)
			window.draw_text_lines(win, { "(Editor — install /home/AtlasOS/apps/editor)", "" }, 1)
		end
		return UI._editor_painter
	end

	local function paint_editor(win)
		get_editor_painter()(win)
	end

	--- Legacy saved layouts may still have a "Trash" window; reuse Files explorer UI.
	local function paint_trash(win)
		pcall(fs.makeDir, paths.TRASH_DIR)
		local saved = UI.files_dir
		UI.files_dir = paths.TRASH_DIR
		paint_files(win)
		UI.files_dir = saved
	end

	return {
		paint_window_content = {
			Guide = paint_guide,
			Welcome = paint_guide,
			Help = paint_guide,
			Status = paint_status,
			Files = paint_files,
			Settings = paint_settings,
			Console = paint_console,
			Trash = paint_trash,
			Editor = paint_editor,
		},
	}
end

return M
