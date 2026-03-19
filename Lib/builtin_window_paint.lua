--[[
  Built-in AtlasOS window chrome + content painters (Guide, Status, Files fallback, etc.).
  Loaded by ui.lua with a dependency table; keeps desktop shell free of per-window paint blocks.
]]

local M = {}

--- @param ctx { UI, window, widgets, atlasgfx, appkit, atlastheme, VERSION, paths, deskutil, startmenu }
function M.create(ctx)
	local UI = ctx.UI
	local window = ctx.window
	local widgets = ctx.widgets
	local atlasgfx = ctx.atlasgfx
	local appkit = ctx.appkit
	local atlastheme = ctx.atlastheme
	local VERSION = ctx.VERSION
	local paths = ctx.paths
	local deskutil = ctx.deskutil
	local startmenu = ctx.startmenu

	local guide_shell, status_shell, console_shell, trash_shell, files_fallback_shell, settings_fallback_shell

	local function get_guide_shell()
		if not guide_shell then
			guide_shell = appkit.shell({
				on_command = function(id)
					if id == "guide:top" then
						UI._guide_first_line = 1
					elseif id == "guide:refresh" then
						UI._guide_first_line = 1
					elseif id == "guide:bottom" then
						UI._guide_scroll_end = true
					end
					UI.redraw()
				end,
			})
			guide_shell:set_menubar({
				{
					label = "View",
					items = {
						{ label = "Top", id = "guide:top" },
						{ label = "Bottom", id = "guide:bottom" },
						{ label = "Refresh", id = "guide:refresh" },
					},
				},
			})
			guide_shell:set_toolbar({
				{ label = "Top", id = "guide:top", w = 6 },
				{ label = "End", id = "guide:bottom", w = 6 },
				{ label = "Refresh", id = "guide:refresh", w = 10 },
			})
		end
		return guide_shell
	end

	local function get_status_shell()
		if not status_shell then
			status_shell = appkit.shell({
				on_command = function(id)
					if id == "status:refresh" then UI.redraw() end
				end,
			})
			status_shell:set_menubar({
				{ label = "View", items = { { label = "Refresh", id = "status:refresh" } } },
			})
			status_shell:set_toolbar({ { label = "Refresh", id = "status:refresh", w = 10 } })
		end
		return status_shell
	end

	local function get_console_shell()
		if not console_shell then
			console_shell = appkit.shell({
				on_command = function(id)
					if id == "console:clear" then
						_G.AtlasOS_log = {}
					end
					UI.redraw()
				end,
			})
			console_shell:set_menubar({
				{ label = "Edit", items = { { label = "Clear log", id = "console:clear" } } },
			})
			console_shell:set_toolbar({ { label = "Clear", id = "console:clear", w = 8 } })
		end
		return console_shell
	end

	local function get_trash_shell()
		if not trash_shell then
			trash_shell = appkit.shell({
				on_command = function(id)
					if id == "trash:refresh" then UI.redraw() end
				end,
			})
			trash_shell:set_menubar({
				{ label = "File", items = { { label = "Refresh", id = "trash:refresh" } } },
			})
			trash_shell:set_toolbar({ { label = "Refresh", id = "trash:refresh", w = 10 } })
		end
		return trash_shell
	end

	local function get_files_fallback_shell()
		if not files_fallback_shell then
			files_fallback_shell = appkit.shell({
				on_command = function(id)
					if id == "files:up" then
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
			files_fallback_shell:set_menubar({
				{
					label = "File",
					items = {
						{ label = "Up", id = "files:up" },
						{ label = "Home", id = "files:home" },
						{ label = "Apps folder", id = "files:apps" },
						{ label = "Refresh", id = "files:refresh" },
					},
				},
			})
			files_fallback_shell:set_toolbar({
				{ label = "Up", id = "files:up", w = 6 },
				{ label = "Home", id = "files:home", w = 8 },
				{ label = "Apps", id = "files:apps", w = 8 },
				{ label = "Refresh", id = "files:refresh", w = 10 },
			})
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

	local function paint_guide(win)
		local t = atlastheme.load()
		local scale_line = "Canvas: "
			.. tostring(UI.W)
			.. "x"
			.. tostring(UI.H)
			.. "  cell px "
			.. tostring(atlasgfx.cell_w)
			.. "x"
			.. tostring(atlasgfx.cell_h)
		local lines = {
			"--- System ---",
			"AtlasOS " .. VERSION .. " (Custom OS for LuaMade Computers)",
			scale_line,
			"Theme: " .. t.mode,
			"Host: " .. deskutil.hostname(),
			"",
			"--- Quick tips ---",
			"start  — Start menu",
			"tasknext / go — taskbar pins",
			"Title: _ min  ^ max  x close  drag title",
			"Tab — next window  |  minimized row above taskbar",
			"pin / unpin  ·  save_layout",
			"",
		}
		local raw = fs.read("/home/AtlasOS/README.txt")
		if not raw or raw == "" then
			raw = "No README at /home/AtlasOS/README.txt — run `help` in console for commands."
		end
		lines[#lines + 1] = "--- User guide (README) ---"
		for line in (raw .. ""):gmatch("[^\r\n]+") do
			lines[#lines + 1] = line
		end

		local sh = get_guide_shell()
		sh:attach(win)
		sh:paint_decorations(win)
		local y0 = sh:content_row()
		local rows_avail = win:client_h() - y0
		if rows_avail < 1 then
			sh:paint_dropdown(win)
			return
		end
		UI._guide_first_line = UI._guide_first_line or 1
		if UI._guide_scroll_end then
			UI._guide_first_line = widgets.log_tail_index(lines, rows_avail)
			UI._guide_scroll_end = nil
		end
		widgets.log_paint(win, lines, UI._guide_first_line, y0)
		sh:paint_dropdown(win)
	end

	local function paint_status(win)
		local lines = {
			deskutil.clock_str(),
			"Host: " .. deskutil.hostname(),
			"",
			"Cwd: " .. (fs.getCurrentDir and fs.getCurrentDir() or "/home"),
			"",
			"Network: —",
			"Ship: —",
			"",
			"Input API: pending",
		}
		local sh = get_status_shell()
		sh:attach(win)
		sh:paint_decorations(win)
		local y0 = sh:content_row()
		for i = 1, #lines do
			window.draw_text_line(win, 0, y0 + i - 1, lines[i])
		end
		sh:paint_dropdown(win)
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

	local function paint_console(win)
		local sh = get_console_shell()
		sh:attach(win)
		sh:paint_decorations(win)
		local y0 = sh:content_row()
		local log = _G.AtlasOS_log or {}
		local rows = math.max(1, win:client_h() - y0)
		local start = widgets.log_tail_index(log, rows)
		widgets.log_paint(win, log, start, y0)
		sh:paint_dropdown(win)
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

	local function paint_trash(win)
		pcall(fs.makeDir, "/home/.trash")
		local dir = "/home/.trash"
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
				list[#list + 1] = { text = name, dir = isDir }
			end
		else
			list[#list + 1] = "(empty or n/a)"
		end

		local sh = get_trash_shell()
		sh:attach(win)
		sh:paint_decorations(win)
		local y0 = sh:content_row()
		local ch = win:client_h()
		if y0 + 2 > ch then
			sh:paint_dropdown(win)
			return
		end
		window.draw_text_line(win, 0, y0, widgets.path_display("Trash — " .. dir, win:client_w() - 2))
		widgets.hrule(win, y0 + 1, "-")
		local list_h = math.max(0, ch - (y0 + 2))
		widgets.list_box(win, list, 1, list_h, y0 + 2)
		sh:paint_dropdown(win)
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
