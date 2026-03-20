--[[
  AtlasOS installer for LuaMade computers.

  LuaMade runs /etc/startup.lua at terminal boot if it exists
  (see https://garretreichenbach.github.io/Logiscript/markdown/core/luamade.html#startup-behavior).

  Deploy files first:
    · Repo Lib/     → virtual  /home/lib/
    · Repo AtlasOS/ → virtual  /home/AtlasOS/
  Then run:  run /home/AtlasOS/installer.lua

  Optional: run /home/AtlasOS/installer.lua uninstall  — remove AtlasOS startup hook only.
]]

local STARTUP_PATH = "/etc/startup.lua"
local STARTUP_BACKUP = "/etc/startup.lua.atlasos_backup"

local function check_paths()
	local missing = {}
	for _, p in ipairs({
		"/home/AtlasOS/installer_gate.lua",
		"/home/AtlasOS/installer_ui.lua",
		"/home/AtlasOS/boot_desktop.lua",
		"/home/AtlasOS/shell.lua",
		"/home/AtlasOS/ui.lua",
		"/home/lib/startmenu.lua",
		"/home/lib/atlasgfx.lua",
		"/home/lib/atlasinstall.lua",
		"/home/lib/atlasprofile.lua",
		"/home/lib/atlastheme.lua",
	}) do
		if not fs.read(p) then missing[#missing + 1] = p end
	end
	return missing
end

local STARTUP_BODY = [[-- AtlasOS auto-start (LuaMade runs this at boot; see Logiscript "Startup behavior")
local function atlas_bootstrap_loader()
	local orig_loadfile = rawget(_G, "loadfile")
	local orig_dofile = rawget(_G, "dofile")

	local function atlas_loadfile(path)
		path = tostring(path or "")
		if type(orig_loadfile) == "function" then
			local ok, chunk, err = pcall(orig_loadfile, path)
			if ok and (type(chunk) == "function" or chunk == nil) then
				return chunk, err
			end
		end
		if fs and type(fs.read) == "function" and type(load) == "function" then
			local ok, raw = pcall(fs.read, path)
			if not ok or raw == nil then
				return nil, "could not read " .. tostring(path)
			end
			return load(raw, "@" .. path)
		end
		return nil, "no script loader available (loadfile/fs.read+load missing)"
	end

	local function atlas_dofile(path)
		local chunk, err = atlas_loadfile(path)
		if not chunk then
			if type(orig_dofile) == "function" then
				return orig_dofile(path)
			end
			error(err)
		end
		return chunk()
	end

	_G.loadfile = atlas_loadfile
	_G.dofile = atlas_dofile
	_G.__AtlasLoad = atlas_dofile
	return atlas_dofile
end

atlas_bootstrap_loader()
local function atlas_format_error(err)
	if debug and type(debug.traceback) == "function" then
		return debug.traceback(tostring(err), 2)
	end
	return tostring(err)
end

local ok, err = xpcall(function()
	return _G.__AtlasLoad("/home/AtlasOS/installer_gate.lua")
end, atlas_format_error)
if not ok then
	print("AtlasOS startup failed: " .. tostring(err))
end
]]

local function install()
	local miss = check_paths()
	if #miss > 0 then
		print("AtlasOS installer — missing files:")
		for _, p in ipairs(miss) do print("  " .. p) end
		print("")
		print("Copy the repo into the computer:")
		print("  Lib/*        → /home/lib/")
		print("  AtlasOS/*    → /home/AtlasOS/")
		print("Then run this installer again.")
		return false
	end

	local prev = fs.read(STARTUP_PATH)
	if prev and prev:gsub("%s", "") ~= "" then
		local ok = pcall(fs.write, STARTUP_BACKUP, prev)
		if ok then
			print("Backed up previous startup to " .. STARTUP_BACKUP)
		else
			print("Could not write " .. STARTUP_BACKUP .. " — aborting.")
			return false
		end
	end

	pcall(fs.makeDir, "/etc")
	local ok, err = pcall(fs.write, STARTUP_PATH, STARTUP_BODY)
	if not ok then
		print("Error writing " .. STARTUP_PATH .. ": " .. tostring(err))
		return false
	end

	print("Wrote " .. STARTUP_PATH)
	print("Reboot this computer (or open a new terminal) to boot into AtlasOS.")
	print("Fallback: run  desktop  for the UI without editing startup.")
	return true
end

local function uninstall()
	if not fs.read(STARTUP_PATH) then
		print("No " .. STARTUP_PATH .. " — nothing to remove.")
		return true
	end
	local body = fs.read(STARTUP_PATH) or ""
	if not body:match("boot_desktop%.lua") and not body:match("installer_gate%.lua") and not body:match("AtlasOS") then
		print(STARTUP_PATH .. " does not look like AtlasOS startup — not removing.")
		return false
	end
	if fs.read(STARTUP_BACKUP) then
		pcall(fs.write, STARTUP_PATH, fs.read(STARTUP_BACKUP))
		print("Restored " .. STARTUP_PATH .. " from " .. STARTUP_BACKUP)
	else
		pcall(fs.delete, STARTUP_PATH)
		if fs.remove then pcall(fs.remove, STARTUP_PATH) end
		print("Removed " .. STARTUP_PATH .. " (no backup to restore)")
	end
	print("Reboot to return to default terminal boot.")
	return true
end

local arg1 = args and args[1] and tostring(args[1]):lower()
if arg1 == "uninstall" or arg1 == "remove" then
	uninstall()
elseif arg1 == "check" then
	local m = check_paths()
	if #m == 0 then
		print("All core paths present.")
	else
		print("Missing:")
		for _, p in ipairs(m) do print("  " .. p) end
	end
else
	install()
end
