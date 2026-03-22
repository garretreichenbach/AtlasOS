--[[
  atlas_draw.lua — Cell-grid drawing adapter backed by gfx_2d.
  Drop-in replacement for atlasgfx.lua (Phase 1 migration).

  All public coordinates are in character cells (1-based x/y, width/height in cells).
  Pixel conversion is handled internally. Phase 2 will move callers to pixel coords
  and gui components, at which point this module can be removed.

  Canvas sizing: gfx_2d.setAutoScale(true) is enabled so the host viewport scales
  the logical canvas automatically — no manual cell_scale / gfx.conf needed.

  Text rendering uses gfx_2d.text() (built-in pixel font, scale 1) instead of the
  manual 8×8 bitmap font loop from the old atlasgfx.
]]

if _G.__AtlasDraw then return _G.__AtlasDraw end

local color = dofile("/home/lib/atlas_color.lua")

-- Logical pixel dimensions of one cell (at gfx_2d text scale 1).
-- cell_w matches the 8-pixel-wide built-in font; cell_h adds 2px leading.
local CELL_W = 8
local CELL_H = 10

local D = {
  cell_w     = CELL_W,
  cell_h     = CELL_H,
  text_scale = 1,
  layer      = "default",
}

--- init([conf]) — validates gfx_2d is present. The conf table is accepted for
--- backward compatibility with callers that still pass a gfx.conf result, but the
--- cell_scale field is no longer used; scaling is handled by gfx_2d.setAutoScale.
function D.init(_conf)
  assert(type(gfx_2d) == "table", "atlas_draw.init: global 'gfx_2d' is missing")
  D.cell_w     = CELL_W
  D.cell_h     = CELL_H
  D.text_scale = 1
end

--- Set the canvas to fit (cols × rows) cells and enable viewport auto-scale.
--- Returns the canvas size in pixels.
function D.set_canvas_from_cells(cols, rows)
  cols = math.max(1, math.floor(cols or 80))
  rows = math.max(1, math.floor(rows or 24))
  assert(type(gfx_2d.setCanvasSize) == "function",
    "atlas_draw.set_canvas_from_cells: gfx_2d.setCanvasSize missing")
  if type(gfx_2d.setAutoScale) == "function" then
    gfx_2d.setAutoScale(true)
  end
  local pw = cols * D.cell_w
  local ph = rows * D.cell_h
  gfx_2d.setCanvasSize(pw, ph)
  return pw, ph
end

--- Returns current canvas size in cells (derived from gfx_2d canvas dimensions).
function D.canvas_cells()
  assert(
    type(gfx_2d.getWidth) == "function" and type(gfx_2d.getHeight) == "function",
    "atlas_draw.canvas_cells: gfx_2d.getWidth/getHeight missing"
  )
  local gw = gfx_2d.getWidth()
  local gh = gfx_2d.getHeight()
  if type(gw) ~= "number" or type(gh) ~= "number" then return 80, 24 end
  return math.max(8, math.floor(gw / D.cell_w)),
         math.max(8, math.floor(gh / D.cell_h))
end

--- Returns the canvas pixel dimensions used for input hit-testing.
function D.canvas_pixels_for_input()
  if type(gfx_2d.getWidth) ~= "function" then return nil, nil end
  local gw, gh = gfx_2d.getWidth(), gfx_2d.getHeight()
  if gw and gh and gw > 0 and gh > 0 then return gw, gh end
  return nil, nil
end

--- Convert 1-based cell (cx, cy) to top-left pixel coordinates.
function D.cell_to_pixel(cx, cy)
  return (math.floor(cx or 1) - 1) * D.cell_w,
         (math.floor(cy or 1) - 1) * D.cell_h
end

--- Convert canvas pixel (px, py) to 1-based cell coordinates.
function D.pixel_to_cell_rel(px, py)
  return math.floor((tonumber(px) or 0) / D.cell_w) + 1,
         math.floor((tonumber(py) or 0) / D.cell_h) + 1
end

--- Clear the canvas and open a new draw batch (anti-flicker).
function D.begin_frame()
  assert(type(gfx_2d.clear) == "function", "atlas_draw.begin_frame: gfx_2d.clear missing")
  gfx_2d.clear()
  if type(gfx_2d.beginBatch) == "function" then gfx_2d.beginBatch() end
  if type(gfx_2d.setLayer) == "function" then gfx_2d.setLayer(D.layer) end
end

--- Commit the draw batch started by begin_frame.
function D.end_frame()
  if type(gfx_2d.commitBatch) == "function" then gfx_2d.commitBatch() end
end

--- Filled rectangle in cell coordinates.
--- bg_color: AtlasOS color token (named string, 256-colour int, or {r,g,b,a} table).
function D.fillRect(cx, cy, cw, ch, bg_color)
  cx = math.floor(cx or 1)
  cy = math.floor(cy or 1)
  cw = math.floor(cw or 1)
  ch = math.floor(ch or 1)
  if cw < 1 or ch < 1 then return end
  local px, py = D.cell_to_pixel(cx, cy)
  local pw, ph = cw * D.cell_w, ch * D.cell_h
  local r, g, b, a = color.resolve(bg_color)
  gfx_2d.rect(px, py, pw, ph, r, g, b, a, true)
end

--- Outline rectangle in cell coordinates.
function D.rect(cx, cy, cw, ch, fg_color)
  cx = math.floor(cx or 1)
  cy = math.floor(cy or 1)
  cw = math.floor(cw or 1)
  ch = math.floor(ch or 1)
  if cw < 2 or ch < 2 then return end
  local px, py = D.cell_to_pixel(cx, cy)
  local pw, ph = cw * D.cell_w, ch * D.cell_h
  local r, g, b, a = color.resolve(fg_color)
  gfx_2d.rect(px, py, pw, ph, r, g, b, a, false)
end

--- Text with background fill in cell coordinates.
--- Renders str at cell (cx, cy) with fg_color foreground and optional bg_color background.
function D.text(cx, cy, str, fg_color, bg_color)
  str = tostring(str or "")
  if #str == 0 then return end
  cx, cy = math.floor(cx or 1), math.floor(cy or 1)
  local px, py = D.cell_to_pixel(cx, cy)
  local pw = #str * D.cell_w
  local ph = D.cell_h
  if bg_color then
    local r, g, b, a = color.resolve(bg_color)
    gfx_2d.rect(px, py, pw, ph, r, g, b, a, true)
  end
  local r, g, b, a = color.resolve(fg_color)
  gfx_2d.text(px, py, str, r, g, b, a, D.text_scale)
end

_G.__AtlasDraw = D
return D
