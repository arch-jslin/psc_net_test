local enet    = require 'enet'
local socket = require 'socket'
local ffi     = require 'ffi'
local C       = ffi.C
local kit      = require 'kit'
local msg      = kit.msg
local pmsg     = kit.pmsg
local dump     = kit.getDump('Protocol_Gameplay')

local EXPORT = {}


-- recv functions : gameplay receiver

local RECV = {}
RECV.MOV = function(m)
  pmsg(m)
end
RECV.HIT = function(m)
  pmsg(m)
end
RECV.DIE = function(m)
  pmsg(m)
end
RECV.POKE = function(m)
  pmsg(m)
end
RECV.GREETING = function()
  -- do nothing for duplicated greetings
end

local recv = kit.getRecv(function (m)
  if RECV[m.T]==nil then
    dump('Incoming msg is not supported: '..m.T)
    return
  end

  RECV[m.T](m)
end)

-- outgoing messages
local function poke(peer)
  local m = msg('POKE')
  m.t = os.time()
  kit.send(m, peer)
end

local function move(peer, x,y)
  local m = msg('MOV')
  m.x = x
  m.y = y
  m.t = os.time()
  kit.send(m, peer)
end
local function hit(peer, x,y)
  local m = msg('HIT')
  m.x = x
  m.y = y
  m.t = os.time()
  kit.send(m, peer)
end

EXPORT.setup = function(n) net = n end
EXPORT.recv = recv
EXPORT.poke = poke
EXPORT.move = move
EXPORT.hit = hit

return EXPORT