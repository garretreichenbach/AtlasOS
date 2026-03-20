--[[
  Cell-grid UI drawing for LuaMade bitmap gfx (pixel coords + rgba rects).
  https://garretreichenbach.github.io/Logiscript/markdown/graphics/gfx.html

  Current API: gfx.rect, gfx.point, gfx.line, gfx.setCanvasSize, gfx.getWidth/getHeight,
  gfx.clear, gfx.setLayer, gfx.createLayer, gfx.clearLayer.
  Legacy text-cell methods (fillRect, text, setColor, render, setAnsiEnabled, setSize)
  have been removed from the API; those paths in this module are no-ops.
]]

if _G.__AtlasGFX then
  return _G.__AtlasGFX
end

local FONT = dofile("/home/lib/font8x8_basic.lua")

local atlasgfx = {
  _bitmap = false,
  cell_w = 8,
  cell_h = 14,
  layer = "atlas",
  fg = { 1, 1, 1, 1 },
  bg = { 0, 0, 0, 1 },
}

local function probe_bitmap_gfx()
  if not gfx or type(gfx.rect) ~= "function" then return false end
  local ok = pcall(function()
    gfx.rect(0, 0, 1, 1, 0, 0, 0, 1, true)
  end)
  return ok
end

local NAMED = {
  black = { 0.02, 0.02, 0.02, 1 },
  red = { 0.75, 0.12, 0.12, 1 },
  green = { 0.15, 0.72, 0.2, 1 },
  yellow = { 0.92, 0.86, 0.2, 1 },
  blue = { 0.22, 0.4, 0.88, 1 },
  magenta = { 0.82, 0.22, 0.75, 1 },
  cyan = { 0.15, 0.82, 0.88, 1 },
  white = { 0.88, 0.88, 0.88, 1 },
  bright_black = { 0.35, 0.35, 0.38, 1 },
  bright_red = { 1, 0.35, 0.35, 1 },
  bright_green = { 0.35, 1, 0.45, 1 },
  bright_yellow = { 1, 1, 0.45, 1 },
  bright_blue = { 0.45, 0.55, 1, 1 },
  bright_magenta = { 1, 0.45, 1, 1 },
  bright_cyan = { 0.45, 1, 1, 1 },
  bright_white = { 1, 1, 1, 1 },
}

local NUM = {
  [22] = { 0.35, 0.38, 0.95, 1 },
  [28] = { 0.22, 0.88, 0.28, 1 },
  [235] = { 0.12, 0.12, 0.14, 1 },
  [252] = { 0.93, 0.93, 0.94, 1 },
}

local function color_to_rgba(c, fallback)
  if type(c) == "string" then
    return NAMED[c] or fallback
  end
  if type(c) == "number" then
    local n = math.floor(c)
    if NUM[n] then return NUM[n] end
    if n >= 232 and n <= 255 then
      local gmi = (n - 232) / 23
      return { gmi, gmi, gmi, 1 }
    end
  end
  return fallback
end

local function bit_pixel(byte, col)
  return math.floor(byte / 2 ^ (7 - col)) % 2
end

function atlasgfx.init(conf)
  conf = conf or {}
  local is_new = probe_bitmap_gfx()
  atlasgfx._bitmap = is_new and true or false
  local sc = tonumber(conf.cell_scale) or 1
  sc = math.max(0.5, math.min(4, sc))
  atlasgfx.cell_w = math.max(4, math.floor(8 * sc + 0.5))
  atlasgfx.cell_h = math.max(6, math.floor(14 * sc + 0.5))
  if atlasgfx._bitmap and gfx and type(gfx.createLayer) == "function" and not atlasgfx._layer_ready then
    pcall(gfx.createLayer, atlasgfx.layer, 0)
    atlasgfx._layer_ready = true
  end
  if not atlasgfx._bitmap then
    atlasgfx._layer_ready = false
  end
end

function atlasgfx.is_bitmap()
  return atlasgfx._bitmap == true
end

function atlasgfx.set_canvas_from_cells(cols, rows)
  cols = math.max(1, math.floor(cols or 80))
  rows = math.max(1, math.floor(rows or 24))
  local pw = cols * atlasgfx.cell_w
  local ph = rows * atlasgfx.cell_h
  if atlasgfx._bitmap and gfx and type(gfx.setCanvasSize) == "function" then
    pcall(gfx.setCanvasSize, pw, ph)
  end
  return pw, ph
end

function atlasgfx.canvas_cells()
  if not gfx or type(gfx.getWidth) ~= "function" then return nil, nil end
  local ok, gw, gh = pcall(function()
    return gfx.getWidth(), gfx.getHeight()
  end)
  if not ok or type(gw) ~= "number" then return nil, nil end
  if atlasgfx._bitmap then
    local cw = atlasgfx.cell_w > 0 and gw / atlasgfx.cell_w or gw
    local ch = atlasgfx.cell_h > 0 and gh / atlasgfx.cell_h or gh
    return math.max(8, math.floor(cw)), math.max(8, math.floor(ch))
  end
  return math.floor(gw), math.floor(gh)
end

function atlasgfx.canvas_pixels_for_input()
  if not gfx then return nil, nil end
  local ok, gw, gh = pcall(function()
    return gfx.getWidth(), gfx.getHeight()
  end)
  if ok and gw and gh and gw > 0 and gh > 0 then return gw, gh end
  return nil, nil
end

function atlasgfx.begin_frame()
  if not gfx then return end
  if atlasgfx._bitmap then
    if type(gfx.clear) == "function" then pcall(gfx.clear) end
    if type(gfx.setLayer) == "function" then pcall(gfx.setLayer, atlasgfx.layer) end
  end
end

function atlasgfx.end_frame()
  -- gfx.render removed in current API; rendering is automatic.
end

function atlasgfx.cell_to_pixel(cx, cy)
  return (math.floor(cx or 1) - 1) * atlasgfx.cell_w, (math.floor(cy or 1) - 1) * atlasgfx.cell_h
end

--- Mouse / uiX uiY (canvas pixels, origin top-left) → 1-based cell index.
function atlasgfx.pixel_to_cell_rel(px, py)
  local cx = math.floor((tonumber(px) or 0) / atlasgfx.cell_w) + 1
  local cy = math.floor((tonumber(py) or 0) / atlasgfx.cell_h) + 1
  return cx, cy
end

function atlasgfx.setColor(fg, bg)
  if not atlasgfx._bitmap then
    -- gfx.setColor removed in current API; no-op.
    return
  end
  atlasgfx.fg = color_to_rgba(fg, atlasgfx.fg)
  atlasgfx.bg = color_to_rgba(bg, atlasgfx.bg)
end

function atlasgfx.fillRect(x, y, w, h, _)
  if not atlasgfx._bitmap then
    -- gfx.fillRect removed in current API; no-op.
    return
  end
  x, y, w, h = math.floor(x or 1), math.floor(y or 1), math.floor(w or 1), math.floor(h or 1)
  if w < 1 or h < 1 then return end
  local px, py = atlasgfx.cell_to_pixel(x, y)
  local pw, ph = w * atlasgfx.cell_w, h * atlasgfx.cell_h
  local r, g, b, a = atlasgfx.bg[1], atlasgfx.bg[2], atlasgfx.bg[3], atlasgfx.bg[4]
  pcall(gfx.rect, px, py, pw, ph, r, g, b, a, true)
end

function atlasgfx.rect(x, y, w, h, _)
  if not atlasgfx._bitmap then
    -- Legacy text-cell path; no-op in current API.
    return
  end
  x, y, w, h = math.floor(x or 1), math.floor(y or 1), math.floor(w or 1), math.floor(h or 1)
  if w < 2 or h < 2 then return end
  local px, py = atlasgfx.cell_to_pixel(x, y)
  local pw, ph = w * atlasgfx.cell_w, h * atlasgfx.cell_h
  local r, g, b, a = atlasgfx.fg[1], atlasgfx.fg[2], atlasgfx.fg[3], atlasgfx.fg[4]
  pcall(gfx.rect, px, py, pw, ph, r, g, b, a, false)
end

function atlasgfx.text(x, y, str)
  if not atlasgfx._bitmap then
    -- gfx.text removed in current API; no-op.
    return
  end
  str = tostring(str or "")
  x, y = math.floor(x or 1), math.floor(y or 1)
  local rf, gf, bf, af = atlasgfx.fg[1], atlasgfx.fg[2], atlasgfx.fg[3], atlasgfx.fg[4]
  local br, bgc, bb, ba = atlasgfx.bg[1], atlasgfx.bg[2], atlasgfx.bg[3], atlasgfx.bg[4]
  local scale = math.min(atlasgfx.cell_w / 8, atlasgfx.cell_h / 8)
  scale = math.max(1, math.floor(scale))
  for i = 1, #str do
    local col = x + i - 1
    local px, py = atlasgfx.cell_to_pixel(col, y)
    pcall(gfx.rect, px, py, atlasgfx.cell_w, atlasgfx.cell_h, br, bgc, bb, ba, true)
    local byte = str:byte(i) or 32
    if byte < 0 or byte > 127 then byte = 63 end
    local g = FONT[byte + 1]
    if g then
      local ox = px + math.floor((atlasgfx.cell_w - 8 * scale) / 2)
      local oy = py + math.floor((atlasgfx.cell_h - 8 * scale) / 2)
      for row = 1, 8 do
        local bits = g[row]
        for colp = 0, 7 do
          if bit_pixel(bits, colp) == 1 then
            pcall(gfx.rect, ox + colp * scale, oy + (row - 1) * scale, scale, scale, rf, gf, bf, af, true)
          end
        end
      end
    end
  end
end

function atlasgfx.setAnsiEnabled(on)
  -- gfx.setAnsiEnabled removed in current API; no-op.
end

--- No-op on bitmap gfx (per-cell scaling removed in new API).
function atlasgfx.rect_pixel_scale() end

function atlasgfx.rect_pixel_scale_reset() end

_G.__AtlasGFX = atlasgfx
return atlasgfx
