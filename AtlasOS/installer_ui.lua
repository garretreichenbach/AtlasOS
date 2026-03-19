--[[
  First-run graphical installer: loading bar, then username + theme setup.
  Writes /etc/AtlasOS/setup_complete then chains to boot_desktop.lua.
]]

local atlasgfx = dofile("/home/lib/atlasgfx.lua")
local input = dofile("/home/lib/input.lua")
local atlastheme = dofile("/home/lib/atlastheme.lua")
local atlasprofile = dofile("/home/lib/atlasprofile.lua")
local atlasinstall = dofile("/home/lib/atlasinstall.lua")

local GFX_CONF_PATH = "/etc/AtlasOS/gfx.conf"

local function read_gfx_conf()
	local conf = { cell_scale = 1.5 }
	if not fs or not fs.read then return conf end
	local ok, raw = pcall(fs.read, GFX_CONF_PATH)
	if not ok or not raw or tostring(raw):gsub("%s", "") == "" then return conf end
	for line in tostring(raw):gmatch("[^\r\n]+") do
		local n = line:match("^%s*cell_scale%s*=%s*([0-9.]+)%s*$")
			or line:match("^%s*scale%s*=%s*([0-9.]+)%s*$")
		if n then
			n = tonumber(n)
			if n then conf.cell_scale = math.max(0.5, math.min(4, n)) end
		end
	end
	return conf
end

local TARGET_W, TARGET_H = 120, 72

local function now_ms()
	if util and util.now then
		local ok, v = pcall(util.now)
		if ok and type(v) == "number" then return v end
	end
	if console and console.getTime then return console.getTime() end
	return 0
end

local state = {
	phase = "loading",
	progress = 0,
	load_plan = nil,
	install_co = nil,
	load_title = "",
	load_hint = "",
	load_detail = "",
	missing = {},
	username = "user",
	theme = "light",
	focus = 1,
	blink_t = 0,
}

local W, H = TARGET_W, TARGET_H

local function sync_canvas()
	atlasgfx.init(read_gfx_conf())
	if atlasgfx.is_bitmap() and gfx and type(gfx.setCanvasSize) == "function" then
		atlasgfx.set_canvas_from_cells(TARGET_W, TARGET_H)
	end
	if gfx and type(gfx.setSize) == "function" and not atlasgfx.is_bitmap() then
		pcall(gfx.setSize, TARGET_W, TARGET_H)
	end
	local cw, ch = atlasgfx.canvas_cells()
	if cw and ch then W, H = cw, ch end
	local pw, ph = atlasgfx.canvas_pixels_for_input()
	if pw and ph then input.set_canvas_pixels(pw, ph) end
end

local function draw_center_text(row, msg, fg, bg)
	msg = tostring(msg or "")
	local pad = math.max(1, math.floor((W - #msg) / 2))
	atlasgfx.setColor(fg, bg)
	atlasgfx.text(pad, row, msg)
end

local function draw_loading()
	atlasgfx.begin_frame()
	atlasgfx.setColor("bright_white", "blue")
	atlasgfx.fillRect(1, 1, W, H, " ")
	draw_center_text(3, "AtlasOS", "bright_yellow", "blue")
	draw_center_text(5, state.load_title ~= "" and state.load_title or "Working…", "bright_white", "blue")
	local det = state.load_detail or ""
	if #det > W - 4 then
		det = det:sub(1, math.max(1, W - 7)) .. "…"
	end
	atlasgfx.setColor("bright_cyan", "blue")
	atlasgfx.text(2, 6, det)
	local hint = state.load_hint or ""
	if hint ~= "" and H >= 10 then
		if #hint > W - 4 then
			hint = hint:sub(1, math.max(1, W - 7)) .. "…"
		end
		atlasgfx.setColor("bright_black", "blue")
		atlasgfx.text(2, 7, hint)
	end
	local bar_row = H >= 12 and 9 or 8
	local bar_x, bar_y, bar_w = 8, bar_row, W - 16
	atlasgfx.setColor("bright_black", "bright_white")
	atlasgfx.fillRect(bar_x, bar_y, bar_w, 1, " ")
	local inner = math.max(0, math.floor(bar_w * state.progress))
	if inner > 0 then
		atlasgfx.setColor("black", "bright_green")
		atlasgfx.fillRect(bar_x, bar_y, inner, 1, " ")
	end
	atlasgfx.setColor("bright_white", "blue")
	local pct = math.floor(state.progress * 100 + 0.5)
	draw_center_text(bar_row + 3, tostring(pct) .. "%", "bright_cyan", "blue")
	atlasgfx.end_frame()
end

local function draw_error()
	atlasgfx.begin_frame()
	atlasgfx.setColor("bright_white", "red")
	atlasgfx.fillRect(1, 1, W, H, " ")
	draw_center_text(3, "AtlasOS — installation failed", "bright_yellow", "red")
	atlasgfx.setColor("bright_white", "red")
	local row = 6
	for _, p in ipairs(state.missing) do
		if row < H - 4 then
			atlasgfx.text(4, row, p:sub(1, math.max(1, W - 8)))
			row = row + 1
		end
	end
	draw_center_text(H - 4, "Mount repo as /disk/AtlasOS + /disk/Lib or copy into /home/", "bright_white", "red")
	draw_center_text(H - 2, "Press any key to exit…", "bright_yellow", "red")
	atlasgfx.end_frame()
end

local function draw_setup()
	atlasgfx.begin_frame()
	local bg = state.theme == "dark" and "black" or "white"
	local fg = state.theme == "dark" and "bright_white" or "black"
	atlasgfx.setColor(fg, bg)
	atlasgfx.fillRect(1, 1, W, H, " ")
	draw_center_text(2, "Welcome to AtlasOS", "bright_cyan", bg)
	draw_center_text(4, "Choose your name and theme", fg, bg)

	atlasgfx.setColor(fg, bg)
	atlasgfx.text(4, 7, "Username" .. (state.focus == 1 and " ◄" or ""))
	local show = state.username
	if state.focus == 1 then
		local blink = (math.floor(state.blink_t / 400) % 2) == 0
		show = show .. (blink and "_" or " ")
	else
		show = show .. " "
	end
	atlasgfx.setColor("black", "bright_white")
	atlasgfx.text(4, 8, show:sub(1, math.max(1, W - 10)))

	atlasgfx.setColor(fg, bg)
	atlasgfx.text(4, 11, "Theme" .. (state.focus == 2 and " ◄" or ""))
	local function paint_theme_chip(col, label, which)
		local on = (state.theme == which)
		local sel = (state.focus == 2)
		if on then
			atlasgfx.setColor("black", sel and "bright_cyan" or "bright_green")
		else
			atlasgfx.setColor(fg, sel and "bright_black" or bg)
		end
		atlasgfx.text(col, 12, "[ " .. label .. " ]")
	end
	paint_theme_chip(6, "Light", "light")
	paint_theme_chip(24, "Dark", "dark")

	if state.focus == 3 then
		atlasgfx.setColor("black", "bright_yellow")
	else
		atlasgfx.setColor(fg, bg)
	end
	draw_center_text(
		15,
		"[  Continue — Enter  ]",
		state.focus == 3 and "black" or fg,
		state.focus == 3 and "bright_yellow" or bg
	)

	local hint_fg = state.theme == "dark" and "bright_cyan" or "bright_black"
	atlasgfx.setColor(hint_fg, bg)
	atlasgfx.text(3, H - 1, "Tab next field  Enter: save on Continue  Typing: name")
	atlasgfx.end_frame()
end

local function redraw()
	if state.phase == "loading" then
		draw_loading()
	elseif state.phase == "error" then
		draw_error()
	else
		draw_setup()
	end
end

local function finish_setup()
	atlasprofile.save_username(state.username)
	atlastheme.save(state.theme)
	pcall(fs.makeDir, "/etc/AtlasOS")
	pcall(fs.write, "/etc/AtlasOS/setup_complete", "v1\n")
end

local function is_enter(k)
	return k == 28 or k == 257
end

local function is_tab(k)
	return k == 15
end

local function is_back(k)
	return k == 259 or k == 14
end

local function is_left(k)
	return k == 263 or k == 203
end

local function is_right(k)
	return k == 262 or k == 205 or k == 204
end

local function handle_key(e)
	if e.type ~= "key" or e.down ~= true then return end

	local key = tonumber(e.key) or 0
	local ch = e.char

	if state.phase == "setup" or state.phase == "error" then
		input.cancelKeyEvent(e)
	end

	if state.phase == "error" then
		print("AtlasOS: fix missing files (see on-screen list) then reboot.")
		return "quit"
	end

	if state.phase == "loading" then
		return nil
	end

	-- setup
	if is_tab(key) then
		state.focus = (state.focus % 3) + 1
		return nil
	end

	if state.focus == 1 then
		if is_back(key) then
			state.username = (state.username:sub(1, -2)) or ""
			if state.username == "" then state.username = "" end
		elseif type(ch) == "string" and ch ~= "" and not e.ctrl then
			local b = ch:byte(1)
			if b and b >= 32 and b < 127 and #state.username < 32 then
				state.username = state.username .. ch
			end
		end
	elseif state.focus == 2 then
		if is_left(key) or is_right(key) then
			state.theme = (state.theme == "light") and "dark" or "light"
		elseif is_enter(key) then
			state.theme = (state.theme == "light") and "dark" or "light"
		end
	elseif state.focus == 3 and is_enter(key) then
		finish_setup()
		return "boot"
	end

	return nil
end

local function handle_mouse(e)
	if state.phase ~= "setup" or e.type ~= "mouse" or e.button ~= "left" or e.pressed ~= true then
		return nil
	end
	local cx, cy
	if atlasgfx.is_bitmap() and e.insideCanvas and type(e.uiX) == "number" and type(e.uiY) == "number" then
		cx, cy = atlasgfx.pixel_to_cell_rel(e.uiX, e.uiY)
	else
		cx, cy = input.pixel_to_cell(e.x, e.y, W, H)
	end
	cx, cy = math.max(1, math.min(W, cx)), math.max(1, math.min(H, cy))
	if cy >= 12 and cy <= 13 then
		if cx >= 6 and cx <= 18 then
			state.theme = "light"
			state.focus = 2
		elseif cx >= 22 and cx <= 34 then
			state.theme = "dark"
			state.focus = 2
		end
	elseif cy >= 14 and cy <= 16 then
		state.focus = 3
	elseif cy >= 7 and cy <= 9 then
		state.focus = 1
	end
	if state.focus == 3 and cy >= 14 and cy <= 16 then
		finish_setup()
		return "boot"
	end
	return nil
end

sync_canvas()

input.setEnabled(true)

local out = nil
while not out do
	local events = input.poll_all()
	if #events == 0 then
		local one = input.waitFor(32)
		if one then events = { one } end
	end

	local t = now_ms()
	state.blink_t = t

	if state.phase == "loading" then
		if not state.install_co then
			local cli = args and args[1] and tostring(args[1])
			state.load_plan = atlasinstall.build_plan(cli)
			state.load_title = state.load_plan.title or ""
			state.load_hint = state.load_plan.hint or ""
			state.load_detail = ""
			state.progress = 0
			state.install_co = atlasinstall.install_coroutine(state.load_plan, 5)
		end
		local co = state.install_co
		if coroutine.status(co) ~= "dead" then
			local st, tick_ok, a, b = coroutine.resume(co)
			if not st then
				state.phase = "error"
				state.missing = { tostring(tick_ok) }
			elseif tick_ok == false then
				state.phase = "error"
				state.missing = { tostring(a) }
			elseif tick_ok == true then
				state.progress = tonumber(a) or state.progress
				state.load_detail = tostring(b or "")
			end
			-- Final resume after last yield: coroutine returns (no yield); tick_ok is nil.
		end
		if coroutine.status(co) == "dead" and state.phase == "loading" then
			state.phase = "setup"
			state.progress = 1
		end
	end

	for _, ev in ipairs(events) do
		if ev.type == "key" then
			out = handle_key(ev)
		elseif ev.type == "mouse" then
			out = handle_mouse(ev)
		end
	end

	redraw()
end

input.setEnabled(true)

if out == "boot" then
	dofile("/home/AtlasOS/boot_desktop.lua")
end
