--[[
  atlas_color.lua — AtlasOS color token → normalized RGBA float resolution.
  Extracted from atlasgfx so any module can resolve colors without pulling in drawing state.
]]

if _G.__AtlasColor then return _G.__AtlasColor end

local NAMED = {
  black          = { 0.02, 0.02, 0.02, 1 },
  red            = { 0.75, 0.12, 0.12, 1 },
  green          = { 0.15, 0.72, 0.2,  1 },
  yellow         = { 0.92, 0.86, 0.2,  1 },
  blue           = { 0.22, 0.4,  0.88, 1 },
  magenta        = { 0.82, 0.22, 0.75, 1 },
  cyan           = { 0.15, 0.82, 0.88, 1 },
  white          = { 0.88, 0.88, 0.88, 1 },
  bright_black   = { 0.35, 0.35, 0.38, 1 },
  bright_red     = { 1,    0.35, 0.35, 1 },
  bright_green   = { 0.35, 1,    0.45, 1 },
  bright_yellow  = { 1,    1,    0.45, 1 },
  bright_blue    = { 0.45, 0.55, 1,    1 },
  bright_magenta = { 1,    0.45, 1,    1 },
  bright_cyan    = { 0.45, 1,    1,    1 },
  bright_white   = { 1,    1,    1,    1 },
}

local NUM = {
  [22]  = { 0.35, 0.38, 0.95, 1 },
  [28]  = { 0.22, 0.88, 0.28, 1 },
  [235] = { 0.12, 0.12, 0.14, 1 },
  [252] = { 0.93, 0.93, 0.94, 1 },
}

local M = {}

--- Returns r, g, b, a as normalized floats [0, 1].
--- c may be a named string, a 256-colour integer, an {r,g,b,a} table, or nil.
--- Falls back to opaque white when unresolved.
function M.resolve(c)
  if type(c) == "table" then
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
  end
  if type(c) == "string" then
    local t = NAMED[c]
    if t then return t[1], t[2], t[3], t[4] end
  end
  if type(c) == "number" then
    local n = math.floor(c)
    local t = NUM[n]
    if t then return t[1], t[2], t[3], t[4] end
    if n >= 232 and n <= 255 then
      local v = (n - 232) / 23
      return v, v, v, 1
    end
  end
  return 1, 1, 1, 1
end

_G.__AtlasColor = M
return M
