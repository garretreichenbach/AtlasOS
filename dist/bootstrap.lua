--[[
AtlasOS Bootstrap Installer
Downloads the full installer from GitHub Pages and runs it.

Usage in-game:
  httpget https://garretreichenbach.github.io/AtlasOS/bootstrap.lua /tmp/bootstrap.lua
  run /tmp/bootstrap.lua
]]

local GITHUB_REPO = "garretreichenbach"  -- Change this to your GitHub username
local INSTALLER_URL = "https://" .. GITHUB_REPO .. ".github.io/AtlasOS/atlasos-web-installer.lua"
local INSTALLER_PATH = "/tmp/atlasos-web-installer.lua"

local function download_installer()
  print("Downloading AtlasOS installer from GitHub Pages...")
  print("URL: " .. INSTALLER_URL)
  print("")

  local ok, err = pcall(function()
    return httpget(INSTALLER_URL, INSTALLER_PATH)
  end)

  if not ok then
    error("Failed to download installer: " .. tostring(err))
  end

  print("Installer downloaded to " .. INSTALLER_PATH)
  return true
end

local function run_installer()
  print("Running AtlasOS installer...")
  print("")

  if type(_G.__AtlasLoad) == "function" then
    return _G.__AtlasLoad(INSTALLER_PATH)
  elseif type(dofile) == "function" then
    return dofile(INSTALLER_PATH)
  else
    error("No script loader available (dofile/__AtlasLoad missing)")
  end
end

local function main()
  print("=" .. string.rep("=", 60))
  print("  AtlasOS Bootstrap Installer")
  print("=" .. string.rep("=", 60))
  print("")

  -- Download the full installer
  download_installer()

  -- Run it
  print("")
  run_installer()
end

local ok, err = xpcall(main, function(e)
  if debug and type(debug.traceback) == "function" then
    return debug.traceback(tostring(e), 2)
  end
  return tostring(e)
end)

if not ok then
  print("")
  print("Bootstrap failed: " .. tostring(err))
end
