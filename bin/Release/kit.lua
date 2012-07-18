
local mp      = require 'luajit-msgpack-pure'
local gettime = require 'socket'.gettime
local serpent = require 'serpent'
local serpent = require 'serpent'

local EXPORT  = {}

-- reverse(...) : take some tuple and return a tuple of elements in reverse order
-- e.g. "reverse(1,2,3)" returns 3,2,1
local function reverse(...)
  local function reverse_h(acc, v, ...)
    if 0 == select('#', ...) then
        return v, acc()
    else
        return reverse_h(function () return v, acc() end, ...)
    end
  end

  return reverse_h(function () return end, ...)
end

local function curry(func, num_args)
  -- currying 2-argument functions seems to be the most popular application
  num_args = num_args or 2

  if num_args <= 1 then return func end

  local function curry_h(argtrace, n)
    if 0 == n then
      return func(reverse(argtrace()))
    else
      return function (onearg)
        return curry_h(function () return onearg, argtrace() end, n - 1)
      end
    end
  end

  -- push the terminal case of argtrace into the function first
  return curry_h(function () return end, num_args)

end

EXPORT.curry = curry

-- random string generator
math.randomseed(socket.gettime()*1000)

local Chars = {}
for Loop = 0, 255 do
   Chars[Loop+1] = string.char(Loop)
end
local String = table.concat(Chars)

local Built = {['.'] = Chars}

local AddLookup = function(CharSet)
   local Substitute = string.gsub(String, '[^'..CharSet..']', '')
   local Lookup = {}
   for Loop = 1, string.len(Substitute) do
       Lookup[Loop] = string.sub(Substitute, Loop, Loop)
   end
   Built[CharSet] = Lookup

   return Lookup
end

function string.random(Length, CharSet)
   -- Length (number)
   -- CharSet (string, optional); e.g. %l%d for lower case letters and digits

   local CharSet = CharSet or '.'

   if CharSet == '' then
      return ''
   else
      local Result = {}
      local Lookup = Built[CharSet] or AddLookup(CharSet)
      local Range = table.getn(Lookup)

      for Loop = 1,Length do
         Result[Loop] = Lookup[math.random(1, Range)]
      end

      return table.concat(Result)
   end
end


EXPORT.deepcopy = function (object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

-- construct a message object
-- T = message type
-- C = returning code (optional)
EXPORT.msg = function (t, c)
  local r = {T=t}
  if c ~= nil then r.C = c end
  return r
end

-- pring message
EXPORT.pmsg = function(m)
  print(serpent.printsing(m))
end

EXPORT.getDump = function(h)
  local function _dump(header, text)
    print(header..': '..serpent.printmult(text))
  end
  return curry(_dump)(h)
end

-- tool functions for address
EXPORT.addr = function (peer)
  local i,p = string.gmatch(tostring(peer), "(.+):(%w+)")()
  return {ip=i, port=p}
end

EXPORT.addr_str = function(addr)
  return (''..addr.ip)..':'..addr.port
end

EXPORT.addr_cmp = function (a,b)
  if a ==nil or b==nil then return false end
  return a.ip==b.ip and a.port==b.port
end

local function _parse(hnd, e)
  -- print('inside _parse peer=', e.peer)
  local off, m = mp.unpack(e.data)
  if (type(m)=='table') then
    m.src = e.peer
    hnd(m)
  else
    dump('received command is not an object: '..m)
  end
end

EXPORT.getRecv = function (hnd)
  return curry(_parse)(hnd)
end

EXPORT.send = function (obj, peer)
  peer:send(mp.pack(obj))
end

-- prepare additional info for connection
EXPORT.addr_ext = function(tar)
  -- for ns method 3
  tar.pubs = {}
  for i = 1, 5, 1 do
    tar.pubs[i] = {ip=tar.pub.ip, port=tar.pub.port+i}
  end

  -- for ns method 4
  tar.pubalt = {ip=tar.pub.ip, port=tar.pub.port+1000}
  tar.prialt = {ip=tar.pri.ip, port=tar.pri.port+1000}
  return tar
end


EXPORT.helper = {}
EXPORT.helper.keepalive = function(th)
  local dump = EXPORT.getDump('keepalive')

  local timetb = {}  -- time table
  local THRESHOLD = th or 5

  local _name = nil
  local _recv = nil
  local _send = function(peer)
    local m = EXPORT.msg(_name)    -- PS_POKE
    EXPORT.send(m, peer)
  end

  local function _poke(key)
    timetb[key] = os.time()
  end

  local function _bind(name, tb, cb)
    _name = name
    _recv = function(m)
      -- dump(m.T)
      cb(m)
      _poke(tostring(m.src))
    end
    tb[name..'_R'] = _recv   -- PS_POKE_R
  end

  local function _num()
    local cnt = 0
    table.foreach(timetb, function(k,v)
      cnt = cnt + 1
    end)
    return cnt
  end
  local function _chk_zombie(cbt, cbf)
    table.foreach(timetb, function(k,v)
      if os.time() - v > THRESHOLD then
        -- print(_name, k, v, ' is zombie')
        if (cbt~=nil) then cbt(k) end -- is a zombie
      else
        -- print(_name, k, v, ' is not zombie')
        if (cbf~=nil) then cbf(k) end -- not a zombie
      end
    end)
  end

  local function _del(key)
    timetb[key] = nil
  end

  return
  { poke = _poke
  , num  = _num
  , del  = _del
  , chk_zombie = _chk_zombie
  , bind = _bind
  , send = _send
  }
end

local dump = EXPORT.getDump('Kit')

EXPORT.kindof = function (base, n) return (n % base == 0) end
EXPORT.eq = function (l, r) return l==r end

--
-- experimental functions
--
function gte(l, r)
  return l>=r
end
function lte(l, r)
  return l<=r
end

function check(...)
  local arg = {...}
  for i = 1, select('#',...)-1 do
    dump('try '..i..tostring(arg[i]))
    if not arg[i] then return end
  end

  dump('call ')
  arg[select('#',...)]() -- the last argument is callback function
end

EXPORT.str_test1 = string.random(1024)
EXPORT.str_test2 = string.random(10240)

return EXPORT





