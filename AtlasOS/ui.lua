--[[
  AtlasOS desktop: bottom taskbar + Start menu (pinned / grouped apps).
]]

local atlastheme = dofile("/home/lib/atlastheme.lua")
local atlassettings = nil
do
	local ok, m = pcall(dofile, "/home/lib/atlassettings.lua")
	atlassettings = ok and m or {
		developer_mode = function() return false end,
		toggle_developer_mode = function() return false end,
		set_developer_mode = function() end,
	}
end
local window = dofile("/home/lib/window.lua")
local widgets = dofile("/home/lib/widgets.lua")
local input = dofile("/home/lib/input.lua")
local startmenu = _G.startmenu or dofile("/home/lib/startmenu.lua")
_G.startmenu = startmenu
local draw = dofile("/home/lib/atlas_draw.lua")
local atlas_color = dofile("/home/lib/atlas_color.lua")
local appkit = dofile("/home/lib/appkit.lua")
local paths = dofile("/home/lib/desktop_paths.lua")
local deskutil = dofile("/home/lib/desktop_util.lua")
local settings_actions = dofile("/home/lib/settings_dispatch.lua")
local builtin_paint = dofile("/home/lib/builtin_window_paint.lua")

local LAYOUT_PATH = "/etc/AtlasOS/layout.txt"
local VERSION = "0.3.2"

-- Default canvas (cells) before first gfx_2d.setCanvasSize; avoids trusting the mod default.
local CANVAS_DEFAULT_W, CANVAS_DEFAULT_H = 150, 100

--- Per-row / per-app icon colors (appinfo icon_fg, icon_bg, icon_row_fg, icon_taskbar_sel_fg).
local function gfx_icon_row_style(meta, row_idx, default_fg, default_bg, taskbar_selected)
	local fg, bg = default_fg, default_bg
	if meta then
		local rr = meta.icon_row_fg
		if type(rr) == "table" and rr[row_idx] and tostring(rr[row_idx]) ~= "" then
			fg = tostring(rr[row_idx])
		elseif type(meta.icon_fg) == "string" and meta.icon_fg ~= "" then
			fg = meta.icon_fg
		end
	end
	if taskbar_selected then
		local sfg = meta and meta.icon_taskbar_sel_fg
		if type(sfg) == "string" and sfg ~= "" then
			fg = sfg
		else
			fg = "black"
		end
		return fg, 28
	end
	if meta and type(meta.icon_bg) == "string" and meta.icon_bg ~= "" then
		bg = meta.icon_bg
	end
	return fg, bg
end

local function size_get()
	local cw, ch = draw.canvas_cells()
	if cw and ch and cw >= 8 and ch >= 8 then return cw, ch end
	return CANVAS_DEFAULT_W, CANVAS_DEFAULT_H
end

local function size_set(w, h)
	w = math.max(1, math.min(240, math.floor(w or CANVAS_DEFAULT_W)))
	h = math.max(1, math.min(120, math.floor(h or CANVAS_DEFAULT_H)))
	draw.init()
	draw.set_canvas_from_cells(w, h)
end

local UI = {
	_size_get = size_get,
	_size_set = size_set,
	W = CANVAS_DEFAULT_W,
	H = CANVAS_DEFAULT_H,
	TASKBAR_H = math.max(1, math.min(10, math.floor(CANVAS_DEFAULT_H * 0.15 + 0.5))),
	desk = nil,
	start_open = false,
	activities_open = false,
	taskbar_sel = 1,
	files_dir = "/home",
	_drag = nil,
	_min_strip = {},
}

-- ── Taskbar GUI (Phase 2.2) ─────────────────────────────────────────────────
-- Cell→pixel helpers (match atlas_draw CELL_W=8, CELL_H=10)
local CW, CH = draw.cell_w, draw.cell_h
local function C(token) return atlas_color.resolve(token) end

-- Persistent gui_lib components for the taskbar strip.
-- Assumption: gui_lib.GUIManager:draw() issues gfx_2d.rect/text calls without
-- managing its own clear/batch cycle, so it can be called inside the existing
-- draw.begin_frame() / draw.end_frame() batch in UI.redraw().
local _TB_POOL      = 24
local _tb_mgr       = nil
local _tb_key       = nil    -- "W:H:TASKBAR_H" — rebuild on canvas change
local _tb_bg        = nil    -- Panel: full taskbar bg strip
local _tb_start     = nil    -- Panel: start-button zone
local _tb_slot_pool = {}     -- Panels: one per app slot (pooled)
local _tb_status    = nil    -- Text: centre status line (row 2 when th >= 3)
local _tb_clock     = nil    -- Text: clock / date (dock row, right-aligned)
local _tb_world     = nil    -- Text: world / entity line (dock row, left)
-- Per-slot icon rendering data, populated by the layout callback each frame:
local _tb_icon_data = {}     -- [i] = {sx, y_icon, slot_w, nrows, lines, sel, meta}
local _tb_search_w  = 0      -- search bar width (cells), needed by search API call
local _tb_y0        = 1      -- taskbar top row (1-based cells)

local function build_taskbar_gui()
	local P   = gui_lib.Panel
	local T   = gui_lib.Text
	local mgr = gui_lib.GUIManager.new()
	-- Transparent bg: draw.begin_frame() handles the canvas clear; mgr should
	-- not fill the whole canvas, only its component panels.
	mgr:setBackgroundColor(0, 0, 0, 0)

	local bg = P.new(0, 0, 0, 0)
	bg:setBorderColor(0, 0, 0, 0)
	mgr:addComponent(bg)

	local start_p = P.new(0, 0, 0, 0)
	start_p:setBorderColor(0, 0, 0, 0)
	mgr:addComponent(start_p)

	local pool = {}
	for i = 1, _TB_POOL do
		local sp = P.new(0, 0, 0, 0)
		sp:setBorderColor(0, 0, 0, 0)
		sp:setVisible(false)
		mgr:addComponent(sp)
		pool[i] = sp
	end

	local st_txt = T.new(0, 0, "")
	local ck_txt = T.new(0, 0, "")
	local wd_txt = T.new(0, 0, "")
	st_txt:setScale(1)
	ck_txt:setScale(1)
	wd_txt:setScale(1)
	mgr:addComponent(st_txt)
	mgr:addComponent(ck_txt)
	mgr:addComponent(wd_txt)

	mgr:setLayoutCallback(function(m, _pw, _ph)
		local t    = atlastheme.load()
		local tb   = t.mode == "dark" and "black" or 22
		local W, H, TH = UI.W, UI.H, UI.TASKBAR_H
		local y0   = H - TH + 1
		local py0  = (y0 - 1) * CH
		local ph_tb = TH * CH
		_tb_y0 = y0

		-- Background strip
		bg:setPosition(0, py0)
		bg:setSize(W * CW, ph_tb)
		bg:setBackgroundColor(C(tb))

		-- Start button area (cells x=2..5)
		local start_h = (TH >= 3) and 2 or TH
		start_p:setPosition(1 * CW, py0)     -- cell 2 → pixel x = 1*CW
		start_p:setSize(4 * CW, start_h * CH)
		start_p:setBackgroundColor(C(UI.start_open and 28 or tb))

		-- App slot panels
		local slots, search_w, settings_x = UI.taskbar_slots_visible()
		local trash_x = W - 19
		local step    = startmenu.taskbar_icon_step()
		local slot_w  = 6
		_tb_search_w  = search_w
		_tb_icon_data = {}
		local si = 0
		for i, id in ipairs(slots) do
			si = si + 1
			local sx
			if i <= #slots - 2 then
				sx = 7 + search_w + 1 + (i - 1) * step
			elseif i == #slots - 1 then
				sx = settings_x
			else
				sx = trash_x
			end
			local sp = pool[si]
			if sp then
				sp:setVisible(true)
				sp:setPosition((sx - 1) * CW, py0)
				sp:setSize(slot_w * CW, TH * CH)
				local sel = (si == UI.taskbar_sel)
				sp:setBackgroundColor(C(sel and 28 or tb))
				sp:setBorderColor(0, 0, 0, 0)
				local meta = startmenu.registry[id]
				local lines, nrows = {}, 1
				if meta then
					lines, nrows = startmenu.icon_taskbar_lines(meta, TH)
				end
				_tb_icon_data[si] = {
					sx = sx, y_icon = y0,
					slot_w = slot_w, nrows = nrows,
					lines = lines, sel = sel, meta = meta,
				}
			end
		end
		for j = si + 1, _TB_POOL do
			if pool[j] then pool[j]:setVisible(false) end
		end

		-- Centre status line (second row when th >= 3)
		if TH >= 3 then
			local gap_x = 7 + search_w + 1
			local gap_w = settings_x - gap_x - 1
			if gap_w >= 7 then
				local s = deskutil.taskbar_status_line(gap_w)
				if s == "" then s = "AtlasOS" end
				st_txt:setVisible(true)
				st_txt:setText(s)
				st_txt:setColor(C(28))
				st_txt:setPosition((gap_x - 1) * CW, py0 + CH)
				st_txt:setSize(gap_w * CW, CH)
			else
				st_txt:setVisible(false)
			end
		else
			st_txt:setVisible(false)
		end

		-- Clock (dock row, right-aligned)
		local dt     = deskutil.dock_datetime_str()
		local y_dock = y0 + TH - 1
		local py_d   = (y_dock - 1) * CH
		ck_txt:setText(dt)
		ck_txt:setColor(C(28))
		ck_txt:setPosition((W - #dt - 1) * CW, py_d)
		ck_txt:setSize(#dt * CW, CH)

		-- World / entity line (dock row, left)
		local world = deskutil.dock_world_line()
		local room  = W - #dt - 4
		if room >= 8 then
			local wl = world
			if #wl > room then wl = wl:sub(1, room - 1) .. "…" end
			wd_txt:setVisible(true)
			wd_txt:setText(wl)
			wd_txt:setColor(C(28))
			wd_txt:setPosition(1 * CW, py_d)   -- cell 2 → pixel 8
			wd_txt:setSize(room * CW, CH)
		else
			wd_txt:setVisible(false)
		end
	end)

	_tb_mgr       = mgr
	_tb_bg        = bg
	_tb_start     = start_p
	_tb_slot_pool = pool
	_tb_status    = st_txt
	_tb_clock     = ck_txt
	_tb_world     = wd_txt
end

-- ── Start Menu GUI (Phase 2.3) ───────────────────────────────────────────────
local _SM_MAX_GROUPS = 8      -- max group name labels
local _SM_MAX_TILES  = 48     -- max tile buttons (pooled)
local _SM_MAX_APPS   = 64     -- max all-apps rows

local _sm_mgr        = nil     -- GUIManager
local _sm_key        = nil     -- "W:H:TASKBAR_H" rebuild trigger
local _sm_panel      = nil     -- Panel: main menu container
local _sm_search_txt = nil     -- Text: search placeholder
local _sm_pinned_hdr = nil     -- Text: "── Pinned (groups) ──"
local _sm_grp_names  = {}      -- Text[]: group name labels
local _sm_tiles      = {}      -- Button[]: pooled tile buttons
local _sm_allapps_hdr= nil     -- Text: "── All apps ──"
local _sm_app_icon   = {}      -- Text[]: all-apps icon marks
local _sm_app_label  = {}      -- Text[]: all-apps labels
local _sm_footer_txt = nil     -- Text: hint footer
-- per-frame tile render data (for icon text overlays)
local _sm_tile_data  = {}      -- [i] = {tx, row, tile_w, nrows, block, meta}

local function build_start_menu_gui()
	local P = gui_lib.Panel
	local T = gui_lib.Text
	local B = gui_lib.Button
	local mgr = gui_lib.GUIManager.new()
	mgr:setBackgroundColor(0, 0, 0, 0)

	local panel = P.new(0, 0, 0, 0)
	panel:setVisible(false)
	mgr:addComponent(panel)

	local search_t = T.new(0, 0, " Search apps and files...")
	search_t:setScale(1) ; search_t:setVisible(false)
	mgr:addComponent(search_t)

	local pinned_hdr = T.new(0, 0, "")
	pinned_hdr:setScale(1) ; pinned_hdr:setVisible(false)
	mgr:addComponent(pinned_hdr)

	local grp_names = {}
	for i = 1, _SM_MAX_GROUPS do
		local t = T.new(0, 0, "") ; t:setScale(1) ; t:setVisible(false)
		mgr:addComponent(t)
		grp_names[i] = t
	end

	local tiles = {}
	for i = 1, _SM_MAX_TILES do
		local b = B.new(0, 0, 0, 0, "", function() end)
		b:setVisible(false)
		mgr:addComponent(b)
		tiles[i] = b
	end

	local allapps_hdr = T.new(0, 0, "")
	allapps_hdr:setScale(1) ; allapps_hdr:setVisible(false)
	mgr:addComponent(allapps_hdr)

	local app_icons, app_labels = {}, {}
	for i = 1, _SM_MAX_APPS do
		local ic = T.new(0, 0, "") ; ic:setScale(1) ; ic:setVisible(false)
		local lb = T.new(0, 0, "") ; lb:setScale(1) ; lb:setVisible(false)
		mgr:addComponent(ic)
		mgr:addComponent(lb)
		app_icons[i] = ic ; app_labels[i] = lb
	end

	local footer = T.new(0, 0, "")
	footer:setScale(1) ; footer:setVisible(false)
	mgr:addComponent(footer)

	mgr:setLayoutCallback(function(m, _pw, _ph)
		local visible = UI.start_open
		local t   = atlastheme.load()
		local th  = UI.TASKBAR_H
		local W, H = UI.W, UI.H
		local pw  = math.min(50, math.max(36, math.floor(W * 0.52)))
		local ph  = math.min(H - th - 2, math.max(14, math.floor(H * 0.68)))
		local py  = H - th - ph + 1
		local px  = 2
		local panel_bg_tok = t.mode == "dark" and "black" or "white"
		local panel_fg_tok = t.mode == "dark" and "white" or "black"
		local r,g,b,a = C(panel_bg_tok)
		local fr,fg_,fb,fa = C(panel_fg_tok)
		local hr,hg,hb,ha = C(28)   -- highlight/accent color

		_sm_panel:setVisible(visible)
		_sm_panel:setPosition((px-1)*CW, (py-1)*CH)
		_sm_panel:setSize(pw*CW, ph*CH)
		_sm_panel:setBackgroundColor(r,g,b,a)
		_sm_panel:setBorderColor(hr,hg,hb,ha)

		if not visible then
			for i = 1, _SM_MAX_GROUPS do if _sm_grp_names[i] then _sm_grp_names[i]:setVisible(false) end end
			for i = 1, _SM_MAX_TILES do if _sm_tiles[i] then _sm_tiles[i]:setVisible(false) end end
			for i = 1, _SM_MAX_APPS do
				if _sm_app_icon[i] then _sm_app_icon[i]:setVisible(false) end
				if _sm_app_label[i] then _sm_app_label[i]:setVisible(false) end
			end
			_sm_search_txt:setVisible(false)
			_sm_pinned_hdr:setVisible(false)
			_sm_allapps_hdr:setVisible(false)
			_sm_footer_txt:setVisible(false)
			return
		end

		-- Row counter in cells
		local row = py + 1

		-- Search placeholder
		_sm_search_txt:setVisible(true)
		_sm_search_txt:setText(" Search apps and files...")
		_sm_search_txt:setColor(fr,fg_,fb,fa)
		_sm_search_txt:setPosition((px)*CW, (row-1)*CH)
		row = row + 2

		-- Pinned header
		_sm_pinned_hdr:setVisible(true)
		_sm_pinned_hdr:setText("── Pinned (groups) ──")
		_sm_pinned_hdr:setColor(hr,hg,hb,ha)
		_sm_pinned_hdr:setPosition((px)*CW, (row-1)*CH)
		row = row + 1

		local groups = startmenu.load()
		local tile_w, gap = 14, 1
		local icon_rows = 4
		local tile_h = icon_rows + 1
		local cols = math.max(2, math.floor((pw - 3) / (tile_w + gap)))

		local ti = 0   -- tile pool index
		local gi = 0   -- group name index
		_sm_tile_data = {}

		for _, g in ipairs(groups) do
			if row >= py + ph - 8 then break end
			gi = gi + 1
			local grp_t = _sm_grp_names[gi]
			if grp_t then
				grp_t:setVisible(true)
				grp_t:setText(g.name)
				grp_t:setColor(hr,hg,hb,ha)
				grp_t:setPosition((px)*CW, (row-1)*CH)
			end
			row = row + 1
			local col = 0
			for _, id in ipairs(g.ids) do
				local meta = startmenu.registry[id]
				if meta and row + tile_h <= py + ph - 6 then
					ti = ti + 1
					local tb = _sm_tiles[ti]
					if tb then
						local tx = px + 2 + col * (tile_w + gap)
						tb:setVisible(true)
						tb:setPosition((tx-1)*CW, (row-1)*CH)
						tb:setSize(tile_w*CW, tile_h*CH)
						tb:setNormalColor(C(22))
						tb:setLabel("")  -- icon text drawn as overlay
						local cap_id = id
						tb:setOnPress(function()
							UI.start_open = false
							UI.launch_app(cap_id)
						end)
						-- store icon overlay data
						local iw = tile_w - 2
						local raw = startmenu.icon_lines(meta)
						while #raw > icon_rows do table.remove(raw) end
						local blank = string.rep(" ", iw)
						local top = math.floor((icon_rows - #raw) / 2)
						local block = {}
						for _ = 1, top do block[#block+1] = blank end
						for j = 1, #raw do
							block[#block+1] = raw[j] .. string.rep(" ", math.max(0, iw - #raw[j]))
						end
						while #block < icon_rows do block[#block+1] = blank end
						_sm_tile_data[ti] = {
							tx = tx, row = row,
							tile_w = tile_w, nrows = icon_rows,
							block = block, meta = meta,
						}
					end
					col = col + 1
					if col >= cols then
						col = 0
						row = row + tile_h + 1
					end
				end
			end
			if col > 0 then row = row + tile_h + 1 end
			row = row + 1
		end

		-- Hide unused tile pool entries
		for j = ti + 1, _SM_MAX_TILES do
			if _sm_tiles[j] then _sm_tiles[j]:setVisible(false) end
		end
		for j = gi + 1, _SM_MAX_GROUPS do
			if _sm_grp_names[j] then _sm_grp_names[j]:setVisible(false) end
		end

		-- All apps header
		_sm_allapps_hdr:setVisible(true)
		_sm_allapps_hdr:setText("── All apps ──")
		_sm_allapps_hdr:setColor(hr,hg,hb,ha)
		_sm_allapps_hdr:setPosition((px)*CW, (row-1)*CH)
		row = row + 1

		local ai = 0
		for _, id in ipairs(startmenu.all_app_ids()) do
			if row >= py + ph - 3 then break end
			local meta = startmenu.registry[id]
			if meta then
				ai = ai + 1
				local mark = (startmenu.icon_lines(meta)[1] or "?"):sub(1, 8)
				local ifg, ibg = gfx_icon_row_style(meta, 1, panel_fg_tok, panel_bg_tok, false)
				local ic_t = _sm_app_icon[ai]
				local lb_t = _sm_app_label[ai]
				if ic_t and lb_t then
					ic_t:setVisible(true)
					ic_t:setText(mark)
					ic_t:setColor(C(ifg))
					ic_t:setPosition((px+1)*CW, (row-1)*CH)
					lb_t:setVisible(true)
					lb_t:setText("  " .. meta.label .. "  (" .. id .. ")")
					lb_t:setColor(fr,fg_,fb,fa)
					lb_t:setPosition((px+1+#mark)*CW, (row-1)*CH)
				end
				row = row + 1
			end
		end
		for j = ai + 1, _SM_MAX_APPS do
			if _sm_app_icon[j] then _sm_app_icon[j]:setVisible(false) end
			if _sm_app_label[j] then _sm_app_label[j]:setVisible(false) end
		end

		-- Footer
		_sm_footer_txt:setVisible(true)
		_sm_footer_txt:setText("pin user apps only  find|search <text>")
		_sm_footer_txt:setColor(hr,hg,hb,ha)
		_sm_footer_txt:setPosition((px)*CW, (py + ph - 2 - 1)*CH)
	end)

	_sm_mgr = mgr ; _sm_panel = panel
	_sm_search_txt = search_t ; _sm_pinned_hdr = pinned_hdr
	_sm_grp_names = grp_names ; _sm_tiles = tiles
	_sm_allapps_hdr = allapps_hdr
	_sm_app_icon = app_icons ; _sm_app_label = app_labels
	_sm_footer_txt = footer
end

local function settings_ctx()
	return {
		UI = UI,
		atlastheme = atlastheme,
		startmenu = startmenu,
		window = window,
		paths = paths,
	}
end

function UI.developer_mode_enabled()
	return atlassettings.developer_mode and atlassettings.developer_mode() or false
end

function UI.toggle_developer_mode()
	if atlassettings.toggle_developer_mode then
		return atlassettings.toggle_developer_mode()
	end
	return false
end

--- Hide system AtlasOS tree from Files when not developer: no `AtlasOS` under /home.
function UI.files_show_list_entry(parent_dir, entry_name, is_dir)
	if UI.developer_mode_enabled() then return true end
	if not is_dir then return true end
	if paths.normalize(parent_dir) == "/home" and entry_name == "AtlasOS" then
		return false
	end
	return true
end

function UI.files_effective_dir()
	local d = paths.normalize(UI.files_dir or "/home")
	if paths.is_AtlasOS_tree(d) and not UI.developer_mode_enabled() then
		return "/home"
	end
	return d
end

--- Apply `appinfo.args` that affect the desktop before focusing `meta.window`.
--- For `window` == `"Files"`, the first arg (if non-empty) is passed to `files_set_dir`.
function UI.apply_launch_args(meta)
	if not meta or meta.window ~= "Files" then return end
	local a = meta.args
	if type(a) ~= "table" then return end
	local path = a[1]
	if path == nil then return end
	path = tostring(path)
	if path:match("%S") then UI.files_set_dir(path) end
end

UI._search_api_cached = nil
UI._files_painter = nil

local function search_offline_api()
	return {
		clear = function() end,
		begin = function() end,
		step = function() end,
		get_state = function()
			return { needle = "", needle_display = "", name_hits = {}, content_hits = {}, busy = false }
		end,
		draw_taskbar = function(ag, opt)
			ag.fillRect(opt.x, opt.y0, opt.sw, math.max(1, opt.th >= 3 and 2 or 1), "white")
			ag.text(opt.x, opt.y0, "[search missing]", "black", "white")
		end,
	}
end

function UI.search_api()
	if UI._search_api_cached then return UI._search_api_cached end
	local candidates = {}
	if startmenu._AtlasOS_search and startmenu._AtlasOS_search.package_dir and startmenu._AtlasOS_search.module then
		candidates[#candidates + 1] = startmenu._AtlasOS_search.package_dir .. "/" .. startmenu._AtlasOS_search.module
	end
	candidates[#candidates + 1] = "/home/AtlasOS/apps/search/search_engine.lua"
	for _, p in ipairs(candidates) do
		local ok, m = pcall(function()
			if not fs.read(p) then return nil end
			return dofile(p)
		end)
		if ok and type(m) == "table" and m.begin and m.step and m.draw_taskbar then
			UI._search_api_cached = m
			return m
		end
	end
	UI._search_api_cached = search_offline_api()
	return UI._search_api_cached
end

function UI.invalidate_packages()
	UI._search_api_cached = nil
	UI._files_painter = nil
	UI._editor_painter = nil
	UI._settings_painter = nil
	UI._welcome_painter = nil
	UI._status_painter = nil
	UI._console_painter = nil
end

function UI.search_clear()
	UI.search_api().clear()
end

function UI.search_begin(needle)
	UI.search_api().begin(needle)
end

function UI.search_step(budget)
	UI.search_api().step(budget)
end

--- Slots actually drawn (user pins may be truncated if taskbar is narrow).
function UI.taskbar_slots_visible()
	UI.update_size()
	local W = UI.W
	local settings_x = math.max(22, W - 24)
	local lc = #startmenu.TASKBAR_LEFT
	local step = startmenu.taskbar_icon_step()
	-- Room: Start+gap + search + gap + icons (step cols each) + ≥1 user pin
	local max_sw = settings_x - 7 - 1 - step * lc - step
	local search_w = math.min(28, math.max(4, math.floor(W * 0.20), max_sw))
	if search_w < 4 then search_w = 4 end
	if 7 + search_w + 1 + step * lc > settings_x - 2 then
		search_w = math.max(4, settings_x - 7 - 1 - step * lc - 1)
	end
	local x = 7 + search_w + 1
	local slots = {}
	for _, id in ipairs(startmenu.TASKBAR_LEFT) do
		slots[#slots + 1] = id
		x = x + step
	end
	for _, id in ipairs(startmenu.flatten_user_pins(14)) do
		if x + step > settings_x - 2 then break end
		slots[#slots + 1] = id
		x = x + step
	end
	for _, id in ipairs(startmenu.TASKBAR_RIGHT) do
		slots[#slots + 1] = id
	end
	return slots, search_w, settings_x
end

function UI.workspace_rect()
	local th = math.max(1, UI.TASKBAR_H)
	return 1, 1, UI.W, UI.H - th
end

function UI.update_size()
	local w, h = UI._size_get()
	-- Taskbar needs room for Start + search + 2 left icons + pins + Settings + Trash + clock/status strip
	UI.W = math.max(54, math.floor(w or 80))
	UI.H = math.max(12, math.floor(h or 24))
	-- 3 rows: icons+search, search stats / filler, entity+date (QoL dock strip)
	UI.TASKBAR_H = (UI.H >= 22) and 3 or math.max(2, math.min(3, math.floor(UI.H * 0.10 + 0.5)))
end

local REF_W, REF_H = 80, 24
local REF_TASKBAR = 2
local function ref_workspace()
	return 1, 1, REF_W, REF_H - REF_TASKBAR
end

--- Fractional def: xf,yf,wf,hf in 0..1 of workspace. Legacy: absolute x,y,w,h scaled from REF canvas.
local function resolve_window_rect(def, wx, wy, ww, wh)
	local minw, minh = math.max(6, math.floor(ww * 0.12)), math.max(3, math.floor(wh * 0.12))
	if def.xf then
		local x = wx + math.floor((def.xf or 0) * ww)
		local y = wy + math.floor((def.yf or 0) * wh)
		local rw = math.max(minw, math.floor((def.wf or 0.25) * ww))
		local rh = math.max(minh, math.floor((def.hf or 0.25) * wh))
		x = math.max(wx, math.min(x, wx + ww - rw))
		y = math.max(wy, math.min(y, wy + wh - rh))
		return x, y, rw, rh
	end
	local rwx, rwy, rww, rwh = ref_workspace()
	local x = wx + math.floor(((def.x - rwx) / rww) * ww)
	local y = wy + math.floor(((def.y - rwy) / rwh) * wh)
	local rw = math.max(minw, math.floor((def.w / rww) * ww))
	local rh = math.max(minh, math.floor((def.h / rwh) * wh))
	x = math.max(wx, math.min(x, wx + ww - rw))
	y = math.max(wy, math.min(y, wy + wh - rh))
	return x, y, rw, rh
end

function UI.device_name()
	return deskutil.hostname()
end

function UI.settings_dispatch(tag)
	settings_actions.dispatch(settings_ctx(), tag)
end

function UI._theme_reload_desktop()
	settings_actions.reload_desktop(settings_ctx())
end

function UI.layout_load()
	local raw = fs.read(LAYOUT_PATH)
	if not raw then return nil end
	local out = { theme = nil, taskbar_sel = 1, windows = {} }
	for line in raw:gmatch("[^\r\n]+") do
		local k, v = line:match("^([%w_]+)=(.*)$")
		if k == "theme" and (v == "light" or v == "dark") then out.theme = v end
		if k == "dock_sel" or k == "taskbar_sel" then out.taskbar_sel = math.floor(tonumber(v) or 1) end
		local title, xf, yf, wf, hf = line:match("^([%w]+)%s+f%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)$")
		if title and xf then
			out.windows[#out.windows + 1] = {
				title = title,
				xf = tonumber(xf),
				yf = tonumber(yf),
				wf = tonumber(wf),
				hf = tonumber(hf),
			}
		else
			local t2, x, y, w, h = line:match("^([%w]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
			if t2 and x then
				out.windows[#out.windows + 1] = {
					title = t2,
					x = tonumber(x),
					y = tonumber(y),
					w = tonumber(w),
					h = tonumber(h),
				}
			end
		end
	end
	return out
end

function UI.layout_save()
	fs.makeDir("/etc/AtlasOS")
	local t = atlastheme.load()
	UI.update_size()
	local wx, wy, ww, wh = UI.workspace_rect()
	local lines = {
		"layout_version=2",
		"theme=" .. t.mode,
		"taskbar_sel=" .. tostring(UI.taskbar_sel),
	}
	if UI.desk and UI.desk._windows then
		for _, win in ipairs(UI.desk._windows) do
			if ww > 0 and wh > 0 then
				local xf = (win.x - wx) / ww
				local yf = (win.y - wy) / wh
				local wf = win.w / ww
				local hf = win.h / wh
				lines[#lines + 1] = string.format(
					"%s f %.4f %.4f %.4f %.4f",
					win.title or "Window", xf, yf, wf, hf
				)
			end
		end
	end
	fs.write(LAYOUT_PATH, table.concat(lines, "\n"))
end

-- Default layout: fractions of workspace (wx..wx+ww, wy..wy+wh)
local default_layout = {
	{ title = "Guide",    xf = 0.03, yf = 0.06, wf = 0.52, hf = 0.62 },
	{ title = "Files",    xf = 0.03, yf = 0.10, wf = 0.34, hf = 0.52 },
	{ title = "Settings", xf = 0.40, yf = 0.32, wf = 0.56, hf = 0.40 },
	{ title = "Console",  xf = 0.06, yf = 0.58, wf = 0.86, hf = 0.36 },
}

function UI.build_desktop()
	UI.update_size()
	local layout = UI.layout_load()
	if layout and layout.theme then
		atlastheme.save(layout.theme)
	end
	if layout and layout.taskbar_sel then
		local slots = UI.taskbar_slots_visible()
		UI.taskbar_sel = math.max(1, math.min(layout.taskbar_sel, math.max(1, #slots)))
	end

	UI.desk = window.Desktop.new()
	atlastheme.apply_desktop(UI.desk)

	local wx, wy, ww, wh = UI.workspace_rect()
	local wins = (layout and layout.windows and #layout.windows > 0) and layout.windows or default_layout

	for i, def in ipairs(wins) do
		local x, y, rw, rh = resolve_window_rect(def, wx, wy, ww, wh)
		local w = window.new({
			x = x,
			y = y,
			w = rw,
			h = rh,
			title = def.title,
			minimized = def.minimized == true,
		})
		atlastheme.style_window(w, def.title)
		window.Desktop.add(UI.desk, w)
		if i == 1 then window.Desktop.set_focus(UI.desk, w) end
	end
	local foc = window.Desktop.focused(UI.desk)
	if foc and foc.minimized then
		for _, w in ipairs(UI.desk._windows) do
			if not w.minimized then
				window.Desktop.set_focus(UI.desk, w)
				break
			end
		end
	end

	local has_editor = false
	for _, w in ipairs(UI.desk._windows) do
		if w.title == "Editor" then
			has_editor = true
			break
		end
	end
	if not has_editor then
		local x, y, rw, rh = resolve_window_rect({
			title = "Editor",
			xf = 0.50,
			yf = 0.08,
			wf = 0.46,
			hf = 0.52,
		}, wx, wy, ww, wh)
		local ed = window.new({
			x = x,
			y = y,
			w = rw,
			h = rh,
			title = "Editor",
			minimized = true,
		})
		atlastheme.style_window(ed, "Editor")
		window.Desktop.add(UI.desk, ed)
	end
end

local function editor_split_lines(raw)
	if raw == nil or raw == "" then return { "" } end
	local t = {}
	for line in (raw .. "\n"):gmatch("(.-)\n") do
		t[#t + 1] = line
	end
	return t
end

function UI.editor_ensure()
	if UI._editor then return end
	UI._editor = {
		path = "/home/notes.txt",
		lines = { "" },
		cur_line = 1,
		cur_col = 0,
		scroll = 1,
		dirty = false,
	}
	UI.editor_load(UI._editor.path)
end

function UI.editor_load(path)
	if not path or path == "" then path = "/home/notes.txt" end
	UI.editor_ensure()
	local raw = fs.read(path)
	UI._editor.lines = editor_split_lines(raw)
	if #UI._editor.lines == 0 then UI._editor.lines = { "" } end
	UI._editor.path = path
	UI._editor.cur_line = 1
	UI._editor.cur_col = 0
	UI._editor.scroll = 1
	UI._editor.dirty = false
end

function UI.editor_save()
	UI.editor_ensure()
	local st = UI._editor
	local path = st.path or "/home/notes.txt"
	local par = path:match("^(.+)/[^/]+$") or "/"
	pcall(fs.makeDir, par)
	local ok = pcall(fs.write, path, table.concat(st.lines, "\n"))
	if ok then st.dirty = false end
	return ok
end

function UI.editor_open(path)
	UI.editor_ensure()
	if path and tostring(path) ~= "" then
		UI.editor_load(tostring(path))
	end
	UI.focus_window_by_title("Editor")
end

--- Returns true if key was consumed (Editor focused).
function UI.editor_handle_key(e)
	UI.editor_ensure()
	local st = UI._editor
	local key = tonumber(e.key) or 0
	local ctrl = e.ctrl == true
	local ch = e.char

	if ctrl and (key == 83 or (type(ch) == "string" and ch:lower() == "s")) then
		UI.editor_save()
		return true
	end

	if key == 15 then
		local line = st.lines[st.cur_line] or ""
		local c = st.cur_col
		st.lines[st.cur_line] = line:sub(1, c) .. "  " .. line:sub(c + 1)
		st.cur_col = c + 2
		st.dirty = true
		return true
	end

	if key == 28 or key == 257 then
		local line = st.lines[st.cur_line] or ""
		local c = st.cur_col
		local rest = line:sub(c + 1)
		st.lines[st.cur_line] = line:sub(1, c)
		table.insert(st.lines, st.cur_line + 1, rest)
		st.cur_line = st.cur_line + 1
		st.cur_col = 0
		st.dirty = true
		return true
	end

	if key == 259 then
		local line = st.lines[st.cur_line] or ""
		local c = st.cur_col
		if c > 0 then
			st.lines[st.cur_line] = line:sub(1, c - 1) .. line:sub(c + 1)
			st.cur_col = c - 1
			st.dirty = true
		elseif st.cur_line > 1 then
			local prev = st.lines[st.cur_line - 1] or ""
			st.cur_col = #prev
			st.lines[st.cur_line - 1] = prev .. line
			table.remove(st.lines, st.cur_line)
			st.cur_line = st.cur_line - 1
			st.dirty = true
		end
		return true
	end

	if key == 261 then
		local line = st.lines[st.cur_line] or ""
		local c = st.cur_col
		if c < #line then
			st.lines[st.cur_line] = line:sub(1, c) .. line:sub(c + 2)
			st.dirty = true
		elseif st.cur_line < #st.lines then
			st.lines[st.cur_line] = line .. (st.lines[st.cur_line + 1] or "")
			table.remove(st.lines, st.cur_line + 1)
			st.dirty = true
		end
		return true
	end

	local function is_left(k) return k == 263 or k == 203 end
	local function is_right(k) return k == 262 or k == 205 or k == 204 end
	local function is_up(k) return k == 265 or k == 200 end
	local function is_down(k) return k == 264 or k == 208 end

	if is_left(key) then
		if st.cur_col > 0 then
			st.cur_col = st.cur_col - 1
		elseif st.cur_line > 1 then
			st.cur_line = st.cur_line - 1
			st.cur_col = #(st.lines[st.cur_line] or "")
		end
		return true
	end
	if is_right(key) then
		local line = st.lines[st.cur_line] or ""
		if st.cur_col < #line then
			st.cur_col = st.cur_col + 1
		elseif st.cur_line < #st.lines then
			st.cur_line = st.cur_line + 1
			st.cur_col = 0
		end
		return true
	end
	if is_up(key) and st.cur_line > 1 then
		st.cur_line = st.cur_line - 1
		st.cur_col = math.min(st.cur_col, #(st.lines[st.cur_line] or ""))
		return true
	end
	if is_down(key) and st.cur_line < #st.lines then
		st.cur_line = st.cur_line + 1
		st.cur_col = math.min(st.cur_col, #(st.lines[st.cur_line] or ""))
		return true
	end

	if type(ch) == "string" and ch ~= "" and not ctrl then
		local b = string.byte(ch, 1)
		if b and b >= 32 then
			local line = st.lines[st.cur_line] or ""
			local c = st.cur_col
			st.lines[st.cur_line] = line:sub(1, c) .. ch .. line:sub(c + 1)
			st.cur_col = c + #ch
			st.dirty = true
			return true
		end
	end

	return false
end

do
	local builtin = builtin_paint.create({
		UI = UI,
		window = window,
		widgets = widgets,
		draw = draw,
		appkit = appkit,
		atlastheme = atlastheme,
		VERSION = VERSION,
		paths = paths,
		deskutil = deskutil,
		startmenu = startmenu,
	})
	UI.paint_window_content = builtin.paint_window_content
end

function UI.launch_app(id)
	local meta = startmenu.registry[id]
	if not meta then return end
	if startmenu.is_taskbar_fixed(id) and meta.window then
		UI.apply_launch_args(meta)
		UI.focus_window_by_title(meta.window)
		return
	end
	if meta.entry and meta.package_dir then
		local ok, err = startmenu.run_package(id)
		if ok then
			UI.apply_launch_args(meta)
			if meta.window then
				UI.focus_window_by_title(meta.window)
			else
				UI.focus_window_by_title("Console")
			end
		else
			_G.AtlasOS_log = _G.AtlasOS_log or {}
			_G.AtlasOS_log[#_G.AtlasOS_log + 1] = "[app] " .. tostring(err)
		end
		UI.redraw()
		return
	end
	if meta.window then
		UI.apply_launch_args(meta)
		UI.focus_window_by_title(meta.window)
	end
end

function UI.toggle_start()
	UI.start_open = not UI.start_open
	UI.redraw()
end

--- Hit-test taskbar (cell coords). Returns "start", "search", 1-based slot index, or nil.
function UI.taskbar_hit(cx, cy)
	UI.update_size()
	local y0 = UI.H - UI.TASKBAR_H + 1
	local th = UI.TASKBAR_H
	if cy < y0 or cy > y0 + th - 1 then return nil end
	local start_h = (th >= 3) and 2 or th
	if cx >= 2 and cx <= 5 and cy <= y0 + start_h - 1 then return "start" end
	local slots, search_w, settings_x = UI.taskbar_slots_visible()
	local trash_x = UI.W - 19
	local step = startmenu.taskbar_icon_step()
	local slot_w = 6
	if cx >= 7 and cx <= 7 + search_w - 1 then return "search" end
	local x = 7 + search_w + 1
	for i = 1, #slots do
		local sx
		if i <= #slots - 2 then
			sx = 7 + search_w + 1 + (i - 1) * step
		elseif i == #slots - 1 then
			sx = settings_x
		else
			sx = trash_x
		end
		if cx >= sx and cx <= sx + slot_w - 1 then return i end
	end
	return nil
end

--- Hit-test start menu panel (cell coords). Returns "panel", "search" (top row), or nil.
function UI.start_menu_hit(cx, cy)
	if not UI.start_open then return nil end
	local th = UI.TASKBAR_H
	local pw = math.min(50, math.max(36, math.floor(UI.W * 0.52)))
	local ph = math.min(UI.H - th - 2, math.max(14, math.floor(UI.H * 0.68)))
	local py = UI.H - th - ph + 1
	local px = 2
	if cx < px or cx > px + pw - 1 or cy < py or cy > py + ph - 1 then return nil end
	if cy <= py + 1 then return "search" end
	return "panel"
end

--- Handle one input event (key or mouse). GLFW: ESC=1, ENTER=28, LEFT=203, RIGHT=205, TAB=15.
function UI.handle_event(e)
	if e.type == "key" then
		local key = e.key
		local down = (e.down == true)
		if not down then return end
		local fw = UI.desk and window.Desktop.focused(UI.desk)
		if fw and fw.title == "Editor" and not fw.minimized then
			if UI.editor_handle_key(e) then
				UI.redraw()
				return
			end
		end
		if fw and not fw.minimized and type(fw._atlas_on_key) == "function" then
			if fw._atlas_on_key(e) then
				UI.redraw()
				return
			end
		end
		if key == 1 then
			UI.start_open = false
			UI.activities_open = false
			UI.redraw()
			return
		end
		if key == 15 and UI.desk then
			window.Desktop.focus_next(UI.desk)
			UI.redraw()
			return
		end
		if key == 28 then
			local slots = UI.taskbar_slots_visible()
			local id = slots[UI.taskbar_sel]
			if id then UI.launch_app(id) end
			UI.redraw()
			return
		end
		if key == 203 or key == 205 then
			local slots = UI.taskbar_slots_visible()
			local n = #slots
			if n >= 1 then
				if key == 203 then
					UI.taskbar_sel = (UI.taskbar_sel - 2 + n) % n + 1
				else
					UI.taskbar_sel = (UI.taskbar_sel % n) + 1
				end
				UI.redraw()
			end
			return
		end
	end
	if e.type == "mouse" then
		local cx, cy
		-- Use canvas pixel coordinates when available (uiX/uiY) and fall back to
		-- input.pixel_to_cell otherwise. Under hard cutover, atlasgfx provides
		-- consistent pixel-to-cell mapping.
		if e.insideCanvas and type(e.uiX) == "number" and type(e.uiY) == "number" then
			cx, cy = draw.pixel_to_cell_rel(e.uiX, e.uiY)
			cx = math.max(1, math.min(UI.W, cx))
			cy = math.max(1, math.min(UI.H, cy))
		else
			cx, cy = input.pixel_to_cell(e.x, e.y, UI.W, UI.H)
		end
		local left = (e.button == "left")

		if UI._drag and e.type == "mouse" then
			if left and e.released == true then
				UI._drag = nil
				UI.redraw()
				return
			end
			if e.wheel and e.wheel ~= 0 then
				return
			end
			if e.button == "right" or e.button == "middle" then
				return
			end
			if e.button ~= "left" and e.button ~= "none" then
				return
			end
			local w = UI._drag.win
			if w and not w.maximized and not w.minimized then
				local wx, wy, ww, wh = UI.workspace_rect()
				w.x = math.max(wx, math.min(wx + ww - w.w, cx - UI._drag.offx))
				w.y = math.max(wy, math.min(wy + wh - w.h, cy - UI._drag.offy))
			end
			UI.redraw()
			return
		end

		if not (left and e.pressed == true) then return end

		local hit = UI.taskbar_hit(cx, cy)
		if hit == "start" then
			UI.toggle_start()
			return
		end
		if hit == "search" then
			if UI.start_open then UI.start_open = false end
			UI.redraw()
			return
		end
		if type(hit) == "number" then
			local slots = UI.taskbar_slots_visible()
			if slots[hit] then
				UI.taskbar_sel = hit
				UI.launch_app(slots[hit])
				UI.start_open = false
				UI.redraw()
			end
			return
		end

		if UI.start_open and UI.start_menu_hit(cx, cy) then
			return
		end
		if UI.start_open then
			UI.start_open = false
			UI.redraw()
			return
		end

		if UI.activities_open then
			return
		end

		local mw = UI.minimized_strip_hit(cx, cy)
		if mw then
			mw.minimized = false
			window.Desktop.bring_to_front(UI.desk, mw)
			window.Desktop.set_focus(UI.desk, mw)
			UI.redraw()
			return
		end

		local win = UI.top_window_at(cx, cy)
		if win then
			local zone = window.hit_chrome(win, cx, cy)
			if zone == "close" then
				window.Desktop.remove(UI.desk, win)
				UI.redraw()
				return
			end
			if zone == "max" then
				UI.window_toggle_maximize(win)
				window.Desktop.bring_to_front(UI.desk, win)
				window.Desktop.set_focus(UI.desk, win)
				UI.redraw()
				return
			end
			if zone == "min" then
				UI.window_minimize(win)
				UI.redraw()
				return
			end
			if zone == "drag" then
				window.Desktop.bring_to_front(UI.desk, win)
				window.Desktop.set_focus(UI.desk, win)
				UI._drag = { win = win, offx = cx - win.x, offy = cy - win.y }
				UI.redraw()
				return
			end
			if zone == "client" then
				local rcx = cx - win:client_x()
				local rcy = cy - win:client_y()
				if win._appkit_shell and win._appkit_shell:handle_click(rcx, rcy, win) then
					window.Desktop.bring_to_front(UI.desk, win)
					window.Desktop.set_focus(UI.desk, win)
					UI.redraw()
					return
				end
				if type(win._atlas_client_click) == "function" and win._atlas_client_click(rcx, rcy) then
					window.Desktop.bring_to_front(UI.desk, win)
					window.Desktop.set_focus(UI.desk, win)
					UI.redraw()
					return
				end
				if win.title == "Settings" then
					for _, z in ipairs(UI._settings_zones or {}) do
						if rcx >= z.x0 and rcx <= z.x1 and rcy >= z.y0 and rcy <= z.y1 then
							UI.settings_dispatch(z.tag)
							window.Desktop.bring_to_front(UI.desk, win)
							window.Desktop.set_focus(UI.desk, win)
							UI.redraw()
							return
						end
					end
				end
				window.Desktop.bring_to_front(UI.desk, win)
				window.Desktop.set_focus(UI.desk, win)
				UI.redraw()
				return
			end
		end
	end
end

function UI.draw_taskbar()
	local t  = atlastheme.load()
	local tb = t.mode == "dark" and "black" or 22
	local fg = "bright_white"

	-- Rebuild gui_lib components when canvas dimensions or taskbar height change.
	local key = tostring(UI.W) .. ":" .. tostring(UI.H) .. ":" .. tostring(UI.TASKBAR_H)
	if not _tb_mgr or _tb_key ~= key then
		build_taskbar_gui()
		_tb_key = key
	end

	-- Clamp slot selection before the layout callback reads UI.taskbar_sel.
	local slots = UI.taskbar_slots_visible()
	if UI.taskbar_sel > #slots then UI.taskbar_sel = math.max(1, #slots) end

	-- Render bg strip, slot highlight panels, status / clock / world text.
	-- Assumption: gui_lib.GUIManager:draw() issues gfx_2d.rect/text calls without
	-- managing its own clear or batch — it therefore composites correctly inside the
	-- draw.begin_frame() / draw.end_frame() batch started by UI.redraw().
	_tb_mgr:update(0)
	_tb_mgr:draw()

	-- Overlay: start-button characters on top of start panel (no bg rect needed).
	local y0 = _tb_y0
	draw.text(3, y0, "[", fg, nil)
	draw.text(4, y0, "S", fg, nil)
	draw.text(5, y0, "]", fg, nil)

	-- Overlay: per-slot icon rows (multi-row, per-row colours via draw.text).
	for _, d in ipairs(_tb_icon_data) do
		if d.meta then
			for i = 1, d.nrows do
				local L   = d.lines[i] or ""
				local pad = math.max(0, math.floor((d.slot_w - #L) / 2))
				local ifg, ibg = gfx_icon_row_style(d.meta, i, fg, tb, d.sel)
				draw.text(d.sx + pad, d.y_icon + i - 1, L, ifg, ibg)
			end
		end
	end

	-- Overlay: search bar content (external API draws into the search region).
	UI.search_api().draw_taskbar(draw, {
		x      = 7,
		y0     = y0,
		sw     = _tb_search_w,
		th     = UI.TASKBAR_H,
		tb     = tb,
		fg     = fg,
		accent = 28,
	})
end

function UI.draw_start_menu()
	if not UI.start_open then return end
	local sm_key = UI.W .. ":" .. UI.H .. ":" .. UI.TASKBAR_H
	if _sm_mgr == nil or _sm_key ~= sm_key then
		build_start_menu_gui()
		_sm_key = sm_key
	end
	_sm_mgr:update(0)
	_sm_mgr:draw()
	-- Icon text overlays (same as taskbar: multi-row multi-color can't be pure Text component)
	for _, d in ipairs(_sm_tile_data) do
		local iw = d.tile_w - 2
		for r = 1, d.nrows do
			local ifg, ibg = gfx_icon_row_style(d.meta, r, "bright_white", 22, false)
			draw.text(d.tx + 1, d.row + r - 1, d.block[r], ifg, ibg)
		end
		-- label row below icon
		local lab = d.meta.label:sub(1, iw)
		local t = atlastheme.load()
		local panel_fg = t.mode == "dark" and "white" or "black"
		local panel_bg = t.mode == "dark" and "black" or "white"
		draw.text(d.tx + 1, d.row + d.nrows, lab .. string.rep(" ", iw - #lab), panel_fg, panel_bg)
	end
end

function UI.draw_activities_overlay()
	if not UI.activities_open then return end
	local mx = math.max(3, math.floor(UI.W * 0.04))
	local my = math.max(2, math.floor(UI.H * 0.06))
	local ow, oh = UI.W - 2 * mx, UI.H - 2 * my
	draw.fillRect(mx, my, ow, oh, "black")
	draw.rect(mx, my, ow, oh, 22)
	local ix = mx + 2
	local iy = my + 1
	draw.text(ix, iy, " Activities", "black", "white")
	draw.text(ix, iy + 2, "Search: ______", "black", "white")
	draw.text(ix, iy + 4, "Windows:", "black", "white")
	local row = iy + 6
	if UI.desk and UI.desk._windows then
		for _, w in ipairs(UI.desk._windows) do
			if row >= my + oh - 3 then break end
			local tag = w.minimized and " (min)" or ""
			draw.text(ix + 2, row, "- " .. (w.title or "Window") .. tag, "black", "white")
			row = row + 1
		end
	end
	draw.text(ix, my + oh - 2, "Esc when keys work", "black", "white")
end

function UI.redraw()
	draw.init()
	UI.update_size()
	UI._size_set(UI.W, UI.H)
	local pw, ph = draw.canvas_pixels_for_input()
	if pw and ph then
		input.set_canvas_pixels(pw, ph)
	end
	draw.begin_frame()
	local key = UI.W .. "x" .. UI.H
	if UI.desk and UI._canvas_key ~= key then
		UI.desk = nil
	end
	if not UI.desk then
		UI.build_desktop()
		UI._canvas_key = key
	end
	UI.search_step(24)
	local wx, wy, ww, wh = UI.workspace_rect()
	window.Desktop.paint_region(UI.desk, wx, wy, ww, wh)
	for _, w in ipairs(UI.desk._windows) do
		if not w.minimized then
			local paint = UI.paint_window_content[w.title]
			if paint then paint(w) end
		end
	end
	UI.draw_minimized_strip()
	UI.draw_taskbar()
	UI.draw_start_menu()
	UI.draw_activities_overlay()
	draw.end_frame()
end

function UI.toggle_activities()
	UI.activities_open = not UI.activities_open
	UI.redraw()
end

--- Focus the first window matching any of the titles (Guide vs legacy Welcome/Help).
function UI.focus_window_by_title_one_of(...)
	local order = { ... }
	if not UI.desk then return end
	for _, title in ipairs(order) do
		for _, w in ipairs(UI.desk._windows) do
			if w.title == title then
				w.minimized = false
				window.Desktop.bring_to_front(UI.desk, w)
				window.Desktop.set_focus(UI.desk, w)
				UI.redraw()
				return
			end
		end
	end
end

function UI.focus_window_by_title(title)
	if not UI.desk then return end
	for _, w in ipairs(UI.desk._windows) do
		if w.title == title then
			w.minimized = false
			window.Desktop.bring_to_front(UI.desk, w)
			window.Desktop.set_focus(UI.desk, w)
			UI.redraw()
			return
		end
	end
end

function UI.top_window_at(cx, cy)
	if not UI.desk or not UI.desk._windows then return nil end
	for i = #UI.desk._windows, 1, -1 do
		local w = UI.desk._windows[i]
		if not w.minimized and cx >= w.x and cy >= w.y and cx <= w.x + w.w - 1 and cy <= w.y + w.h - 1 then
			return w
		end
	end
	return nil
end

function UI.window_toggle_maximize(w)
	if not w or w.minimized then return end
	local wx, wy, ww, wh = UI.workspace_rect()
	if w.maximized then
		if w._restore then
			w.x, w.y, w.w, w.h = w._restore.x, w._restore.y, w._restore.w, w._restore.h
		end
		w.maximized = false
		w._restore = nil
	else
		w._restore = { x = w.x, y = w.y, w = w.w, h = w.h }
		w.x, w.y, w.w, w.h = wx, wy, ww, wh
		w.maximized = true
	end
end

function UI.window_minimize(w)
	if not w then return end
	if w.maximized and w._restore then
		w.x, w.y, w.w, w.h = w._restore.x, w._restore.y, w._restore.w, w._restore.h
		w.maximized = false
		w._restore = nil
	end
	w.minimized = true
	window.Desktop.focus_next(UI.desk)
end

function UI.draw_minimized_strip()
	UI._min_strip = {}
	if not UI.desk then return end
	local y0 = UI.H - UI.TASKBAR_H
	local has = false
	for _, w in ipairs(UI.desk._windows) do
		if w.minimized then
			has = true
			break
		end
	end
	if not has then return end
	local t = atlastheme.load()
	local bg = t.mode == "dark" and 235 or 252
	draw.fillRect(1, y0, UI.W, 1, bg)
	local x = 2
	draw.text(1, y0, " ", 28, bg)
	for _, w in ipairs(UI.desk._windows) do
		if w.minimized then
			local seg = "[" .. (w.title:sub(1, 12)) .. "]"
			if x + #seg > UI.W then break end
			draw.text(x, y0, seg, "bright_white", 22)
			UI._min_strip[#UI._min_strip + 1] = { w = w, x0 = x, x1 = x + #seg - 1 }
			x = x + #seg + 2
		end
	end
end

function UI.minimized_strip_hit(cx, cy)
	local y0 = UI.H - UI.TASKBAR_H
	if cy ~= y0 then return nil end
	for _, r in ipairs(UI._min_strip or {}) do
		if cx >= r.x0 and cx <= r.x1 then return r.w end
	end
	return nil
end

function UI.focus_next_window()
	if not UI.desk then return end
	window.Desktop.focus_next(UI.desk)
	UI.redraw()
end

function UI.files_set_dir(path)
	path = paths.normalize(path or "/home")
	if paths.is_AtlasOS_tree(path) and not UI.developer_mode_enabled() then
		_G.AtlasOS_log = _G.AtlasOS_log or {}
		_G.AtlasOS_log[#_G.AtlasOS_log + 1] =
		"[Files] /home/AtlasOS is hidden. Use /home/apps or enable Developer mode."
		path = "/home"
	end
	UI.files_dir = path
	UI.redraw()
end

function UI.boot()
	if not _G.AtlasOS_log then _G.AtlasOS_log = {} end
	if paths.is_AtlasOS_tree(paths.normalize(UI.files_dir or "")) and not UI.developer_mode_enabled() then
		UI.files_dir = "/home"
	end
	UI.build_desktop()
	UI.redraw()
end

--- True when a focused control should receive typing (Editor, future search field, …).
--- Optional: set UI.extra_input_text_active = function() return bool end
function UI.input_text_active()
	if type(UI.extra_input_text_active) == "function" and UI.extra_input_text_active() then
		return true
	end
	local d = UI.desk
	if not d then return false end
	local fw = window.Desktop.focused(d)
	if not fw or fw.minimized then return false end
	if fw.title == "Editor" then return true end
	if type(fw._atlas_input_text_active) == "function" and fw._atlas_input_text_active() then
		return true
	end
	return false
end

--- Keys that only make sense in a text field; cancel via input.cancelKeyEvent when not editing.
local function key_expects_text_target(e)
	if e.type ~= "key" then return false end
	if e.ctrl or e.alt then return false end
	if type(e.char) == "string" and e.char ~= "" then
		local b = string.byte(e.char, 1)
		if b and b >= 32 then return true end
	end
	local k = tonumber(e.key) or 0
	if k == 14 or k == 259 then return true end
	if k == 261 then return true end
	return false
end

--- Run input loop (blocking). Polls mod input, handles key/mouse, redraws on events.
function UI.run_loop()
	input.consumeKeyboard()
	local ok, err = pcall(function()
		UI.redraw()
		while true do
			local events = input.poll_all()
			if #events == 0 then input.idle(8) end
			for _, ev in ipairs(events) do
				if not ev then
				elseif ev.type == "key" and key_expects_text_target(ev) and not UI.input_text_active() then
					input.cancelKeyEvent(ev)
				else
					UI.handle_event(ev)
				end
			end
			if #events > 0 then UI.redraw() end
		end
	end)
	input.releaseKeyboard()
	if not ok then error(err) end
end

return UI
