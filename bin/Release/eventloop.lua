local enet    = require 'enet'
local gettime = require 'socket'.gettime
local sleep   = require 'socket'.sleep
local ffi     = require 'ffi'
local C       = ffi.C
local kit      = require 'kit'
local addr     = kit.addr
local addr_cmp = kit.addr_cmp
local addr_str = kit.addr_str
local msg      = kit.msg
local pmsg     = kit.pmsg
local ptab     = kit.ptab
local dump     = kit.getDump('Lua')
local ns       = require 'net_strategy'


ffi.cdef[[
void on_connected();
void on_matched();
void on_disconnected();
int  poll_from_C();
bool check_quit();
]]

local PORT_A = 2501
local PORT_B = 2502
local PORT = 2501
local IP_LOCAL = socket.dns.toip( socket.dns.gethostname() )
dump( "Lua: Local IP: "..IP_LOCAL )
local OPPONENT = {}

local SERVER=1
local CLIENT=2

local net  = {}

-- recv functions
local function TAR(m)
  dump(m)
  C.on_matched()  
  net.host_matcher:disconnect_now() -- say goodbye to matcher
  ns.connect(net, m)
end

local RECV = {}
RECV.TAR = TAR

local send = kit.send
local recv = kit.getRecv(function (m)
  if RECV[m.T]==nil then
    dump('Incoming msg is not supported: '..m.T)
    return
  end

  RECV[m.T](m)
end)

-- outgoing messages
local function IAM()
  local m = msg('IAM')
  m.ip    = IP_LOCAL
  m.port  = PORT
  return m
end

-- connection management
net.host_matcher = nil
net.client = nil  -- enet.host_create:connect
net.host   = nil  -- pose as a client or a server
net.working = false

--[[ state number
0: disconnected
1: start connection, wait for greetings
2: connected
9: give up
]]
net.state  = 0

net.type   = nil  -- 1:server 2:client
net.tar    = nil  -- target information
net.tm     = 0
net.greeting = 0

net.tarPriAddr = function()
  return addr_str(net.tar.pri)
end

net.tarPubAddr = function(i)
  if i ~= nil and i > 0 and i < 6 then
    return addr_str(net.tar.pubs[i])
  end
  return addr_str(net.tar.pub)
end

net.init = function(tar)
  net.reset()
  net.tar = tar
  net.tar.pubs = {} -- for ns method 3
  for i = 1, 5, 1 do
    net.tar.pubs[i] = {ip=net.tar.pub.ip, port=net.tar.pub.port+i}
  end  
end

net.reset = function()
  if net.client then net.client:disconnect() end
  if net.host_matcher then net.host_matcher:disconnect() end
  net.state  = 0
  net.type   = nil
  net.client = nil
  net.greeting = 0
  net.working = false
end

net.waitGreeting = function()
    dump('wait for greetings...'..tostring(net.greeting))
    net.greeting = net.greeting + 1

  if net.greeting >= 2 then
    dump('wait too long... disconnect it')
    net.reset()
    local ret = ns.connect_next()
    if ret == false then
      net.state = 9
    end
  end
end

net.gotGreeting = function(e)
  net.state = 2
  net.working = true
  dump('got greetings. state=2 from '..tostring(e.peer))
end

net.tick = function()
  local e = net.host:service(1) -- 1 ms

  if e then
    if e.type == "receive" then
      -- print("Lua: Got origin message: ", e.data, e.peer)
      if e.data=='Greetings' then
        net.gotGreeting(e)
      else
        recv(e)
      end
    elseif e.type == "connect" then
      e.peer:send("Greetings")
      -- dump('connected: '..tostring(e.peer))
    elseif e.type == "disconnect" then
      print("Lua: disconnected:", e.peer)
      net.working = false
    else
      dump(e)
    end
  end


  if (os.time() - net.tm > 0) then
    dump(os.time())
    net.tm = os.time()
    if net.state==1 then
      net.waitGreeting()
    end
  end
end

net.connectTarget = function()
  if net.state < 1 then
    return false
  end
  net.tick()
  return true
end

net.connectMatcher= function()
  if net.state > 0 then
    return false
  end

  local e = net.host:service(1) -- 1 ms
  if e then
    if e.type == "receive" then
      recv(e)
    elseif e.type == "connect" then
      print("Lua: connected:", e.peer)
      if not net.host_matcher then
        net.host_matcher = e.peer
      end
      net.working = true
      C.on_connected()
      send(IAM(), e.peer)
    elseif e.type == "disconnect" then
      print("Lua: disconnected:", e.peer)
      net.working = false
      C.on_disconnected()
    end
  end

  return true
end





-- entry
function run(sc_flag) -- global function so it can be called from C++

  --local host = nil
  local connected = false

  --IP_LOCAL = 'localhost'
  if sc_flag == SERVER then
    PORT = PORT_A
    net.host = enet.host_create(IP_LOCAL..":"..PORT)
    -- net.host_matcher = net.host:connect("localhost:12345")
    
    local function foo()
      net.host_matcher = net.host:connect('173.255.254.41:12345')
    end

    local ok, err = pcall(foo)
    if ok==false then
      dump(err)
      return false
    end

  elseif sc_flag == CLIENT then
    PORT = PORT_B
    net.host = enet.host_create(IP_LOCAL..":"..PORT)
    -- net.host_matcher = net.host:connect("localhost:12345")
    net.host_matcher = net.host:connect("173.255.254.41:12345")
  end

  -- parse, unpack, hnd
  -- hnd, pack, send
  while not C.check_quit() do
    -- commands from app
    if net.working then
      local RECV_C = C.poll_from_C()
      if RECV_C ~= 0 then
        --dump(RECV_C)
      end
    end

    -- networking
    if net.connectTarget() then
    elseif net.connectMatcher() then
    end

  end

  net.reset()
  dump('event loop ended.')
end
