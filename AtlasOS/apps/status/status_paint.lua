--[[ Status detail window (optional). Core host · cwd is on the taskbar; pin this app for the full panel. ]]
local CACHE = "__AtlasOS_status_paint_factory"
local factory = _G[CACHE]
if not factory then
	factory = function(ctx)
		local UI = ctx.UI
		local window = ctx.window
		local deskutil = ctx.deskutil
		local appkit = dofile("/home/lib/appkit.lua")
		local draw = dofile("/home/lib/atlas_draw.lua")
		local atlas_color = dofile("/home/lib/atlas_color.lua")

		local CW = draw.cell_w
		local CH = draw.cell_h
		local function C(token) return atlas_color.resolve(token) end

		-- Module-level persistent state for gui components
		local _st_mgr, _st_key, _st_win, _st_y0, _st_texts = nil, nil, nil, 0, {}

		local function build_status_gui()
			local P = gui.Panel
			local T = gui.Text
			local mgr = gui.GUIManager.new()
			mgr:setBackgroundColor(0, 0, 0, 0)

			_st_texts = {}
			for i = 1, 9 do
				_st_texts[i] = T.new(0, 0, "")
				_st_texts[i]:setScale(1)
				mgr:addComponent(_st_texts[i])
			end

			mgr:setLayoutCallback(function(m, _pw, _ph)
				local win = _st_win
				if not win then return end
				local y0 = _st_y0
				local cx = win:client_x()
				local cy = win:client_y() + y0

				for i = 1, 9 do
					_st_texts[i]:setPosition(cx * CW, (cy + i - 1) * CH)
				end
			end)

			_st_mgr = mgr
		end

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

			-- Set upvalues for layout callback
			_st_win = win
			_st_y0 = y0

			-- Rebuild if needed
			local st_key = win:client_w() .. ":" .. win:client_h() .. ":" .. y0
			if _st_mgr == nil or _st_key ~= st_key then
				build_status_gui()
				_st_key = st_key
			end

			-- Update text content and colors
			local win_fg = win.client_fg
			local win_bg = win.client_bg
			local fg_r, fg_g, fg_b, fg_a = C(win_fg)
			local bg_r, bg_g, bg_b, bg_a = C(win_bg)

			for i = 1, 9 do
				local text = lines[i] or ""
				_st_texts[i]:setText(tostring(text))
				_st_texts[i]:setColor(fg_r, fg_g, fg_b, fg_a)
				_st_texts[i]:setBackgroundColor(bg_r, bg_g, bg_b, bg_a)
			end

			-- Render components
			_st_mgr:update(0)
			_st_mgr:draw()

			shell:paint_dropdown(win)
		end
	end
	_G[CACHE] = factory
end
return factory
