--[[
  appkit — menu bar, dropdowns, and toolbar strip for AtlasOS window client areas.
  Uses client-relative coords (0-based column/row like window.draw_text_line).

  1) dofile("/home/lib/appkit.lua")
  2) shell = appkit.shell({ on_command = function(id, ctx) ... end })
  3) shell:set_menubar({ { label = "File", items = { { label = "New", id = "new" } } }, ... })
  4) shell:set_toolbar({ { label = "Save", id = "save", w = 8 }, ... })  -- optional
  5) paint(win): shell:attach(win); shell:paint_decorations(win); draw app body from
     row shell:content_row() (0-based); shell:paint_dropdown(win) last (menu overlaps hrule).
  6) Desktop sends clicks when win._appkit_shell is set (see ui.lua).

  ctx in on_command: { source = "menubar" | "toolbar", menu_index?, item_label? }
]]

local atlasgfx = dofile("/home/lib/atlasgfx.lua")
local widgets = dofile("/home/lib/widgets.lua")

local appkit = {}

local function clamp(s, maxc)
  s = tostring(s or "")
  if #s <= maxc then return s end
  return s:sub(1, math.max(0, maxc - 1)) .. "…"
end

function appkit.shell(opts)
  opts = opts or {}
  local self = {
    on_command = opts.on_command,
    menubar = opts.menubar or {},
    toolbar = opts.toolbar or {},
    open_menu = nil,
    _menu_layout = {},
    _dropdown_rect = nil,
    _bar_zones = {},
    _tb_zones = {},
    _dd_zones = {},
    menubar_bg = opts.menubar_bg or 235,
    menubar_fg = opts.menubar_fg or "bright_white",
    toolbar_bg = opts.toolbar_bg or 252,
    toolbar_fg = opts.toolbar_fg or "black",
    dd_bg = opts.dropdown_bg or "white",
    dd_fg = opts.dropdown_fg or "black",
    dd_border = opts.dropdown_border or 22,
    dd_sel_bg = opts.dropdown_sel_bg or "bright_white",
    dd_sel_fg = opts.dropdown_sel_fg or "black",
  }

  function self:set_menubar(menus)
    self.menubar = menus or {}
    self.open_menu = nil
  end

  function self:set_toolbar(buttons)
    self.toolbar = buttons or {}
  end

  function self:blur()
    self.open_menu = nil
    self._dropdown_rect = nil
  end

  function self:attach(win, o)
    o = o or {}
    if o.on_command then self.on_command = o.on_command end
    win._appkit_shell = self
    win._appkit_on_command = o.on_command or self.on_command
  end

  --- First client row available for app content (0-based).
  function self:content_row()
    local n = 1
    if self.menubar and #self.menubar > 0 then n = n + 1 end
    if self.toolbar and #self.toolbar > 0 then n = n + 1 end
    return n
  end

  --- Visible client rows below header rule.
  function self:content_height(win)
    local ch = win:client_h()
    return math.max(0, ch - self:content_row())
  end

  local function layout_menubar(self, win)
    self._menu_layout = {}
    self._bar_zones = {}
    local cw = win:client_w()
    if cw < 1 or not self.menubar or #self.menubar == 0 then return 0 end
    local x = 0
    local row = 0
    local cy0 = win:client_y()
    local cx0 = win:client_x()
    atlasgfx.setColor(self.menubar_fg, self.menubar_bg)
    atlasgfx.fillRect(cx0, cy0 + row, cw, 1, " ")
    for i, m in ipairs(self.menubar) do
      local lab = " " .. clamp(m.label, 20) .. " "
      if x + #lab > cw then break end
      atlasgfx.text(cx0 + x, cy0 + row, lab)
      self._menu_layout[i] = { x0 = x, x1 = x + #lab - 1, label = m.label }
      self._bar_zones[#self._bar_zones + 1] = {
        x0 = x,
        y0 = row,
        x1 = x + #lab - 1,
        y1 = row,
        kind = "title",
        menu_index = i,
      }
      x = x + #lab
    end
    return 1
  end

  local function layout_toolbar(self, win, start_row)
    self._tb_zones = {}
    if not self.toolbar or #self.toolbar == 0 then return start_row end
    local row = start_row
    local cw, ch = win:client_w(), win:client_h()
    if row >= ch then return start_row end
    local cx0, cy0 = win:client_x(), win:client_y()
    atlasgfx.setColor(self.toolbar_fg, self.toolbar_bg)
    atlasgfx.fillRect(cx0, cy0 + row, cw, 1, " ")
    local x = 0
    for _, b in ipairs(self.toolbar) do
      local w = math.max(3, math.floor(b.w or (#tostring(b.label or "") + 4)))
      if x + w > cw then break end
      widgets.button(win, x, row, w, clamp(b.label, w - 2), self.toolbar_fg, self.toolbar_bg)
      self._tb_zones[#self._tb_zones + 1] = {
        x0 = x,
        y0 = row,
        x1 = x + w - 1,
        y1 = row,
        id = b.id,
      }
      x = x + w + 1
    end
    return start_row + 1
  end

  --- Draw menubar, optional toolbar, horizontal rule. Call first each paint.
  function self:paint_decorations(win)
    self._dd_zones = {}
    self._dropdown_rect = nil
    local row = 0
    if self.menubar and #self.menubar > 0 then
      layout_menubar(self, win)
      row = row + 1
    end
    row = layout_toolbar(self, win, row)
    local ch = win:client_h()
    if row < ch then
      atlasgfx.setColor(win.client_fg, win.client_bg)
      widgets.hrule(win, row, "-")
    end
  end

  --- Draw open menu dropdown on top (call after app content). Updates hit zones for items.
  function self:paint_dropdown(win)
    self._dd_zones = {}
    local mi = self.open_menu
    if not mi or not self.menubar[mi] then return end
    local m = self.menubar[mi]
    local items = m.items or {}
    if #items == 0 then return end
    local lay = self._menu_layout[mi]
    if not lay then return end

    local maxw = 0
    for _, it in ipairs(items) do
      maxw = math.max(maxw, #tostring(it.label or ""))
    end
    maxw = math.min(maxw + 4, win:client_w() - lay.x0)
    local box_w = math.max(8, maxw)
    local box_h = #items + 2
    local x0 = lay.x0
    -- First row after menu+toolbar: hrule row (dropdown draws over the rule, not app body).
    local y0 = math.max(0, self:content_row() - 1)
    if y0 + box_h > win:client_h() then
      box_h = math.max(3, win:client_h() - y0)
    end

    local cx0, cy0 = win:client_x(), win:client_y()
    atlasgfx.setColor(self.dd_border, self.dd_bg)
    atlasgfx.rect(cx0 + x0, cy0 + y0, box_w, box_h, "#")
    for i, it in ipairs(items) do
      if i + 1 >= box_h then break end
      local line = " " .. clamp(it.label, box_w - 2)
      line = line .. string.rep(" ", math.max(0, box_w - #line))
      atlasgfx.setColor(self.dd_fg, self.dd_bg)
      atlasgfx.text(cx0 + x0, cy0 + y0 + i, line:sub(1, box_w))
      self._dd_zones[#self._dd_zones + 1] = {
        x0 = x0,
        y0 = y0 + i,
        x1 = x0 + box_w - 1,
        y1 = y0 + i,
        id = it.id,
        label = it.label,
        menu_index = mi,
      }
    end
    self._dropdown_rect = { x0 = x0, y0 = y0, x1 = x0 + box_w - 1, y1 = y0 + box_h - 1 }
  end

  local function in_z(z, rcx, rcy)
    return rcx >= z.x0 and rcx <= z.x1 and rcy >= z.y0 and rcy <= z.y1
  end

  --- Handle a left press in client coords; returns true if consumed.
  function self:handle_click(rcx, rcy, win)
    local handler = win._appkit_on_command or self.on_command

    for _, z in ipairs(self._bar_zones) do
      if in_z(z, rcx, rcy) and z.kind == "title" then
        if self.open_menu == z.menu_index then
          self:blur()
        else
          self.open_menu = z.menu_index
        end
        return true
      end
    end

    for _, z in ipairs(self._tb_zones) do
      if in_z(z, rcx, rcy) and z.id then
        self:blur()
        if handler then handler(z.id, { source = "toolbar" }) end
        return true
      end
    end

    for _, z in ipairs(self._dd_zones) do
      if in_z(z, rcx, rcy) and z.id then
        if handler then
          handler(z.id, {
            source = "menubar",
            menu_index = z.menu_index,
            item_label = z.label,
          })
        end
        self:blur()
        return true
      end
    end

    if self.open_menu and self._dropdown_rect then
      local r = self._dropdown_rect
      if rcx < r.x0 or rcx > r.x1 or rcy < r.y0 or rcy > r.y1 then
        self:blur()
      end
    end

    return false
  end

  return self
end

return appkit
