local enet    = require 'enet'
local gettime = require 'socket'.gettime
local sleep   = require 'socket'.sleep
local addr     = require 'kit'.addr
local addr_cmp = require 'kit'.addr_cmp
local msg      = require 'kit'.msg
local pmsg     = require 'kit'.pmsg
local ptab     = require 'kit'.ptab

local host = enet.host_create"localhost:12345"
local self_ip = socket.dns.toip( socket.dns.gethostname() )
print( "Lua: Self IP: "..self_ip )
local ppl = {}

-- recv functions
local function IAM(m)
  pmsg(m)
  local cli = {}
  cli.pub = addr(m.src)
  cli.pri = {ip=m.ip, port=m.port}
  cli.time = os.time()
  cli.peer = m.src
  table.insert(ppl, cli)
end

local RECV = {}
RECV.IAM = IAM

local send = require 'kit'.send
local recv = require 'kit'.getRecv(function (m) RECV[m.T](m) end)

-- outgoing messages
local function TAR(from)
  local m = msg('TAR')
  m.pub = from.pub
  m.pri = from.pri
  return m
end


-- event handlers
local function onRecv(e)
  print("Got message: ", e.data, e.peer)
  recv(e)
end
local function onConnect(e)
  print("Connect:", e.peer)
  --host:broadcast("new client connected")
end
local function onDisconnect(e)
  print("Disconnect:", e.peer)
  local pub = addr(e.peer)
  table.foreachi(ppl, function(idx, val)
    if addr_cmp(val.pub, pub) then table.remove(ppl, idx) end
  end)
end
local function onMisc(e)
  print("Got e", e.type, e.peer)
end

-- system functions
local function match()
  local sz = table.getn(ppl)
  if sz > 1 then
    local p1 = ppl[1]
    local p2 = ppl[2]

    send(TAR(p1), p2.peer)
    send(TAR(p2), p1.peer)

    table.remove(ppl, 1)
    table.remove(ppl, 1)
    --p1.peer:disconnect()
    --p2.peer:disconnect()
  end
end

local function handle(t)
  local e = host:service(t)

  if e == nil then return false end

  if e.type == "receive" then
    onRecv(e)
  elseif e.type == "disconnect" then
    onDisconnect(e)
  elseif e.type == "connect" then
    onConnect(e)
  end

  return true
end

-- main loop
ret = true
while true do
  if ret then t = 1 else t = 100 end
  ret = handle(t)     -- handle messages
  match()             -- match peers
end
