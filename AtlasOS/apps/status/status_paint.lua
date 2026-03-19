--[[ Status detail window (optional). Core host · cwd is on the taskbar; pin this app for the full panel. ]]
local CACHE = "__AtlasOS_status_paint_factory"
local factory = _G[CACHE]
if not factory then
	factory = function(ctx)
		local UI = ctx.UI
		local window = ctx.window
		local deskutil = ctx.deskutil
		local appkit = dofile("/home/lib/appkit.lua")
		local shell = appkit.shell({
			on_command = function(id)
				if id == "status:refresh" then UI.redraw() end
			end,
		})
		shell:set_menubar({
			{ label = "View", items = { { label = "Refresh", id = "status:refresh" } } },
		})
		shell:set_toolbar({ { label = "Refresh", id = "status:refresh", w = 10 } })

		return function(win)
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
			shell:attach(win)
			shell:paint_decorations(win)
			local y0 = shell:content_row()
			for i = 1, #lines do
				window.draw_text_line(win, 0, y0 + i - 1, lines[i])
			end
			shell:paint_dropdown(win)
		end
	end
	_G[CACHE] = factory
end
return factory
