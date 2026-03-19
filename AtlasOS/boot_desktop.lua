--[[
  AtlasOS graphical session entry (blocking input loop).
  LuaMade runs /etc/startup.lua at boot — see installer.lua.
]]
_G.ATLASOS_START_DESKTOP = true
dofile("/home/AtlasOS/shell.lua")
