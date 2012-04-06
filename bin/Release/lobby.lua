local kit      = require 'kit'
local dump     = kit.getDump('Lua-Lobby')
local msg      = kit.msg
local sleep   = require 'socket'.sleep
local EXPORT = {}

-- Constants
local const = {
  MAX_PLAYER_A_ROOM=2,
}

-- broadcast message
local function CHAT(sid, txt, type) 
  local m = msg('CHAT')
  m.sid = sid  -- source
  m.txt = txt  -- content
  m.type= type
  return m
end

-- internal function & data structure
local function _player(peer)
	local p = {}

  -- basic information
	p.id = string.random(6, '%l%d')
	p.status = 'idle'

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

  r.size = function() return table.getn(players) end

  r.get = function(pid)
    return players[pid]
  end
	
  r.add = function(peer)
    if r.size() > const.MAX_PLAYER_A_ROOM then return nil end

    local ppl = _player(peer)
    players[tostring(ppl.id)] = ppl
    return ppl
	end

	r.del = function(pid, reason)
    players[pid].disconnect()
    players[pid] = nil
    local msg = 'delete '..pid
    if reason ~= nil then dump(msg..' Reason: '..reason) end
	end

	r.tell = function(sid, pid, txt, type)
    dump('tell '..pid..' '..txt)    
    local ppl = r.get(pid)
    if ppl == nil then return end

    local m = CHAT(sid, txt, type)
    dump(m)
    kit.send(m, ppl.peer)
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
    table.foreach(players, function(k,v) 
      if r.is_zombie(k)==true then r.del(k, 'is zombie') end
    end)
  end

  r.is_zombie = function(pid)
    local tmp = r.get(pid)
		return ( (now - r.get(pid).tm_poke) > 180 ) -- 3 mins 
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
  room.bcast(msg, pid)
end

local function status(pid, sta)  -- update plsyer's status
  room.poke(pid)
  local ppl = room.get(pid)
  if ppl == nil then return false end

  ppl.status = sta
  return true
end

local function pinfo(pid)        -- info about player
  room.poke(pid)
  local ppl = room.get(pid)
  if ppl == nil then return nil end

  local info = {}
  info.pid = pid
  info.status = ppl.status
  info.addr = ppl.addr
  info.nick = ppl.info
  return info
end

local function plist(pid)       -- list players in the room
  room.poke(pid)
  local ls = {}                 -- except the requester
  table.foreach(room.all(), function(k,v) 
    if pid ~= k then 
      local ppl = pinfo(k)
      table.insert(ls, ppl) 
    end
  end)
  return ls
end

EXPORT.connect    = connect
EXPORT.disconnect = disconnect
EXPORT.join    = join
EXPORT.leave   = leave
EXPORT.say     = say
EXPORT.status  = status
EXPORT.plist   = plist
EXPORT.pinfo   = pinfo
EXPORT.bcast   = function(sid,txt) room.bcast(sid,txt) end
EXPORT.contain = function(pid) return (room.get(pid) ~= nil) end
EXPORT.poke    = function(pid) room.poke(pid) end
EXPORT.tick    = function() room.tick() end
EXPORT.hi      = function() dump('hi') end

return EXPORT