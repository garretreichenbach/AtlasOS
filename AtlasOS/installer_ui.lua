--[[
  First-run graphical installer: loading bar, then username + theme setup.
  Phase 2: renders through gui_lib components. Event handling remains manual
  (no mgr:run()) so the install coroutine can be driven each frame.
  Writes /etc/AtlasOS/setup_complete then chains to boot_desktop.lua.
]]

local draw         = dofile("/home/lib/atlas_draw.lua")
local input        = dofile("/home/lib/input.lua")
local atlastheme   = dofile("/home/lib/atlastheme.lua")
local atlasprofile = dofile("/home/lib/atlasprofile.lua")
local atlasinstall = dofile("/home/lib/atlasinstall.lua")
local atlas_color  = dofile("/home/lib/atlas_color.lua")

-- gui_lib: LuaMade-provided global; component constructors live under gui_lib.*
local GUIManager = gui_lib.GUIManager
local Panel      = gui_lib.Panel
local Text       = gui_lib.Text

-- Shorthand: resolve an AtlasOS color token to (r, g, b, a) floats.
local C = atlas_color.resolve

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
	phase       = "loading",
	progress    = 0,
	load_plan   = nil,
	install_co  = nil,
	load_title  = "",
	load_hint   = "",
	load_detail = "",
	missing     = {},
	username    = "user",
	theme       = "light",
	focus       = 1,
	blink_t     = 0,
}

local W, H = TARGET_W, TARGET_H

-- Canvas: set logical size and enable viewport auto-scale.
draw.init()
draw.set_canvas_from_cells(TARGET_W, TARGET_H)
do
	local cw, ch = draw.canvas_cells()
	if cw and ch then W, H = cw, ch end
	local pw, ph = draw.canvas_pixels_for_input()
	if pw and ph then input.set_canvas_pixels(pw, ph) end
end

-- ── GUI build ────────────────────────────────────────────────────────────────

local mgr = GUIManager.new()
mgr:setBackgroundColor(0, 0, 0, 1)

-- Helper: panel with a solid background and no border.
local function bg_panel(color_name)
	local p = Panel.new(0, 0, 0, 0)
	p:setBackgroundColor(C(color_name))
	p:setBorderColor(0, 0, 0, 0)
	return p
end

-- Helper: text label with optional scale, color, and horizontal alignment.
local function make_label(content, scale, color_name, align)
	local t = Text.new(0, 0, content or "")
	t:setScale(scale or 1)
	t:setColor(C(color_name or "white"))
	if align then t:setLayout(0, 0, align, false) end
	return t
end

-- ── Loading screen ───────────────────────────────────────────────
local load_panel    = bg_panel("blue")

local load_title    = make_label("AtlasOS",  3, "bright_yellow", "center")
local load_sub      = make_label("",         2, "bright_white",  "center")
local load_det      = make_label("",         1, "bright_cyan")
local load_hint     = make_label("",         1, "bright_black")
local bar_bg        = bg_panel("bright_white")
local bar_fill      = bg_panel("bright_green")   -- sibling of bar_bg, drawn on top
local load_pct      = make_label("0%",       2, "bright_cyan",   "center")

for _, c in ipairs({ load_title, load_sub, load_det, load_hint,
                     bar_bg, bar_fill, load_pct }) do
	load_panel:addChild(c)
end

-- ── Error screen ─────────────────────────────────────────────────
local err_panel     = bg_panel("red")
err_panel:setVisible(false)

local err_title     = make_label("AtlasOS — installation failed", 2, "bright_yellow", "center")
local err_list      = make_label("", 1, "bright_white")
local err_footer    = make_label(
	"Mount repo as /disk/AtlasOS + /disk/lib or copy into /home/",
	1, "bright_white", "center")
local err_exit      = make_label("Press any key to exit…", 1, "bright_yellow", "center")

for _, c in ipairs({ err_title, err_list, err_footer, err_exit }) do
	err_panel:addChild(c)
end

-- ── Setup screen ─────────────────────────────────────────────────
local setup_panel   = bg_panel("white")
setup_panel:setVisible(false)

local setup_title   = make_label("Welcome to AtlasOS",        2, "bright_cyan",   "center")
local setup_sub     = make_label("Choose your name and theme", 1, "black",         "center")
local user_lbl      = make_label("Username",                   1, "black")
local user_field    = bg_panel("bright_white")       -- simulated text-input box
local user_val      = make_label("user",             1, "black")
user_field:addChild(user_val)
local theme_lbl     = make_label("Theme",            1, "black")
local light_chip    = bg_panel("bright_green")
local light_lbl     = make_label("[ Light ]",        1, "black",  "center")
light_chip:addChild(light_lbl)
local dark_chip     = bg_panel("bright_black")
local dark_lbl      = make_label("[ Dark ]",         1, "bright_white", "center")
dark_chip:addChild(dark_lbl)
local cont_chip     = bg_panel("bright_yellow")
local cont_lbl      = make_label("[  Continue — Enter  ]", 1, "black", "center")
cont_chip:addChild(cont_lbl)
local setup_hint    = make_label(
	"Tab: next field  Enter: save on Continue  Typing: name",
	1, "bright_black")

for _, c in ipairs({ setup_title, setup_sub, user_lbl, user_field,
                     theme_lbl, light_chip, dark_chip, cont_chip, setup_hint }) do
	setup_panel:addChild(c)
end

mgr:addComponent(load_panel)
mgr:addComponent(err_panel)
mgr:addComponent(setup_panel)

-- ── Layout callback (runs every frame before draw) ────────────────────────
mgr:setLayoutCallback(function(m, w, h)

	-- ── Loading ──────────────────────────────────────────────────
	load_panel:setPosition(0, 0)
	load_panel:setSize(w, h)

	load_title:setPosition(0, math.floor(h * 0.04))
	load_title:setSize(w, math.floor(h * 0.09))

	load_sub:setText(state.load_title ~= "" and state.load_title or "Working…")
	load_sub:setPosition(0, math.floor(h * 0.16))
	load_sub:setSize(w, math.floor(h * 0.08))

	local det = state.load_detail or ""
	if #det > W - 4 then det = det:sub(1, math.max(1, W - 7)) .. "…" end
	load_det:setText(det)
	load_det:setPosition(math.floor(w * 0.02), math.floor(h * 0.27))
	load_det:setSize(w - math.floor(w * 0.04), math.floor(h * 0.06))

	local hint = state.load_hint or ""
	if #hint > W - 4 then hint = hint:sub(1, math.max(1, W - 7)) .. "…" end
	load_hint:setText(hint)
	load_hint:setPosition(math.floor(w * 0.02), math.floor(h * 0.34))
	load_hint:setSize(w - math.floor(w * 0.04), math.floor(h * 0.06))

	local bx = math.floor(w * 0.07)
	local bw = w - math.floor(w * 0.14)
	local by = math.floor(h * 0.46)
	local bh = math.max(6, math.floor(h * 0.025))
	bar_bg:setPosition(bx, by)
	bar_bg:setSize(bw, bh)
	bar_fill:setPosition(bx, by)   -- sibling, same origin; clipped by fill width
	bar_fill:setSize(math.max(0, math.floor(bw * state.progress)), bh)

	local pct = math.floor(state.progress * 100 + 0.5)
	load_pct:setText(tostring(pct) .. "%")
	load_pct:setPosition(0, by + bh + math.floor(h * 0.05))
	load_pct:setSize(w, math.floor(h * 0.08))

	-- ── Error ────────────────────────────────────────────────────
	err_panel:setPosition(0, 0)
	err_panel:setSize(w, h)

	err_title:setPosition(0, math.floor(h * 0.04))
	err_title:setSize(w, math.floor(h * 0.08))

	local lines = {}
	for _, p in ipairs(state.missing or {}) do
		lines[#lines + 1] = p:sub(1, W - 8)
	end
	err_list:setText(table.concat(lines, "\n"))
	err_list:setLayout(w - math.floor(w * 0.08), math.floor(h * 0.55), "left", true)
	err_list:setPosition(math.floor(w * 0.04), math.floor(h * 0.16))
	err_list:setSize(w - math.floor(w * 0.08), math.floor(h * 0.55))

	err_footer:setPosition(0, h - math.floor(h * 0.14))
	err_footer:setSize(w, math.floor(h * 0.06))

	err_exit:setPosition(0, h - math.floor(h * 0.07))
	err_exit:setSize(w, math.floor(h * 0.06))

	-- ── Setup ────────────────────────────────────────────────────
	local bg_name = state.theme == "dark" and "black" or "white"
	local fg_name = state.theme == "dark" and "bright_white" or "black"
	local sel_col = state.focus == 2 and "bright_cyan" or "bright_green"

	setup_panel:setBackgroundColor(C(bg_name))
	setup_panel:setPosition(0, 0)
	setup_panel:setSize(w, h)

	setup_title:setPosition(0, math.floor(h * 0.02))
	setup_title:setSize(w, math.floor(h * 0.08))

	setup_sub:setColor(C(fg_name))
	setup_sub:setPosition(0, math.floor(h * 0.13))
	setup_sub:setSize(w, math.floor(h * 0.06))

	user_lbl:setText("Username" .. (state.focus == 1 and " ◄" or ""))
	user_lbl:setColor(C(fg_name))
	user_lbl:setPosition(math.floor(w * 0.04), math.floor(h * 0.23))
	user_lbl:setSize(w, math.floor(h * 0.06))

	local fw = math.floor(w * 0.48)
	local fh = math.floor(h * 0.07)
	local fy = math.floor(h * 0.30)
	user_field:setPosition(math.floor(w * 0.04), fy)
	user_field:setSize(fw, fh)

	local blink  = (math.floor(state.blink_t / 400) % 2) == 0
	local cursor = (state.focus == 1) and (blink and "_" or " ") or ""
	user_val:setText(state.username .. cursor)
	user_val:setPosition(4, math.floor(fh / 2) - 4)
	user_val:setSize(fw - 8, fh)

	theme_lbl:setText("Theme" .. (state.focus == 2 and " ◄" or ""))
	theme_lbl:setColor(C(fg_name))
	theme_lbl:setPosition(math.floor(w * 0.04), math.floor(h * 0.41))
	theme_lbl:setSize(w, math.floor(h * 0.06))

	local cw = math.floor(w * 0.14)
	local ch = math.floor(h * 0.07)
	local cy = math.floor(h * 0.48)

	local light_on = state.theme == "light"
	light_chip:setBackgroundColor(C(light_on and sel_col or bg_name))
	light_lbl:setColor(C(light_on and "black" or fg_name))
	light_chip:setPosition(math.floor(w * 0.04), cy)
	light_chip:setSize(cw, ch)
	light_lbl:setPosition(0, math.floor(ch / 2) - 4)
	light_lbl:setSize(cw, ch)

	local dark_on = state.theme == "dark"
	dark_chip:setBackgroundColor(C(dark_on and sel_col or bg_name))
	dark_lbl:setColor(C(dark_on and "black" or fg_name))
	dark_chip:setPosition(math.floor(w * 0.04) + cw + math.floor(w * 0.02), cy)
	dark_chip:setSize(cw, ch)
	dark_lbl:setPosition(0, math.floor(ch / 2) - 4)
	dark_lbl:setSize(cw, ch)

	local kw  = math.floor(w * 0.30)
	local kh  = math.floor(h * 0.07)
	local cont_y = math.floor(h * 0.58)
	cont_chip:setBackgroundColor(C(state.focus == 3 and "bright_yellow" or bg_name))
	cont_lbl:setColor(C(state.focus == 3 and "black" or fg_name))
	cont_chip:setPosition(math.floor((w - kw) / 2), cont_y)
	cont_chip:setSize(kw, kh)
	cont_lbl:setPosition(0, math.floor(kh / 2) - 4)
	cont_lbl:setSize(kw, kh)

	local hint_col = state.theme == "dark" and "bright_cyan" or "bright_black"
	setup_hint:setColor(C(hint_col))
	setup_hint:setPosition(math.floor(w * 0.02), h - math.floor(h * 0.07))
	setup_hint:setSize(w - math.floor(w * 0.04), math.floor(h * 0.06))
end)

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function finish_setup()
	atlasprofile.save_username(state.username)
	atlastheme.save(state.theme)
	pcall(fs.makeDir, "/etc/AtlasOS")
	pcall(fs.write, "/etc/AtlasOS/setup_complete", "v1\n")
end

local function show_phase(phase)
	load_panel:setVisible(phase == "loading")
	err_panel:setVisible(phase == "error")
	setup_panel:setVisible(phase == "setup")
end

local function redraw()
	show_phase(state.phase)
	mgr:update(0)
	mgr:draw()
end

-- ── Input ────────────────────────────────────────────────────────────────────

local function is_enter(k) return k == 28 or k == 257 end
local function is_tab(k)   return k == 15 end
local function is_back(k)  return k == 259 or k == 14 end
local function is_left(k)  return k == 263 or k == 203 end
local function is_right(k) return k == 262 or k == 205 or k == 204 end

local function handle_key(e)
	if e.type ~= "key" or e.down ~= true then return end
	local key = tonumber(e.key) or 0
	local ch  = e.char

	if state.phase == "setup" or state.phase == "error" then
		input.cancelKeyEvent(e)
	end

	if state.phase == "error" then
		print("AtlasOS: fix missing files (see on-screen list) then reboot.")
		return "quit"
	end

	if state.phase == "loading" then return nil end

	if is_tab(key) then
		state.focus = (state.focus % 3) + 1
		return nil
	end

	if state.focus == 1 then
		if is_back(key) then
			state.username = state.username:sub(1, -2) or ""
		elseif type(ch) == "string" and ch ~= "" and not e.ctrl then
			local b = ch:byte(1)
			if b and b >= 32 and b < 127 and #state.username < 32 then
				state.username = state.username .. ch
			end
		end
	elseif state.focus == 2 then
		if is_left(key) or is_right(key) or is_enter(key) then
			state.theme = (state.theme == "light") and "dark" or "light"
		end
	elseif state.focus == 3 and is_enter(key) then
		finish_setup()
		return "boot"
	end

	return nil
end

local function handle_mouse(e)
	if state.phase ~= "setup" then return nil end
	if e.type ~= "mouse" or e.button ~= "left" or e.pressed ~= true then return nil end
	if not (e.insideCanvas and type(e.uiX) == "number") then return nil end

	local px, py = e.uiX, e.uiY

	if light_chip:pointInBounds(px, py) then
		state.theme = "light"
		state.focus = 2
	elseif dark_chip:pointInBounds(px, py) then
		state.theme = "dark"
		state.focus = 2
	elseif user_field:pointInBounds(px, py) then
		state.focus = 1
	elseif cont_chip:pointInBounds(px, py) then
		state.focus = 3
		finish_setup()
		return "boot"
	end

	return nil
end

-- ── Main loop ────────────────────────────────────────────────────────────────

input.consumeKeyboard()

local out = nil
while not out do
	local events = input.poll_all()
	if #events == 0 then input.idle(16) end

	state.blink_t = now_ms()

	if state.phase == "loading" then
		if not state.install_co then
			local cli = args and args[1] and tostring(args[1])
			state.load_plan  = atlasinstall.build_plan(cli)
			state.load_title = state.load_plan.title or ""
			state.load_hint  = state.load_plan.hint  or ""
			state.load_detail = ""
			state.progress    = 0
			state.install_co  = atlasinstall.install_coroutine(state.load_plan, 5)
		end
		local co = state.install_co
		if coroutine.status(co) ~= "dead" then
			local st, tick_ok, a, b = coroutine.resume(co)
			if not st then
				state.phase   = "error"
				state.missing = { tostring(tick_ok) }
			elseif tick_ok == false then
				state.phase   = "error"
				state.missing = { tostring(a) }
			elseif tick_ok == true then
				state.progress    = tonumber(a) or state.progress
				state.load_detail = tostring(b or "")
			end
		end
		if coroutine.status(co) == "dead" and state.phase == "loading" then
			state.phase    = "setup"
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

input.releaseKeyboard()

if out == "boot" then
	dofile("/home/AtlasOS/boot_desktop.lua")
end
