local kit    = require 'kit'
local dump   = kit.getDump('Lua-Lobby')
local msg    = kit.msg
local sleep  = require 'socket'.sleep
local EXPORT = {}

-- Constants
local Const = {
  MAX_PLAYER_A_ROOM=10000,
  STATE={
    IDLE='idle',
    PLAYING='playing'
  }
}

-- broadcast message
local function CHAT(sid, txt, type)
  local m = msg('CHAT')
  m.sid  = sid  -- source
  m.txt  = txt  -- content
  m.type = type
  return m
end

-- internal function & data structure
local function _player(peer)
	local p = {}

  -- basic information
	p.id = string.random(6, '%l%d')
	p.status = Const.STATE.IDLE

  -- server-side management
	p.tm_poke = os.time()  -- last time been poked
	p.tm_login = os.time() -- login time

  -- networking
  p.peer = peer
  p.addr = nil
  p.nick = nil

  p.disconnect = function()
    p.peer:disconnect()
  end
	return p
end

local function _room(c)
	local r = {}
	local players = {}
  local now  = os.time()
  local conn = c
  local num_players = 0
  local keepalive = kit.helper.keepalive(5)

  r.num_ppl = function() return num_players end

  r.get = function(pid)
    return players[pid]
  end

  r.lookup = function(e, cb)
    table.foreach(players, function(k,v)
      if tostring(v.peer)==tostring(e.peer) then
        cb(k)
      end
    end)
  end

  r.add = function(peer)
    if r.num_ppl() > Const.MAX_PLAYER_A_ROOM then return nil end

    local p = _player(peer)
    local pid = tostring(p.id)
    players[pid] = p
    keepalive.poke(pid)
    return p
	end

	r.del = function(pid, reason)
    players[pid].disconnect()
    players[pid] = nil
    keepalive.del(pid)
    if reason ~= nil then dump('delete '..pid..' Reason: '..reason) end
	end

	r.tell = function(sid, pid, txt, type)
    dump('tell '..pid..' '..txt)
    local p = r.get(pid)
    if p == nil then return end

    local m = CHAT(sid, txt, type)
    dump(m)
    kit.send(m, p.peer)
	end

	r.bcast = function(sid, txt)
    keepalive.poke(sid)
    table.foreach(players, function(k,v)
      if sid ~= k then
        r.tell(sid, k, txt, 'b')
      end
    end)
	end

  r.all = function()
    return players
  end

  r.status = function(pid, sta)
    keepalive.poke(pid)
    local p = r.get(pid)
    if p == nil then return false end
    p.status = sta
    return true
  end

  r.peer = function (pid)
    keepalive.poke(pid)
    local p = r.get(pid)
    if p == nil then return nil end
    return p.peer
  end

  r.pinfo = function (pid)        -- info about player
    local p = r.get(pid)
    if p == nil then return nil end

    local info  = {}
    info.pid    = pid
    info.status = p.status
    info.addr = p.addr
    info.nick = p.nick
    return info
  end
  r.poke = function(pid)
    keepalive.poke(pid)
  end

  r.tick = function()
    if (os.time() - now > 0) then
      now = os.time()
      r.tick_sec()
    end
	end

  r.tick_sec = function()
    keepalive.chk_zombie(function(key)
      r.del(key, 'zombie')
    end)

    num_players = keepalive.num()

    if now % 10 == 0 then
      dump('#players online: '..num_players)
    end
  end

	return r
end

local room = _room()

local function list_players(pid) -- list players in the room
  room.poke(pid)
  local ls = {}                  -- except the requester
  table.foreach(room.all(), function(k,v)
    if pid ~= k then
      local p = room.pinfo(k)
      table.insert(ls, p)
    end
  end)
  return ls
end

local function table_players(pid) -- list players in the room
  room.poke(pid)
  local tb = {}                  -- except the requester
  table.foreach(room.all(), function(k,v)
    if pid ~= k then
      local p = room.pinfo(k)
      tb[p.pid] = p
    end
  end)
  return tb
end

local function disconnect(e)
  room.lookup(e, room.del)
end

-- EXPORT.connect    = connect
EXPORT.disconnect    = disconnect
EXPORT.list_players  = list_players
EXPORT.table_players = table_players
EXPORT.contain = function(pid) return (room.get(pid) ~= nil) end
EXPORT.peer    = room.peer   -- peer
EXPORT.join    = room.add    -- join
EXPORT.leave   = room.del    -- leave
EXPORT.say     = room.bcast  -- say
EXPORT.status  = room.status
EXPORT.pinfo   = room.pinfo  -- pinfo
EXPORT.num_ppl = room.num_ppl
EXPORT.tick    = room.tick
EXPORT.poke    = room.poke
EXPORT.bcast   = room.bcast

return EXPORT
