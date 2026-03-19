--[[ Console window (log tail) — paint_module for appinfo. ]]
local CACHE = "__AtlasOS_console_paint_factory"
local factory = _G[CACHE]
if not factory then
	factory = function(ctx)
		local UI = ctx.UI
		local window = ctx.window
		local widgets = ctx.widgets
		local appkit = dofile("/home/lib/appkit.lua")
		local shell = appkit.shell({
			on_command = function(id)
				if id == "console:clear" then
					_G.AtlasOS_log = {}
				end
				UI.redraw()
			end,
		})
		shell:set_menubar({
			{ label = "Edit", items = { { label = "Clear log", id = "console:clear" } } },
		})
		shell:set_toolbar({ { label = "Clear", id = "console:clear", w = 8 } })

		return function(win)
			shell:attach(win)
			shell:paint_decorations(win)
			local y0 = shell:content_row()
			local log = _G.AtlasOS_log or {}
			local rows = math.max(1, win:client_h() - y0)
			local start = widgets.log_tail_index(log, rows)
			widgets.log_paint(win, log, start, y0)
			shell:paint_dropdown(win)
		end
	end
	_G[CACHE] = factory
end
return factory
