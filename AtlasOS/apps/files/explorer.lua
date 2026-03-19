--[[ Files window + runapp entry (same file; see appinfo entry + paint_module). ]]
local CACHE = "__AtlasOS_files_factory"
local factory = _G[CACHE]
if not factory then
  factory = function(ctx)
  local UI = ctx.UI
  local widgets = ctx.widgets
  local window = ctx.window
  local appkit = dofile("/home/lib/appkit.lua")
  local shell = appkit.shell({
    on_command = function(id)
      if id == "files:up" then
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
  shell:set_menubar({
    {
      label = "File",
      items = {
        { label = "Up", id = "files:up" },
        { label = "Home", id = "files:home" },
        { label = "Apps folder", id = "files:apps" },
        { label = "Refresh", id = "files:refresh" },
      },
    },
  })
  shell:set_toolbar({
    { label = "Up", id = "files:up", w = 6 },
    { label = "Home", id = "files:home", w = 8 },
    { label = "Apps", id = "files:apps", w = 8 },
    { label = "Refresh", id = "files:refresh", w = 10 },
  })

  return function(win)
    shell:attach(win)
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
