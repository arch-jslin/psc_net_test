local enet     = require 'enet'
local gettime  = require 'socket'.gettime
local sleep    = require 'socket'.sleep
local kit      = require 'kit'
local addr     = kit.addr
local addr_cmp = kit.addr_cmp
local addr_str = kit.addr_str
local msg      = kit.msg
local pmsg     = kit.pmsg
local dump     = kit.getDump('Server')
local lobby    = require 'lobby'

local self_ip = socket.dns.toip( socket.dns.gethostname() )
print( "Lua: Self IP: "..self_ip )
local host = enet.host_create(self_ip..":54321")

--
-- outgoing messages
--
local send = require 'kit'.send

-- assign player id (session) to client
local function URE(pid)
  local m = msg('URE')
  m.pid = pid
  return m
end

-- response player list to client
local function PLS_R(ppl, code)
  local m = msg('PLS_R', code)
  m.ppl = ppl
  return m
end

--
-- recv functions
--
local function IAM(m)
  dump(m.T)
  local peer = m.src
  local p  = lobby.join(peer)

  p.nick = m.nick
  p.addr = {
    pub=addr(m.src),
    pri={ip=m.ip, port=m.port}
  }

  local ret = URE(p.id)
  ret.ppl = lobby.plist(p.id)
  send(ret, peer)
end

local function PLS(m)
  dump(m.T)
  local peer = m.src
  local pid  = m.pid
  local ret = nil

  if lobby.contain(pid) then  -- auth
    ret = PLS_R(lobby.plist(pid), 0)
  else
    ret = PLS_R(nil, 1)       -- error
  end

  send(ret, peer)
end

local function POKE(m)
  dump(m.T)
  local peer = m.src
  local pid  = m.pid
  lobby.poke(pid)
end

local function CHAT(m)
  dump(m.T)
  local sid  = m.pid
  local txt  = m.txt
  local type = m.type
  if type=='b' then
    lobby.bcast(sid, txt)
  end
end

local RECV = {}
RECV.IAM  = IAM  -- register
RECV.PLS  = PLS  -- ask for online player list
RECV.POKE = POKE
RECV.CHAT = CHAT

local recv = require 'kit'.getRecv(function (m) RECV[m.T](m) end)

--
-- event handlers
--
local HAND = {}
HAND.receive = function(e)
  recv(e)
end

HAND.disconnect = function(e)
  print("Connect:", e.peer)
  return true
end

HAND.connect = function(e)
  print("Disconnect:", e.peer)
  local pub = addr(e.peer)
  return true
end

--
-- system functions
--
local function handle(t)
  local e = host:service(t)
  if e == nil then return false end

  local hnd = HAND[e.type]
  if hnd == nil then return false end

  return hnd(e)
end

--
-- main loop
--
ret = true
while true do
  if ret then t = 1 else t = 100 end
  ret = handle(t)     -- handle messages
  lobby.tick()
end
