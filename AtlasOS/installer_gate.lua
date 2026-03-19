--[[
  Boot router: first-run graphical setup, then desktop.
]]
if fs.read("/etc/AtlasOS/setup_complete") then
	dofile("/home/AtlasOS/boot_desktop.lua")
else
	dofile("/home/AtlasOS/installer_ui.lua")
end
