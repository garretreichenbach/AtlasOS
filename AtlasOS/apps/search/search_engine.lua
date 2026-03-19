--[[ Taskbar search + runapp entry (same file; state must stay singleton). ]]
local API_KEY = "__AtlasOS_search_engine_api"
local export = _G[API_KEY]
if not export then

local function join(dir, name)
  return dir:match("/$") and (dir .. name) or (dir .. "/" .. name)
end

local state = {
  needle = "",
  needle_display = "",
  name_hits = {},
  content_hits = {},
  dir_queue = {},
  file_queue = {},
  busy = false,
  scanned = 0,
  max_scan = 500,
  max_name = 24,
  max_content = 12,
  tick = 0,
}

local function clear()
  state.needle = ""
  state.needle_display = ""
  state.name_hits = {}
  state.content_hits = {}
  state.dir_queue = {}
  state.file_queue = {}
  state.busy = false
  state.scanned = 0
end

local function begin(needle)
  needle = (needle or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if needle == "" then
    clear()
    return
  end
  state.needle_display = needle
  state.needle = needle:lower()
  state.name_hits = {}
  state.content_hits = {}
  state.dir_queue = { "/home", "/etc" }
  state.file_queue = {}
  state.busy = true
  state.scanned = 0
  state.tick = 0
end

local function step(budget)
  budget = budget or 18
  local n = state
  if not n.busy or n.needle == "" then return end
  while budget > 0 do
    if #n.content_hits >= n.max_content and #n.file_queue == 0 and #n.dir_queue == 0 then
      n.busy = false
      return
    end
    if #n.file_queue > 0 and #n.content_hits < n.max_content then
      local path = table.remove(n.file_queue, 1)
      budget = budget - 1
      n.scanned = n.scanned + 1
      if n.scanned > n.max_scan then
        n.busy = false
        return
      end
      local body = fs.read(path)
      if type(body) == "string" and #body < 20000 and body:lower():find(n.needle, 1, true) then
        n.content_hits[#n.content_hits + 1] = path
      end
    elseif #n.dir_queue > 0 then
      local dir = table.remove(n.dir_queue, 1)
      budget = budget - 1
      local ok, names = pcall(fs.list, dir)
      if ok and names then
        for _, name in ipairs(names) do
          local full = join(dir, name)
          local nl = name:lower()
          if nl:find(n.needle, 1, true) and #n.name_hits < n.max_name then
            n.name_hits[#n.name_hits + 1] = full
          end
          local isDir = false
          if fs.isDir then pcall(function() isDir = fs.isDir(full) end) end
          if isDir then
            if #n.dir_queue < 200 then n.dir_queue[#n.dir_queue + 1] = full end
          else
            if #n.file_queue < 300 then n.file_queue[#n.file_queue + 1] = full end
          end
        end
      end
    else
      n.busy = false
      return
    end
  end
end

export = {
  clear = clear,
  begin = begin,
  step = step,
  get_state = function()
    return state
  end,
  --- ag = atlasgfx facade; opt: x, y0, sw, th, tb, fg, accent (28)
  draw_taskbar = function(ag, opt)
    local x, y0, sw, th, tb, fg, accent = opt.x, opt.y0, opt.sw, opt.th, opt.tb, opt.fg, opt.accent
    local qraw = state.needle_display ~= "" and state.needle_display or ""
    local spin = ({ ".", "o", "O", "o" })[(state.tick % 4) + 1]
    state.tick = state.tick + 1
    local qdisp = qraw
    if state.busy and qraw ~= "" then qdisp = qdisp .. " " .. spin end
    if #qdisp > sw - 4 then qdisp = qdisp:sub(1, math.max(1, sw - 5)) .. "…" end
    local box = "[" .. qdisp .. string.rep(" ", math.max(0, sw - 2 - #qdisp)) .. "]"
    if #box > sw then box = box:sub(1, sw) end
    local search_h = (th >= 3) and 2 or 1
    ag.setColor("black", "white")
    ag.fillRect(x, y0, sw, search_h, " ")
    ag.text(x, y0, box:sub(1, sw))
    ag.setColor(fg, tb)
    if search_h >= 2 then
      local sub = ""
      if state.needle ~= "" then
        sub = (#state.name_hits .. " name  " .. #state.content_hits .. " in file")
        if state.busy then sub = sub .. " …" else sub = sub .. " done" end
      else
        sub = "search / find"
      end
      if #sub > sw then sub = sub:sub(1, sw - 1) .. "…" end
      ag.setColor(accent, tb)
      ag.text(x, y0 + 1, sub)
    elseif th == 2 and state.needle ~= "" then
      local tail = " " .. #state.name_hits .. "n/" .. #state.content_hits .. "f"
      if #box + #tail <= sw then
        ag.setColor("black", "white")
        ag.text(x + #box, y0, tail)
      end
    end
  end,
}
_G[API_KEY] = export
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "taskbar_search" then
  print("Search indexes /home and /etc from the taskbar.")
  print("Commands: find <text>   search_status   search (clears)")
end
return export
