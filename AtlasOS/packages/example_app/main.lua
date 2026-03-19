--[[ Example packaged app — AtlasOS_APP set while this runs. ]]
local app = _G.AtlasOS_APP
print("Example app: " .. tostring(app and app.id))
print("Package dir: " .. tostring(app and app.package_dir))
if app and app.args and #app.args > 0 then
  print("Args: " .. table.concat(app.args, " "))
end
