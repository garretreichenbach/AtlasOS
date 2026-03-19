--[[
  Minimal JSON decode / encode for AtlasOS (no native JSON in LuaMade).
  Supports: objects, arrays, strings, numbers, true, false, null.
  Strings: escapes \" \\ \/ \b \f \n \r \t \uXXXX (BMP → UTF-8; else ?).
]]

local json = {}

local function err(msg)
  error("json: " .. msg, 0)
end

local function byte_at(s, i)
  return s:byte(i) or 0
end

--- Decode JSON string → Lua value (table, string, number, boolean, nil for null).
function json.decode(str)
  if type(str) ~= "string" then err("expected string") end
  local n = #str
  local i = 1

  local function ws()
    while i <= n do
      local b = byte_at(str, i)
      if b == 32 or b == 9 or b == 10 or b == 13 then
        i = i + 1
      else
        break
      end
    end
  end

  local parse_value

  local function decode_u4()
    if i + 4 > n then err("bad \\u escape") end
    local hx = str:sub(i, i + 3)
    i = i + 4
    local c = tonumber(hx, 16)
    if not c then err("bad \\u hex") end
    if c < 0x80 then
      return string.char(c)
    elseif c < 0x800 then
      return string.char(0xC0 + math.floor(c / 0x40), 0x80 + (c % 0x40))
    elseif c < 0x10000 then
      return string.char(
        0xE0 + math.floor(c / 0x1000),
        0x80 + (math.floor(c / 0x40) % 0x40),
        0x80 + (c % 0x40)
      )
    end
    return "?"
  end

  local function parse_string()
    if str:sub(i, i) ~= '"' then err('expected "') end
    i = i + 1
    local parts, pn = {}, 0
    while i <= n do
      local b = byte_at(str, i)
      if b == 34 then
        i = i + 1
        return table.concat(parts)
      end
      if b == 92 then
        i = i + 1
        if i > n then err("escape at eof") end
        local e = str:sub(i, i)
        i = i + 1
        if e == '"' then pn = pn + 1; parts[pn] = '"'
        elseif e == "\\" then pn = pn + 1; parts[pn] = "\\"
        elseif e == "/" then pn = pn + 1; parts[pn] = "/"
        elseif e == "b" then pn = pn + 1; parts[pn] = "\008"
        elseif e == "f" then pn = pn + 1; parts[pn] = "\012"
        elseif e == "n" then pn = pn + 1; parts[pn] = "\010"
        elseif e == "r" then pn = pn + 1; parts[pn] = "\013"
        elseif e == "t" then pn = pn + 1; parts[pn] = "\009"
        elseif e == "u" then pn = pn + 1; parts[pn] = decode_u4()
        else err("bad escape \\" .. e)
        end
      else
        local j = i
        while j <= n do
          local b2 = byte_at(str, j)
          if b2 == 34 or b2 == 92 then break end
          j = j + 1
        end
        pn = pn + 1
        parts[pn] = str:sub(i, j - 1)
        i = j
      end
    end
    err("unterminated string")
  end

  local function parse_number()
    local j = i
    if str:sub(j, j) == "-" then j = j + 1 end
    if j > n then err("bad number") end
    if str:sub(j, j) == "0" then
      j = j + 1
    elseif str:sub(j, j):match("%d") then
      while j <= n and str:sub(j, j):match("%d") do j = j + 1 end
    else
      err("bad number")
    end
    if j <= n and str:sub(j, j) == "." then
      j = j + 1
      while j <= n and str:sub(j, j):match("%d") do j = j + 1 end
    end
    if j <= n and (str:sub(j, j) == "e" or str:sub(j, j) == "E") then
      j = j + 1
      if j <= n and (str:sub(j, j) == "+" or str:sub(j, j) == "-") then j = j + 1 end
      if j > n or not str:sub(j, j):match("%d") then err("bad exponent") end
      while j <= n and str:sub(j, j):match("%d") do j = j + 1 end
    end
    local chunk = str:sub(i, j - 1)
    i = j
    local num = tonumber(chunk)
    if not num then err("invalid number: " .. chunk) end
    return num
  end

  function parse_value()
    ws()
    if i > n then err("unexpected eof") end
    local c = str:sub(i, i)
    if c == "{" then
      i = i + 1
      ws()
      local t = {}
      if str:sub(i, i) == "}" then
        i = i + 1
        return t
      end
      while true do
        ws()
        local key = parse_string()
        ws()
        if str:sub(i, i) ~= ":" then err("expected :") end
        i = i + 1
        t[key] = parse_value()
        ws()
        local sep = str:sub(i, i)
        if sep == "}" then i = i + 1; return t end
        if sep ~= "," then err("expected , or }") end
        i = i + 1
      end
    elseif c == "[" then
      i = i + 1
      ws()
      local t = {}
      if str:sub(i, i) == "]" then
        i = i + 1
        return t
      end
      local idx = 1
      while true do
        t[idx] = parse_value()
        idx = idx + 1
        ws()
        local sep = str:sub(i, i)
        if sep == "]" then i = i + 1; return t end
        if sep ~= "," then err("expected , or ]") end
        i = i + 1
      end
    elseif c == '"' then
      return parse_string()
    elseif c == "-" or c:match("%d") then
      return parse_number()
    elseif str:sub(i, i + 3) == "true" then
      i = i + 4
      return true
    elseif str:sub(i, i + 4) == "false" then
      i = i + 5
      return false
    elseif str:sub(i, i + 3) == "null" then
      i = i + 4
      return nil
    else
      err("unexpected at " .. i .. ": " .. c)
    end
  end

  local v = parse_value()
  ws()
  if i <= n then err("trailing junk at " .. i) end
  return v
end

local function encode_str(s)
  local t = { '"' }
  local tn = 1
  for p = 1, #s do
    local b = s:byte(p)
    local ch = s:sub(p, p)
    if ch == '"' then tn = tn + 1; t[tn] = "\\\""
    elseif ch == "\\" then tn = tn + 1; t[tn] = "\\\\"
    elseif ch == "\008" then tn = tn + 1; t[tn] = "\\b"
    elseif ch == "\009" then tn = tn + 1; t[tn] = "\\t"
    elseif ch == "\010" then tn = tn + 1; t[tn] = "\\n"
    elseif ch == "\012" then tn = tn + 1; t[tn] = "\\f"
    elseif ch == "\013" then tn = tn + 1; t[tn] = "\\r"
    elseif b and b < 32 then tn = tn + 1; t[tn] = string.format("\\u%04x", b)
    else
      tn = tn + 1
      t[tn] = ch
    end
  end
  tn = tn + 1
  t[tn] = '"'
  return table.concat(t)
end

local function encode_val(v, depth)
  depth = depth or 0
  if depth > 64 then err("depth limit") end
  local tv = type(v)
  if v == nil then return "null" end
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return tostring(v)
  end
  if tv == "string" then return encode_str(v) end
  if tv ~= "table" then err("cannot encode " .. tv) end
  local is_array = true
  local maxk = 0
  for k in pairs(v) do
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
      is_array = false
      break
    end
    if k > maxk then maxk = k end
  end
  if is_array and maxk > 0 then
    for j = 1, maxk do
      if v[j] == nil and rawget(v, j) == nil then
        is_array = false
        break
      end
    end
  end
  if is_array and maxk > 0 then
    local parts = { "[" }
    local pn = 1
    for j = 1, maxk do
      if j > 1 then pn = pn + 1; parts[pn] = "," end
      pn = pn + 1
      parts[pn] = encode_val(v[j], depth + 1)
    end
    pn = pn + 1
    parts[pn] = "]"
    return table.concat(parts)
  end
  local keys = {}
  for k in pairs(v) do
    if type(k) ~= "string" then err("object keys must be strings") end
    keys[#keys + 1] = k
  end
  table.sort(keys)
  local parts = { "{" }
  local pn = 1
  local first = true
  for _, k in ipairs(keys) do
    if not first then pn = pn + 1; parts[pn] = "," end
    first = false
    pn = pn + 1
    parts[pn] = encode_str(k)
    pn = pn + 1
    parts[pn] = ":"
    pn = pn + 1
    parts[pn] = encode_val(v[k], depth + 1)
  end
  pn = pn + 1
  parts[pn] = "}"
  return table.concat(parts)
end

function json.encode(v)
  return encode_val(v, 0)
end

return json
