--[[
  Host name, clocks, taskbar dock line (LuaMade console / entity APIs).
]]

local M = {}

function M.clock_str()
	if console and console.getTime then
		local ms = console.getTime()
		local s = math.floor(ms / 1000) % 86400
		return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
	end
	return "--:--"
end

--- Format Sector / System / vectors from LuaMade Entity API.
function M.fmt_world_obj(o)
	if o == nil then return "—" end
	local ty = type(o)
	if ty == "string" or ty == "number" then return tostring(o) end
	if ty == "table" then
		local x, y, z = o.x, o.y, o.z
		if type(x) == "number" and type(y) == "number" and type(z) == "number" then
			return string.format("%d,%d,%d", math.floor(x), math.floor(y), math.floor(z))
		end
		if o.getName then
			local ok, n = pcall(o.getName, o)
			if ok and n and tostring(n) ~= "" then return tostring(n) end
		end
	end
	local ok, s = pcall(tostring, o)
	if ok and s and not s:match("^table: 0x") then return s end
	return "—"
end

--- Block/computer name, sector coords/name, system.
function M.dock_world_line()
	local comp = "computer"
	local sector, sys = "—", "—"
	if console and console.getBlock then
		local ok, block = pcall(function() return console.getBlock() end)
		if ok and block then
			if block.getInfo then
				local ok2, info = pcall(block.getInfo, block)
				if ok2 and info and info.getName then
					comp = tostring(info.getName() or comp)
				end
			end
			if block.getEntity then
				local ok2, ent = pcall(block.getEntity, block)
				if ok2 and ent then
					if ent.getSector then
						local ok3, v = pcall(ent.getSector, ent)
						if ok3 and v ~= nil then sector = M.fmt_world_obj(v) end
					end
					if ent.getSystem then
						local ok3, v = pcall(ent.getSystem, ent)
						if ok3 and v ~= nil then sys = M.fmt_world_obj(v) end
					end
				end
			end
		end
	end
	return comp .. "  ·  " .. sector .. "  ·  " .. sys
end

--- Wall clock via util.now(); fallback console.getTime if os.date missing.
function M.dock_datetime_str()
	local ms
	if util and util.now then
		local ok, v = pcall(util.now)
		if ok and type(v) == "number" then ms = v end
	end
	if not ms and console and console.getTime then
		ms = console.getTime()
	end
	if not ms then return "--:--   —" end
	local sec = math.floor(ms / 1000)
	if os and os.date then
		return os.date("%H:%M", sec) .. "  " .. os.date("%Y-%m-%d", sec)
	end
	local s = sec % 86400
	return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60)) .. "  (no os.date)"
end

--- Host + working directory for the taskbar center strip (no window required).
function M.taskbar_status_line(max_cols)
	max_cols = math.max(8, tonumber(max_cols) or 48)
	local host = M.hostname()
	local cwd = (fs and fs.getCurrentDir and fs.getCurrentDir()) or "/home"
	if cwd:sub(1, 5) == "/home" then
		if cwd == "/home" then
			cwd = "~"
		else
			cwd = "~" .. cwd:sub(6)
		end
	end
	local sep = " · "
	local s = host .. sep .. cwd
	if #s <= max_cols then return s end
	local budget = max_cols - #host - #sep - 1
	if budget < 4 then
		s = host .. sep .. "…"
		if #s > max_cols then s = s:sub(1, max_cols - 1) .. "…" end
		return s
	end
	if #cwd > budget then
		cwd = "…" .. cwd:sub(math.max(1, #cwd - budget + 2))
	end
	s = host .. sep .. cwd
	if #s > max_cols then s = s:sub(1, max_cols - 1) .. "…" end
	return s
end

function M.hostname()
	if console and console.getBlock then
		local ok, block = pcall(function() return console.getBlock() end)
		if ok and block and block.getInfo then
			local ok2, info = pcall(block.getInfo, block)
			if ok2 and info and info.getName then
				return info.getName() or "computer"
			end
		end
	end
	return "computer"
end

return M
