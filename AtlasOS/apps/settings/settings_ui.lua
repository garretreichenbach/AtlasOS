--[[ Settings window + runapp entry (same file). ]]
local CACHE = "__AtlasOS_settings_factory"
local factory = _G[CACHE]
if not factory then
  factory = function(ctx)
  local UI = ctx.UI
  local window = ctx.window
  local widgets = ctx.widgets
  local atlastheme = ctx.atlastheme
  local VERSION = ctx.VERSION or "0"
  local appkit = dofile("/home/lib/appkit.lua")
  local draw = dofile("/home/lib/atlas_draw.lua")
  local atlas_color = dofile("/home/lib/atlas_color.lua")

  local CW = draw.cell_w
  local CH = draw.cell_h
  local function C(token) return atlas_color.resolve(token) end

  local CATS = {
    { id = "system", label = "System" },
    { id = "personalization", label = "Personalization" },
    { id = "apps", label = "Apps" },
    { id = "developer", label = "Developer" },
    { id = "about", label = "About" },
  }

  local view_items = {}
  for _, c in ipairs(CATS) do
    view_items[#view_items + 1] = { label = c.label, id = "cat:" .. c.id }
  end

  -- Module-level persistent state for gui_lib components
  local _sg_mgr, _sg_key, _sg_win, _sg_yB, _sg_btn_data, _sg_div = nil, nil, nil, 0, {}, {}
  local _sg_cat_panels, _sg_cat_texts, _sg_abtns = {}, {}, {}

  local function build_settings_gui()
    local P = gui_lib.Panel
    local T = gui_lib.Text
    local B = gui_lib.Button
    local mgr = gui_lib.GUIManager.new()
    mgr:setBackgroundColor(0, 0, 0, 0)

    _sg_cat_panels = {}
    _sg_cat_texts = {}
    for i = 1, #CATS do
      _sg_cat_panels[i] = P.new(0, 0, 0, 0)
      _sg_cat_panels[i]:setBorderColor(0, 0, 0, 0)
      mgr:addComponent(_sg_cat_panels[i])

      _sg_cat_texts[i] = T.new(0, 0, "")
      _sg_cat_texts[i]:setScale(1)
      mgr:addComponent(_sg_cat_texts[i])
    end

    _sg_abtns = {}
    for i = 1, 4 do
      _sg_abtns[i] = B.new(0, 0, 0, 0, "", function() end)
      mgr:addComponent(_sg_abtns[i])
    end

    mgr:setLayoutCallback(function(m, _pw, _ph)
      local win = _sg_win
      if not win then return end
      local yB = _sg_yB

      -- Position category sidebar
      local cw, ch = win:client_w(), win:client_h()
      local LW = math.max(12, math.min(20, math.floor(cw * 0.32)))
      if cw - LW - 2 < 14 then
        LW = math.max(10, cw - 16)
      end
      local cx = win:client_x()
      local cy = win:client_y()
      local DIV = LW

      _sg_div = { x = (cx + DIV) * CW, y1 = (cy + yB) * CH, y2 = (cy + ch - 1) * CH }

      local row = yB + 2
      for i, c in ipairs(CATS) do
        if row >= ch - 1 then
          _sg_cat_panels[i]:setVisible(false)
          _sg_cat_texts[i]:setVisible(false)
        else
          local sel = (UI._settings_cat == c.id)
          _sg_cat_panels[i]:setVisible(sel)
          if sel then
            _sg_cat_panels[i]:setPosition(cx * CW, (cy + row) * CH)
            _sg_cat_panels[i]:setSize(LW * CW, CH)
            _sg_cat_panels[i]:setBackgroundColor(C("bright_white"))
          end

          local lfg = sel and "black" or win.client_fg
          local text_str = c.label
          _sg_cat_texts[i]:setText(text_str)
          _sg_cat_texts[i]:setColor(C(lfg))
          if sel then
            _sg_cat_texts[i]:setBackgroundColor(C("bright_white"))
          else
            _sg_cat_texts[i]:setBackgroundColor(C(win.client_bg))
          end
          _sg_cat_texts[i]:setPosition((cx + 1) * CW, (cy + row) * CH)
          _sg_cat_texts[i]:setVisible(true)
          row = row + 1
        end
      end

      -- Position action buttons from _sg_btn_data
      for i = 1, 4 do
        if i <= #_sg_btn_data then
          local bd = _sg_btn_data[i]
          _sg_abtns[i]:setVisible(true)
          _sg_abtns[i]:setPosition((cx + bd.col) * CW, (cy + bd.row) * CH)
          _sg_abtns[i]:setSize(bd.w * CW, CH)
          _sg_abtns[i]:setLabel(bd.label)
          _sg_abtns[i]:setNormalColor(C(win.client_bg))
          _sg_abtns[i]:setOnPress(function()
            UI.settings_dispatch(bd.tag)
          end)
        else
          _sg_abtns[i]:setVisible(false)
        end
      end
    end)

    _sg_mgr = mgr
  end

  local shell = appkit.shell({
    on_command = function(id)
      UI.settings_dispatch(id)
    end,
  })
  shell:set_menubar({
    { label = "View", items = view_items },
    {
      label = "Actions",
      items = {
        { label = "Save layout", id = "cmd:save_layout" },
        { label = "Reload apps", id = "cmd:reload_apps" },
      },
    },
  })
  shell:set_toolbar({
    { label = "Save", id = "cmd:save_layout", w = 8 },
    { label = "Reload", id = "cmd:reload_apps", w = 10 },
  })

  return function(win)
    if not UI._settings_cat then UI._settings_cat = "system" end
    UI._settings_zones = {}

    local function add_zone(x0, y0, x1, y1, tag)
      UI._settings_zones[#UI._settings_zones + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, tag = tag }
    end

    local cw, ch = win:client_w(), win:client_h()
    if cw < 14 or ch < 6 then
      window.draw_text_line(win, 0, 0, "Resize Settings window")
      return
    end

    shell:attach(win)
    shell:paint_decorations(win)
    local yB = shell:content_row()
    if yB + 4 > ch then
      shell:paint_dropdown(win)
      return
    end

    local LW = math.max(12, math.min(20, math.floor(cw * 0.32)))
    local DIV = LW
    local R0 = LW + 2
    local RW = cw - R0
    if RW < 14 then
      LW = math.max(10, cw - 16)
      R0 = LW + 2
      RW = cw - R0
    end

    window.draw_text_line(win, 1, yB, "Settings", "bright_white")

    local row = yB + 2
    for _, c in ipairs(CATS) do
      if row >= ch - 1 then break end
      add_zone(0, row, LW - 1, row, "cat:" .. c.id)
      row = row + 1
    end

    -- Set upvalues for layout callback
    _sg_win = win
    _sg_yB = yB

    -- Rebuild if needed
    local sg_key = cw .. ":" .. ch .. ":" .. yB
    if _sg_mgr == nil or _sg_key ~= sg_key then
      build_settings_gui()
      _sg_key = sg_key
    end

    _sg_btn_data = {}

    local cat = UI._settings_cat
    local rr = yB + 1
    local t = atlastheme.load()
    local mode = (t and t.mode) or "light"
    local dev = UI.developer_mode_enabled()

    local function hdr(s)
      window.draw_text_line(win, R0, rr, (s or ""):sub(1, RW), "bright_white")
      rr = rr + 1
    end

    local function ln(s)
      if rr >= ch - 1 then return end
      window.draw_text_line(win, R0, rr, tostring(s or ""):sub(1, RW))
      rr = rr + 1
    end

    local function btn(col, row, w, label, tag)
      if row >= ch - 1 then return end
      table.insert(_sg_btn_data, { col = col, row = row, w = w, label = label, tag = tag })
      add_zone(col, row, col + w - 1, row, tag)
    end

    if cat == "system" then
      hdr("System")
      ln("")
      ln("Device name")
      ln(UI.device_name and UI.device_name() or "—")
      ln("")
      ln("AtlasOS desktop — taskbar, Start, windows.")
    elseif cat == "personalization" then
      hdr("Personalization")
      ln("")
      ln("Choose your mode (refreshes desktop).")
      ln("Current: " .. mode)
      ln("")
      if R0 + 29 < cw then
        btn(R0, rr, 14, mode == "light" and "[* Light *]" or "[  Light  ]", "theme:light")
        btn(R0 + 15, rr, 14, mode == "dark" and "[* Dark *]" or "[  Dark  ]", "theme:dark")
        rr = rr + 1
      else
        btn(R0, rr, 14, mode == "light" and "[* Light *]" or "[  Light  ]", "theme:light")
        rr = rr + 1
        btn(R0, rr, 14, mode == "dark" and "[* Dark *]" or "[  Dark  ]", "theme:dark")
        rr = rr + 1
      end
      ln("")
      ln("gfx.conf: cell_scale (bitmap text size)")
    elseif cat == "apps" then
      hdr("Apps")
      ln("")
      ln("Packages in /home/apps/ (APPINFO.md).")
      ln("")
      btn(R0, rr, 22, "[ Open /home/apps ]", "nav:apps")
      rr = rr + 1
      btn(R0, rr, 22, "[ Reload app list ]", "cmd:reload_apps")
      ln("")
      ln("System apps: /home/AtlasOS (Dev mode).")
    elseif cat == "developer" then
      hdr("Developer")
      ln("")
      ln("Shows /home/AtlasOS in Files.")
      ln("")
      btn(R0, rr, 28, dev and "[ Developer: ON ]" or "[ Developer: OFF ]", "dev:toggle")
      ln("")
      ln("Off for players who must not edit system files.")
    elseif cat == "about" then
      hdr("About")
      ln("")
      ln("AtlasOS " .. tostring(VERSION))
      ln("Custom OS for LuaMade Computers.")
      ln("")
      btn(R0, rr, 18, "[ Save layout ]", "cmd:save_layout")
    end

    -- Render sidebar gui_lib components
    _sg_mgr:update(0)

    -- Draw vertical divider line
    if _sg_div and _sg_div.x then
      local r, g, b, a = C(win.client_fg)
      gfx_2d.line(_sg_div.x, _sg_div.y1, _sg_div.x, _sg_div.y2, r, g, b, a)
    end

    _sg_mgr:draw()

    shell:paint_dropdown(win)
  end
  end
  _G[CACHE] = factory
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "settings" then
  print("Settings — run: theme  save_layout  |  open Settings window")
end
return factory
