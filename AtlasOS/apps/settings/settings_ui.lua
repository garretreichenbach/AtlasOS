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

  local CATS = {
    { id = "system", label = "System" },
    { id = "personalization", label = "Personalization" },
    { id = "apps", label = "Apps" },
    { id = "developer", label = "Developer" },
    { id = "about", label = "About" },
  }

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
    gfx.setColor(win.client_fg, win.client_bg)

    for r = 0, ch - 1 do
      gfx.text(cx0 + DIV, cy0 + r, "│")
    end

    gfx.setColor("bright_white", win.client_bg)
    window.draw_text_line(win, 1, 0, "Settings")
    gfx.setColor(win.client_fg, win.client_bg)

    local row = 2
    for _, c in ipairs(CATS) do
      if row >= ch - 1 then break end
      local sel = (UI._settings_cat == c.id)
      if sel then
        gfx.setColor("black", "bright_white")
        gfx.fillRect(cx0, cy0 + row, LW, 1, " ")
      else
        gfx.setColor(win.client_fg, win.client_bg)
      end
      local line = (sel and "│ " or "  ") .. c.label
      line = line .. string.rep(" ", math.max(0, LW - #line))
      if #line > LW then line = line:sub(1, LW) end
      gfx.text(cx0, cy0 + row, line)
      add_zone(0, row, LW - 1, row, "cat:" .. c.id)
      gfx.setColor(win.client_fg, win.client_bg)
      row = row + 1
    end

    local cat = UI._settings_cat
    local rr = 1
    local t = atlastheme.load()
    local mode = (t and t.mode) or "light"
    local dev = UI.developer_mode_enabled()

    local function hdr(s)
      gfx.setColor("bright_white", win.client_bg)
      window.draw_text_line(win, R0, rr, (s or ""):sub(1, RW))
      gfx.setColor(win.client_fg, win.client_bg)
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
      ln("gfx.conf: cell_scale, icon_pixel_scale")
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
  end
  end
  _G[CACHE] = factory
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "settings" then
  print("Settings — run: theme  save_layout  |  open Settings window")
end
return factory
