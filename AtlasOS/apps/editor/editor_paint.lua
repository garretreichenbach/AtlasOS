--[[ Editor window + runapp entry (same file). ]]
local CACHE = "__AtlasOS_editor_factory"
local factory = _G[CACHE]
if not factory then
  factory = function(ctx)
  local UI = ctx.UI
  local window = ctx.window
  local widgets = ctx.widgets

  return function(win)
    UI.editor_ensure()
    local st = UI._editor
    local cw, ch = win:client_w(), win:client_h()
    if ch < 3 then return end

    local dirty = st.dirty and " *" or ""
    local p = st.path or "?"
    if #p + #dirty > cw - 14 then
      p = "…" .. p:sub(math.max(1, #p - cw + 18))
    end
    local status = p .. dirty .. "  L" .. st.cur_line .. ":" .. (st.cur_col + 1) .. "  ^S save"
    if #status > cw then status = status:sub(1, cw) end
    window.draw_text_line(win, 0, 0, status)
    widgets.hrule(win, 1, "-")

    local body_h = ch - 2
    local scroll = st.scroll or 1
    while st.cur_line < scroll do
      scroll = scroll - 1
    end
    while st.cur_line > scroll + body_h - 1 do
      scroll = scroll + 1
    end
    st.scroll = scroll

    gfx.setColor(win.client_fg, win.client_bg)
    local focused = win.focused

    for r = 0, body_h - 1 do
      local ln = scroll + r
      local L = st.lines[ln] or ""
      local prefix = (ln == st.cur_line and focused) and ">" or " "
      local budget = cw - #prefix
      local disp = L
      if ln == st.cur_line and focused and budget >= 2 then
        local c = math.min(st.cur_col, #L)
        disp = L:sub(1, c) .. "|" .. L:sub(c + 1)
      end
      if #disp > budget then disp = disp:sub(1, budget) end
      local line = prefix .. disp
      gfx.text(win:client_x(), win:client_y() + 2 + r, line .. string.rep(" ", cw - #line))
    end
  end
  end
  _G[CACHE] = factory
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "editor" then
  local app = _G.AtlasOS_APP
  local path = app and app.args and app.args[1]
  if type(_G.AtlasOS_editor_open) == "function" then
    _G.AtlasOS_editor_open(path)
    print(path and ("Editor: " .. path) or "Editor window")
  else
    print("Editor — run desktop, then open from Start menu.")
    if path then print("  (path ignored until desktop is running)") end
  end
end
return factory
