--[[
  Input API — uses LuaMade/Logiscript mod when available (_G.input).
  Docs: https://garretreichenbach.github.io/Logiscript/markdown/io/input.html

  Mod API: input.poll() -> single event or nil; input.waitFor(ms); input.clear();
           input.consumeKeyboard(); input.releaseKeyboard(); input.pending()
           Compatibility: input.setEnabled(bool), input.isEnabled()
           Optional: input.cancelEvent(e) — stop key from reaching terminal / game bar
           when not handling it in a text field (see AtlasOS UI.run_loop).
  Events: { type="key", key=GLFW, char, down, shift, ctrl, alt }
          { type="mouse", button, pressed, released, x, y, dx, dy, wheel }

  Mouse x,y are in dialog pixels. With bitmap gfx, prefer e.uiX / e.uiY and e.insideCanvas
  (canvas space); UI maps those to cells. Otherwise use set_canvas_pixels() + pixel_to_cell().
]]

local mod = rawget(_G, "input")

-- Some userdata-backed APIs throw on unknown member access (instead of returning nil).
-- Probe methods via pcall so missing methods don't crash AtlasOS.
local function mod_method(name)
  if not mod then return nil end
  local ok, fn = pcall(function()
    return mod[name]
  end)
  if ok and type(fn) == "function" then return fn end
  return nil
end

local input = {
  _queue = {},
  _pixel_w = nil,
  _pixel_h = nil,
  _kbd_owned = false,
}

--- Set dialog/canvas size in pixels (for pixel_to_cell scaling). Call when known (e.g. from gfx).
function input.set_canvas_pixels(pw, ph)
  input._pixel_w = (pw and pw > 0) and pw or nil
  input._pixel_h = (ph and ph > 0) and ph or nil
end

--- Convert dialog pixel (px, py) to 1-based cell (cx, cy) for a grid of cellW x cellH.
--- If set_canvas_pixels was not called, assumes 1:1 (pixels = cells).
function input.pixel_to_cell(px, py, cellW, cellH)
  local px_val = tonumber(px) or 0
  local py_val = tonumber(py) or 0
  cellW = math.max(1, tonumber(cellW) or 1)
  cellH = math.max(1, tonumber(cellH) or 1)
  local cx, cy
  if input._pixel_w and input._pixel_h and input._pixel_w > 0 and input._pixel_h > 0 then
    cx = math.floor(px_val * cellW / input._pixel_w) + 1
    cy = math.floor(py_val * cellH / input._pixel_h) + 1
  else
    cx = math.floor(px_val) + 1
    cy = math.floor(py_val) + 1
  end
  cx = math.max(1, math.min(cellW, cx))
  cy = math.max(1, math.min(cellH, cy))
  return cx, cy
end

--- Return next event from mod or nil. If no mod, return nil.
function input.poll()
  local fn = mod_method("poll")
  if fn then
    return fn()
  end
  return nil
end

--- Collect all pending events into an array (mod returns one per poll()).
function input.poll_all()
  local out = {}
  while true do
    local e = input.poll()
    if not e then break end
    out[#out + 1] = e
  end
  return out
end

function input.push_mock(e)
  input._queue[#input._queue + 1] = e
end

function input.dispatch(events, handler)
  if not handler then return end
  if type(events) == "table" and not events.type then
    for _, e in ipairs(events) do
      if e.type == "key" and handler.on_key then handler.on_key(e) end
      if e.type == "mouse" and handler.on_mouse then handler.on_mouse(e) end
    end
  elseif type(events) == "table" and events.type then
    if events.type == "key" and handler.on_key then handler.on_key(events) end
    if events.type == "mouse" and handler.on_mouse then handler.on_mouse(events) end
  end
end

function input.clear()
  local fn = mod_method("clear")
  if fn then fn() end
  input._queue = {}
end

function input.setEnabled(b)
  if b then
    return input.consumeKeyboard()
  end
  return input.releaseKeyboard()
end

function input.isEnabled()
  local consumeKeyboard = mod_method("consumeKeyboard")
  local releaseKeyboard = mod_method("releaseKeyboard")
  if consumeKeyboard and releaseKeyboard then
    return input._kbd_owned == true
  end
  local fn = mod_method("isEnabled")
  if fn then return fn() end
  return true
end

--- Acquire keyboard focus for AtlasOS UI.
function input.consumeKeyboard()
  local consumeKeyboard = mod_method("consumeKeyboard")
  if consumeKeyboard then
    local ok = select(1, pcall(consumeKeyboard))
    if ok then
      input._kbd_owned = true
      return true
    end
  end
  local setEnabled = mod_method("setEnabled")
  if setEnabled then
    local ok = select(1, pcall(setEnabled, true))
    if ok then
      input._kbd_owned = true
      return true
    end
  end
  return false
end

--- Release keyboard focus back to terminal/game input.
function input.releaseKeyboard()
  local releaseKeyboard = mod_method("releaseKeyboard")
  if releaseKeyboard then
    local ok = select(1, pcall(releaseKeyboard))
    if ok then
      input._kbd_owned = false
      return true
    end
  end
  local setEnabled = mod_method("setEnabled")
  if setEnabled then
    local ok = select(1, pcall(setEnabled, false))
    if ok then
      input._kbd_owned = false
      return true
    end
  end
  return false
end

function input.waitFor(timeoutMs)
  local fn = mod_method("waitFor")
  if fn then return fn(timeoutMs) end
  return nil
end

function input.pending()
  local fn = mod_method("pending")
  if fn then return fn() end
  return 0
end

--- Forward to mod so the key is not applied to the terminal / OS bar.
--- Implement one of: input.cancelEvent(e), cancelKeyEvent(e), cancelKeyEvent().
function input.cancelKeyEvent(e)
  if not mod then return false end
  local cancelEvent = mod_method("cancelEvent")
  if cancelEvent then
    pcall(cancelEvent, e)
    return true
  end
  local consumeEvent = mod_method("consumeEvent")
  if consumeEvent then
    pcall(consumeEvent, e)
    return true
  end
  local cancelKeyEvent = mod_method("cancelKeyEvent")
  if cancelKeyEvent then
    if not select(1, pcall(cancelKeyEvent, e)) then pcall(cancelKeyEvent) end
    return true
  end
  local discardKeyEvent = mod_method("discardKeyEvent")
  if discardKeyEvent then
    pcall(discardKeyEvent, e)
    return true
  end
  return false
end

return input
