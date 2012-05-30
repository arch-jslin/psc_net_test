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

local function _room(c)  -- connection
	local r = {}
	local players = {}
  local now = os.time()
  local conn = c
  local num_players = 0

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
    players[tostring(p.id)] = p
    return p
	end

	r.del = function(pid, reason)
    players[pid].disconnect()
    players[pid] = nil
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
    table.foreach(players, function(k,v)
      if sid ~= k then
        r.tell(sid, k, txt, 'b')
      end
    end)
	end

  r.poke = function(pid)
    local p = r.get(pid)
    if p ~= nil then p.tm_poke = os.time() end
	end

  r.all = function()
    return players
  end

  r.tick = function()
    if (os.time() - now > 0) then
      now = os.time()
      r.tick_sec()
    end
	end

  r.tick_sec = function()
    local cnt = 0
    table.foreach(players, function(k,v)
      if r.is_zombie(k)==true then
        r.del(k, 'zombie')
      end
      cnt = cnt + 1
    end)

    num_players = cnt

    if now % 10 == 0 then
      dump('#players online: '..num_players)
    end
  end

  r.is_zombie = function(pid)
    local tmp = r.get(pid)
		return ( (now - r.get(pid).tm_poke) > 5 ) -- 5 secs
	end

	return r
end

local room = _room()

-- external interface
local function join(addr, peer)  -- player want to join
  return room.add(addr, peer)
end

local function leave(pid)        -- player leaves room
  room.del(pid)
end

local function say(pid, msg)     -- chat
  room.poke(pid)
  dump(tostring(pid)..' says: '..msg)
  room.bcast(pid, msg)
end

local function status(pid, sta)  -- update player's status
  room.poke(pid)
  local p = room.get(pid)
  if p == nil then return false end
  p.status = sta
  return true
end

local function pinfo(pid)        -- info about player
  room.poke(pid)
  local p = room.get(pid)
  if p == nil then return nil end

  local info  = {}
  info.pid    = pid
  info.status = p.status
  info.addr = p.addr
  info.nick = p.nick
  return info
end

local function peer(pid)         -- info about player
  local p = room.get(pid)
  if p == nil then return nil end
  return p.peer
end

local function list_players(pid) -- list players in the room
  room.poke(pid)
  local ls = {}                  -- except the requester
  table.foreach(room.all(), function(k,v)
    if pid ~= k then
      local p = pinfo(k)
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
      local p = pinfo(k)
      tb[p.pid] = p
    end
  end)
  return tb
end

local function num_ppl()
  return room.num_ppl()
end

local function disconnect(e)
  room.lookup(e, room.del)
end

-- EXPORT.connect    = connect
EXPORT.peer    = peer
EXPORT.disconnect = disconnect
EXPORT.join    = join
EXPORT.leave   = leave
EXPORT.say     = say
EXPORT.status  = status
EXPORT.list_players  = list_players
EXPORT.table_players = table_players
EXPORT.pinfo   = pinfo
EXPORT.num_ppl = num_ppl
EXPORT.bcast   = function(sid,txt) room.bcast(sid,txt) end
EXPORT.contain = function(pid) return (room.get(pid) ~= nil) end
EXPORT.poke    = function(pid) room.poke(pid) end
EXPORT.tick    = function() room.tick() end
EXPORT.hi      = function() dump('hi') end

return EXPORT
