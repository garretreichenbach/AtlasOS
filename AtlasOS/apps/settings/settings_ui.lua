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
    local draw = dofile("/home/lib/atlas_draw.lua")
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

    local cx0, cy0 = win:client_x(), win:client_y()

    for r = yB, ch - 1 do
      draw.text(cx0 + DIV, cy0 + r, "│", win.client_fg, win.client_bg)
    end

    window.draw_text_line(win, 1, yB, "Settings", "bright_white")

    local row = yB + 2
    for _, c in ipairs(CATS) do
      if row >= ch - 1 then break end
      local sel = (UI._settings_cat == c.id)
      local lfg = sel and "black" or win.client_fg
      local lbg = sel and "bright_white" or win.client_bg
      if sel then draw.fillRect(cx0, cy0 + row, LW, 1, "bright_white") end
      local line = (sel and "│ " or "  ") .. c.label
      line = line .. string.rep(" ", math.max(0, LW - #line))
      if #line > LW then line = line:sub(1, LW) end
      draw.text(cx0, cy0 + row, line, lfg, lbg)
      add_zone(0, row, LW - 1, row, "cat:" .. c.id)
      row = row + 1
    end

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
      widgets.button(win, col, row, w, label)
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

    shell:paint_dropdown(win)
  end
  end
  _G[CACHE] = factory
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "settings" then
  print("Settings — run: theme  save_layout  |  open Settings window")
end
return factory
