--[[
  Input API — uses LuaMade/Logiscript mod when available (_G.input).
  Docs: https://garretreichenbach.github.io/Logiscript/markdown/io/input.html

  Mod API: input.poll() -> single event or nil; input.waitFor(ms); input.clear();
           input.setEnabled(bool); input.isEnabled(); input.pending()
           Optional: input.cancelEvent(e) — stop key from reaching terminal / game bar
           when not handling it in a text field (see AtlasOS UI.run_loop).
  Events: { type="key", key=GLFW, char, down, shift, ctrl, alt }
          { type="mouse", button, pressed, released, x, y, dx, dy, wheel }

  Mouse x,y are in dialog pixels. Use set_canvas_pixels() + pixel_to_cell() to scale
  to the gfx cell grid (1-based).
]]

local mod = rawget(_G, "input")

local input = {
  _queue = {},
  _pixel_w = nil,
  _pixel_h = nil,
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
  if mod and type(mod.poll) == "function" then
    return mod.poll()
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
  if mod and type(mod.clear) == "function" then mod.clear() end
  input._queue = {}
end

function input.setEnabled(b)
  if mod and type(mod.setEnabled) == "function" then mod.setEnabled(b) end
end

function input.isEnabled()
  if mod and type(mod.isEnabled) == "function" then return mod.isEnabled() end
  return true
end

function input.waitFor(timeoutMs)
  if mod and type(mod.waitFor) == "function" then return mod.waitFor(timeoutMs) end
  return nil
end

function input.pending()
  if mod and type(mod.pending) == "function" then return mod.pending() end
  return 0
end

--- Forward to mod so the key is not applied to the terminal / OS bar.
--- Implement one of: input.cancelEvent(e), cancelKeyEvent(e), cancelKeyEvent().
function input.cancelKeyEvent(e)
  if not mod then return false end
  if type(mod.cancelEvent) == "function" then
    pcall(mod.cancelEvent, e)
    return true
  end
  if type(mod.consumeEvent) == "function" then
    pcall(mod.consumeEvent, e)
    return true
  end
  if type(mod.cancelKeyEvent) == "function" then
    if not select(1, pcall(mod.cancelKeyEvent, e)) then pcall(mod.cancelKeyEvent) end
    return true
  end
  if type(mod.discardKeyEvent) == "function" then
    pcall(mod.discardKeyEvent, e)
    return true
  end
  return false
end

return input
