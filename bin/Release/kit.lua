
local mp      = require "luajit-msgpack-pure"

local EXPORT = {}

local function table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    for key, value in pairs (tt) do
      table.insert(sb, string.rep (" ", indent)) -- indent it
      if type (value) == "table" and not done [value] then
        done [value] = true
        table.insert(sb, "{\n");
        table.insert(sb, table_print (value, indent + 2, done))
        table.insert(sb, string.rep (" ", indent)) -- indent it
        table.insert(sb, "}\n");
      elseif "number" == type(key) then
        table.insert(sb, string.format("\"%s\"\n", tostring(value)))
      else
        table.insert(sb, string.format(
            "%s = \"%s\"\n", tostring (key), tostring(value)))
       end
    end
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end

local function _strtab ( tbl )
    if  "nil"       == type( tbl ) then
        return tostring(nil)
    elseif  "table" == type( tbl ) then
        return table_print(tbl)
    elseif  "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
    end
end

-- construct a message object
EXPORT.msg = function (t, c)
  local r = {T=t}
  if c ~= nil then r.C = c end
  return r
end

-- print table
EXPORT.ptab = function(tb)
  print(_strtab(tb))
end

-- pring message
EXPORT.pmsg = function(m)
  print('***** '..m.T..' *****')
  print(_strtab(m))
end

-- address data
EXPORT.addr = function (peer)
  local i,p = string.gmatch(tostring(peer), "(.+):(%w+)")()
  return {ip=i, port=p}
end

EXPORT.addr_str = function(addr)
  return (''..addr.ip)..':'..addr.port
end

EXPORT.addr_cmp = function (a,b)
  return a.ip==b.ip and a.port==b.port
end

local function curry(f)
  return function (x)
    return function (y) return f(x,y) end
  end
end

local function _parse(hnd, e)
  print('inside _parse peer=', e.peer)
  local off, m = mp.unpack(e.data)
  if (type(m)=='table') then
    m.src = e.peer
    hnd(m)
  end
end

EXPORT.getRecv = function (hnd)
  return curry(_parse)(hnd)
end

EXPORT.send = function (obj, peer)
  peer:send(mp.pack(obj))
end

local function _dump(header, text)
  print(header..': '.._strtab(text))
end

EXPORT.getDump = function(h)
  return curry(_dump)(h)
end



return EXPORT