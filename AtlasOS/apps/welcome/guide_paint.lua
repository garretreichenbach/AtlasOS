--[[ Guide window (README + tips) — paint_module for appinfo; same pattern as explorer/editor. ]]
local CACHE = "__AtlasOS_guide_paint_factory"
local factory = _G[CACHE]
if not factory then
	factory = function(ctx)
		local UI = ctx.UI
		local window = ctx.window
		local widgets = ctx.widgets
		local draw = ctx.draw
		local atlastheme = ctx.atlastheme
		local VERSION = ctx.VERSION
		local deskutil = ctx.deskutil
		local appkit = dofile("/home/lib/appkit.lua")
		local shell = appkit.shell({
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
		shell:set_menubar({
			{
				label = "View",
				items = {
					{ label = "Top", id = "guide:top" },
					{ label = "Bottom", id = "guide:bottom" },
					{ label = "Refresh", id = "guide:refresh" },
				},
			},
		})
		shell:set_toolbar({
			{ label = "Top", id = "guide:top", w = 6 },
			{ label = "End", id = "guide:bottom", w = 6 },
			{ label = "Refresh", id = "guide:refresh", w = 10 },
		})

		return function(win)
			local t = atlastheme.load()
			local scale_line = "Canvas: "
				.. tostring(UI.W)
				.. "x"
				.. tostring(UI.H)
				.. "  cell px "
				.. tostring(draw.cell_w)
				.. "x"
				.. tostring(draw.cell_h)
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
				"Trash icon — Files in /home/.trash",
				"Taskbar — host · cwd between icons and Settings",
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

			shell:attach(win)
			shell:paint_decorations(win)
			local y0 = shell:content_row()
			local rows_avail = win:client_h() - y0
			if rows_avail < 1 then
				shell:paint_dropdown(win)
				return
			end
			UI._guide_first_line = UI._guide_first_line or 1
			if UI._guide_scroll_end then
				UI._guide_first_line = widgets.log_tail_index(lines, rows_avail)
				UI._guide_scroll_end = nil
			end
			widgets.log_paint(win, lines, UI._guide_first_line, y0)
			shell:paint_dropdown(win)
		end
	end
	_G[CACHE] = factory
end
return factory
