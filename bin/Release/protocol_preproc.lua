local enet    = require 'enet'
local socket = require 'socket'
local ffi     = require 'ffi'
local C       = ffi.C
local kit      = require 'kit'
local msg      = kit.msg
local pmsg     = kit.pmsg
local dump     = kit.getDump('Protocol_Init')

local EXPORT = {}

local net = nil


-- recv functions : connection receiver
local RECV = {}

RECV.TAR = function(m)
  pmsg(m)
  C.on_matched()  
  net.reset()     -- say goodbye to matcher
  net.farside(m)  -- say hello to player
end
RECV.GREETING = function(m)
  pmsg(m)
  net.gotGreeting(m.src)
  net.readyToPlay()         -- state=3
end

local recv = kit.getRecv(function (m)
  if RECV[m.T]==nil then
    dump('Incoming msg is not supported: '..m.T)
    return
  end

  RECV[m.T](m)
end)


-- outgoing messages
local function greeting(peer)
  local m = msg('GREETING')
  kit.send(m, peer)
end
local function send_iam(ip, port, peer)
  local m = msg('IAM')
  m.ip    = ip
  m.port  = port
  kit.send(m, peer)
end

EXPORT.setup = function(n) net = n end
EXPORT.recv = recv
EXPORT.send_iam = send_iam
EXPORT.greeting = greeting

return EXPORT