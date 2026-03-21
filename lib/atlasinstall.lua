--[[
  First-boot file install: copy AtlasOS + Lib from a staging volume into /home, then verify.
  Staging root must contain AtlasOS/ and Lib/ (same layout as the repo).
]]

local paths = dofile("/home/lib/desktop_paths.lua")

local M = {}

--- Minimum paths that must exist after install (same idea as installer.lua / installer_ui).
M.CORE_PATHS = {
	"/home/AtlasOS/installer_gate.lua",
	"/home/AtlasOS/installer_ui.lua",
	"/home/AtlasOS/boot_desktop.lua",
	"/home/AtlasOS/shell.lua",
	"/home/AtlasOS/ui.lua",
	"/home/lib/startmenu.lua",
	"/home/lib/atlas_color.lua",
	"/home/lib/atlas_draw.lua",
	"/home/lib/atlasinstall.lua",
	"/home/lib/atlasprofile.lua",
	"/home/lib/atlastheme.lua",
}

function M.looks_like_bundle(root)
	root = paths.normalize(root or "")
	if root == "" or root == "/" then return false end
	local shell = paths.join(paths.join(root, "AtlasOS"), "shell.lua")
	local sm = paths.join(paths.join(root, "Lib"), "startmenu.lua")
	local ok1, a = pcall(fs.read, shell)
	local ok2, b = pcall(fs.read, sm)
	return ok1 and ok2 and a ~= nil and b ~= nil
end

local function staging_hint_path()
	local ok, raw = pcall(fs.read, "/etc/AtlasOS/staging_root.txt")
	if not ok or type(raw) ~= "string" then return nil end
	local line = raw:match("^%s*(%S+)")
	return line
end

--- Pick a volume/folder that holds AtlasOS/ + Lib/, or nil if files already live under /home only.
function M.find_staging_root(cli_path)
	local tried = {}
	local function try(p)
		if not p or p == "" then return nil end
		p = paths.normalize(p)
		if tried[p] then return nil end
		tried[p] = true
		if M.looks_like_bundle(p) then return p end
		return nil
	end

	local candidates = {}
	if cli_path then candidates[#candidates + 1] = tostring(cli_path) end
	local hint = staging_hint_path()
	if hint then candidates[#candidates + 1] = hint end
	for _, c in ipairs({
		"/install",
		"/mnt",
		"/media",
		"/disk",
		"/disk1",
		"/floppy",
	}) do
		candidates[#candidates + 1] = c
	end

	for _, c in ipairs(candidates) do
		local r = try(c)
		if r then
			local norm = paths.normalize(r)
			if norm ~= "/home" then return r end
		end
	end
	return nil
end

local function map_dest_rel(rel)
	if rel:match("^AtlasOS/") then return "/home/" .. rel end
	if rel:match("^Lib/") then return "/home/" .. rel end
	return nil
end

local function walk_files(staging_root, sub, out)
	sub = sub or ""
	local base = sub == "" and staging_root or paths.join(staging_root, sub)
	local ok, names = pcall(fs.list, base)
	if not ok or not names then return end
	for _, n in ipairs(names) do
		local rel = (sub == "") and n or (sub .. "/" .. n)
		local abs = paths.join(staging_root, rel)
		local isDir = false
		if fs.isDir then pcall(function() isDir = fs.isDir(abs) end) end
		if isDir then
			walk_files(staging_root, rel, out)
		else
			out[#out + 1] = rel
		end
	end
end

local function collect_copy_steps(staging_root)
	staging_root = paths.normalize(staging_root)
	local rels = {}
	for _, top in ipairs({ "AtlasOS", "Lib" }) do
		local top_path = paths.join(staging_root, top)
		local ok, names = pcall(fs.list, top_path)
		if ok and names then walk_files(staging_root, top, rels) end
	end
	table.sort(rels)
	local steps = {}
	for _, rel in ipairs(rels) do
		local to_path = map_dest_rel(rel)
		if to_path then
			local from_path = paths.join(staging_root, rel)
			steps[#steps + 1] = {
				op = "copy",
				from = from_path,
				to = to_path,
				label = rel,
			}
		end
	end
	return steps
end

local function ensure_parent_dir(path)
	path = paths.normalize(path)
	local par = path:match("^(.+)/[^/]+$")
	if not par or par == "" or par == "/" then return end
	local acc = ""
	for part in par:gmatch("[^/]+") do
		acc = (acc == "") and ("/" .. part) or (acc .. "/" .. part)
		if fs.makeDir then pcall(fs.makeDir, acc) end
	end
end

local function copy_file(from, to)
	from = paths.normalize(from)
	to = paths.normalize(to)
	if fs.copy then
		local ok = pcall(fs.copy, from, to)
		if ok then return true end
	end
	local okr, raw = pcall(fs.read, from)
	if not okr or raw == nil then return false end
	ensure_parent_dir(to)
	local okw, err = pcall(fs.write, to, raw)
	return okw
end

local function verify_path(path)
	local ok, raw = pcall(fs.read, paths.normalize(path))
	return ok and raw ~= nil
end

--- plan: { title = string, hint = string?, steps = { op=, ... } }
function M.build_plan(cli_path)
	local staging = M.find_staging_root(cli_path)
	local steps = {}
	local title = "Verifying installation…"
	local hint = "No USB-style bundle found — checking files under /home/."

	if staging then
		title = "Installing AtlasOS from media…"
		hint = "Copying from " .. paths.normalize(staging) .. " → /home/"
		local copy_steps = collect_copy_steps(staging)
		for _, s in ipairs(copy_steps) do
			steps[#steps + 1] = s
		end
	end

	for _, p in ipairs(M.CORE_PATHS) do
		steps[#steps + 1] = { op = "verify", path = paths.normalize(p), label = p }
	end

	return {
		title = title,
		hint = hint,
		steps = steps,
		from_staging = staging,
	}
end

--- Process up to batch steps starting at index (1-based). Returns ok, next_index, err_detail.
function M.advance(plan, index, batch)
	local steps = plan and plan.steps
	if not steps or #steps == 0 then return false, index, "no install steps" end
	batch = math.max(1, tonumber(batch) or 4)
	local last = math.min(index + batch - 1, #steps)
	for i = index, last do
		local s = steps[i]
		if s.op == "copy" then
			if not copy_file(s.from, s.to) then
				return false, i, "copy failed: " .. tostring(s.from) .. " → " .. tostring(s.to)
			end
		elseif s.op == "verify" then
			if not verify_path(s.path) then
				return false, i, "missing: " .. tostring(s.path)
			end
		else
			return false, i, "unknown step"
		end
	end
	return true, last + 1
end

--- Coroutine: yields after each batched advance so the UI can redraw between I/O.
--- Yields:  true, progress (0..1), detail (string)  on progress tick.
--- Yields:  false, err (string)  on failure (then coroutine exits).
--- After the last tick, one more resume() runs the coroutine to completion (dead).
function M.install_coroutine(plan, batch_size)
	batch_size = math.max(1, tonumber(batch_size) or 5)
	return coroutine.create(function()
		local steps = plan and plan.steps
		if not steps or #steps == 0 then
			coroutine.yield(false, "no install steps")
			return
		end
		local index = 1
		local n = #steps
		while index <= n do
			local ok, next_i, err = M.advance(plan, index, batch_size)
			if not ok then
				coroutine.yield(false, tostring(err))
				return
			end
			index = next_i
			local detail = ""
			if index > 1 and steps[index - 1] then
				detail = steps[index - 1].label or ""
			end
			local progress = n > 0 and math.min(1, (index - 1) / n) or 1
			coroutine.yield(true, progress, detail)
		end
	end)
end

return M
