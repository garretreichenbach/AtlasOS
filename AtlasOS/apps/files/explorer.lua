--[[ Files window + runapp entry (same file; see appinfo entry + paint_module). ]]
local CACHE = "__AtlasOS_files_factory"
local factory = _G[CACHE]
if not factory then
  factory = function(ctx)
  local UI = ctx.UI
  local widgets = ctx.widgets
  local window = ctx.window

  return function(win)
    local dir = UI.files_effective_dir()
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
    window.draw_text_line(win, 0, 0, widgets.path_display(dir, win:client_w() - 2))
    widgets.hrule(win, 1, "-")
    widgets.list_box(win, list, 1, win:client_h() - 2, 2)
  end
  end
  _G[CACHE] = factory
end
if _G.AtlasOS_APP and _G.AtlasOS_APP.id == "files" then
  print("Files explorer — use the Files window or: files")
end
return factory
