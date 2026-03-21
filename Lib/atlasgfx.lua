--[[
  Cell-grid UI drawing for LuaMade bitmap gfx (pixel coords + rgba rects).
  https://garretreichenbach.github.io/Logiscript/markdown/graphics/gfx.html

  Current API (drawing): gfx.rect(x,y,w,h,r,g,b,a,filled), gfx.point, gfx.line
  Canvas: gfx.setCanvasSize, gfx.getWidth/getHeight
  Layers: gfx.clear, gfx.setLayer, gfx.createLayer, gfx.clearLayer

  All draw calls pass color directly — there is no global color state.
  atlasgfx.fillRect(x,y,w,h,bg_color)       filled rect in bg_color
  atlasgfx.rect(x,y,w,h,fg_color)           outline rect in fg_color
  atlasgfx.text(x,y,str,fg_color,bg_color)  pixel-font text
]]

if _G.__AtlasGFX then
  return _G.__AtlasGFX
end

local FONT = dofile("/home/lib/font8x8_basic.lua")

local atlasgfx = {
  cell_w = 8,
  cell_h = 14,
  layer = "atlas",
}

-- Phase 1 hard cutover: require the new luamade-compatible `gfx` drawing API.
-- This adapter is strict: if the expected drawing primitives are not present
-- atlasgfx.init will raise an error so the migration is obvious and fails fast.

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
  local sc = tonumber(conf.cell_scale) or 1
  sc = math.max(0.5, math.min(4, sc))
  atlasgfx.cell_w = math.max(4, math.floor(8 * sc + 0.5))
  atlasgfx.cell_h = math.max(6, math.floor(14 * sc + 0.5))
  -- Ensure the host provides the expected drawing primitives. This is a
  -- strict, luamade-only contract for the hard cutover.
  assert(type(gfx) == "table", "atlasgfx.init: required global 'gfx' is missing - install the new luamade graphics library")
  assert(type(gfx.rect) == "function", "atlasgfx.init: gfx.rect missing")
  assert(type(gfx.getWidth) == "function" and type(gfx.getHeight) == "function", "atlasgfx.init: gfx.getWidth/getHeight missing")
  -- setCanvasSize and clear are optional but preferred; if missing, callers may fail later.
end

function atlasgfx.is_bitmap()
  -- Hard-cutover: treat the drawing surface as bitmap/cell-backed. Callers
  -- that branch on this will see consistent behavior and should be migrated
  -- in Phase 2 to remove the conditional logic.
  return true
end

function atlasgfx.set_canvas_from_cells(cols, rows)
  cols = math.max(1, math.floor(cols or 80))
  rows = math.max(1, math.floor(rows or 24))
  local pw = cols * atlasgfx.cell_w
  local ph = rows * atlasgfx.cell_h
  -- Resize the underlying drawing canvas. Fail if host does not expose the API.
  assert(type(gfx.setCanvasSize) == "function", "atlasgfx.set_canvas_from_cells: gfx.setCanvasSize missing")
  gfx.setCanvasSize(pw, ph)
  return pw, ph
end

function atlasgfx.canvas_cells()
  assert(type(gfx.getWidth) == "function" and type(gfx.getHeight) == "function", "atlasgfx.canvas_cells: gfx.getWidth/getHeight missing")
  local gw, gh = gfx.getWidth(), gfx.getHeight()
  assert(type(gw) == "number" and type(gh) == "number", "atlasgfx.canvas_cells: invalid canvas dimensions")
  local cw = atlasgfx.cell_w > 0 and gw / atlasgfx.cell_w or gw
  local ch = atlasgfx.cell_h > 0 and gh / atlasgfx.cell_h or gh
  return math.max(8, math.floor(cw)), math.max(8, math.floor(ch))
end

function atlasgfx.canvas_pixels_for_input()
  assert(type(gfx.getWidth) == "function" and type(gfx.getHeight) == "function", "atlasgfx.canvas_pixels_for_input: gfx.getWidth/getHeight missing")
  local gw, gh = gfx.getWidth(), gfx.getHeight()
  if gw and gh and gw > 0 and gh > 0 then return gw, gh end
  return nil, nil
end

function atlasgfx.begin_frame()
  assert(type(gfx.clear) == "function", "atlasgfx.begin_frame: gfx.clear missing")
  gfx.clear()
  -- If host provides layers, attempt to set a default layer (non-fatal).
  if type(gfx.setLayer) == "function" then gfx.setLayer(atlasgfx.layer) end
end

function atlasgfx.fillRect(x, y, w, h, bg_color)
  x, y, w, h = math.floor(x or 1), math.floor(y or 1), math.floor(w or 1), math.floor(h or 1)
  if w < 1 or h < 1 then return end
  local px, py = atlasgfx.cell_to_pixel(x, y)
  local pw, ph = w * atlasgfx.cell_w, h * atlasgfx.cell_h
  local c = color_to_rgba(bg_color, { 0, 0, 0, 1 })
  gfx.rect(px, py, pw, ph, c[1], c[2], c[3], c[4], true)
end

function atlasgfx.rect(x, y, w, h, fg_color)
  x, y, w, h = math.floor(x or 1), math.floor(y or 1), math.floor(w or 1), math.floor(h or 1)
  if w < 2 or h < 2 then return end
  local px, py = atlasgfx.cell_to_pixel(x, y)
  local pw, ph = w * atlasgfx.cell_w, h * atlasgfx.cell_h
  local c = color_to_rgba(fg_color, { 1, 1, 1, 1 })
  gfx.rect(px, py, pw, ph, c[1], c[2], c[3], c[4], false)
end

function atlasgfx.text(x, y, str, fg_color, bg_color)
  -- Render a string into cell grid using the 8x8 pixel font.
  str = tostring(str or "")
  x, y = math.floor(x or 1), math.floor(y or 1)
  local cf = color_to_rgba(fg_color, { 1, 1, 1, 1 })
  local cb = color_to_rgba(bg_color, { 0, 0, 0, 1 })
  local rf, gf, bf, af = cf[1], cf[2], cf[3], cf[4]
  local br, bgc, bb, ba = cb[1], cb[2], cb[3], cb[4]
  local scale = math.min(atlasgfx.cell_w / 8, atlasgfx.cell_h / 8)
  scale = math.max(1, math.floor(scale))
  for i = 1, #str do
    local col = x + i - 1
    local px, py = atlasgfx.cell_to_pixel(col, y)
    gfx.rect(px, py, atlasgfx.cell_w, atlasgfx.cell_h, br, bgc, bb, ba, true)
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
            gfx.rect(ox + colp * scale, oy + (row - 1) * scale, scale, scale, rf, gf, bf, af, true)
          end
        end
      end
    end
  end
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


_G.__AtlasGFX = atlasgfx
return atlasgfx
