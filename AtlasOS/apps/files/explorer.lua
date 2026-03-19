--[[
  Files window painter factory (see appinfo `AtlasOS.paint_module`).
  Listing follows `UI.files_dir` / `UI.files_effective_dir()`.
  To open a path on launch, use appinfo `window` = `"Files"` and `args` = `["/abs/path"]`;
  the desktop runs `UI.apply_launch_args` before focusing the window (see Trash app).
]]
local CACHE = "__AtlasOS_files_factory"
local factory = _G[CACHE]
if not factory then
  factory = function(ctx)
  local UI = ctx.UI
  local widgets = ctx.widgets
  local window = ctx.window
  local paths = dofile("/home/lib/desktop_paths.lua")
  local files_chrome = dofile("/home/lib/files_chrome.lua")
  local trash_util = dofile("/home/lib/trash_util.lua")
  local appkit = dofile("/home/lib/appkit.lua")
  local shell = appkit.shell({
    on_command = function(id)
      if id == "files:empty_trash" then
        if trash_util.empty_trash() then
          _G.AtlasOS_log = _G.AtlasOS_log or {}
          _G.AtlasOS_log[#_G.AtlasOS_log + 1] = "[Trash] Emptied."
        end
        UI.redraw()
      elseif id == "files:up" then
        local d = UI.files_effective_dir()
        if d ~= "/" and d ~= "" then
          local p = d:match("^(.+)/[^/]+$") or "/"
          UI.files_set_dir(p)
        end
      elseif id == "files:home" then
        UI.files_set_dir("/home")
      elseif id == "files:apps" then
        UI.files_set_dir("/home/apps")
      elseif id == "files:refresh" then
        UI.redraw()
      end
    end,
  })
  files_chrome.sync_files_shell(shell, false)

  return function(win)
    shell:attach(win)
    local dir = UI.files_effective_dir()
    files_chrome.sync_files_shell(shell, paths.normalize(dir) == paths.normalize(paths.TRASH_DIR))
    if (UI.files_dir or "") ~= dir then
      UI.files_dir = dir
    end
    local list = {}
    if dir ~= "/" and dir ~= "" then
      list[#list + 1] = { text = "..", dir = true }
    end
    local ok, names = pcall(fs.list, dir)
    if ok and names then
      for _, name in ipairs(names) do
        local full = dir:match("/$") and (dir .. name) or (dir .. "/" .. name)
        local isDir = false
        if fs.isDir then pcall(function() isDir = fs.isDir(full) end) end
        if UI.files_show_list_entry(dir, name, isDir) then
          list[#list + 1] = { text = name, dir = isDir }
        end
      end
    else
      list[#list + 1] = "(cannot list)"
    end

    shell:paint_decorations(win)
    local y0 = shell:content_row()
    local ch = win:client_h()
    if y0 + 2 > ch then
      shell:paint_dropdown(win)
      return
    end
    window.draw_text_line(win, 0, y0, widgets.path_display(dir, win:client_w() - 2))
    widgets.hrule(win, y0 + 1, "-")
    local list_h = math.max(0, ch - (y0 + 2))
    widgets.list_box(win, list, 1, list_h, y0 + 2)

    shell:paint_dropdown(win)
  end
  end
  _G[CACHE] = factory
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "files" then
  print("Files explorer — use the Files window or: files")
end
return factory
