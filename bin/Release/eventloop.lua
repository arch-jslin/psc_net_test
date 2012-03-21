local enet    = require 'enet'
local socket = require 'socket'
-- local gettime = require 'socket'.gettime
-- local sleep   = require 'socket'.sleep
local ffi     = require 'ffi'
local C       = ffi.C
local kit      = require 'kit'
local addr     = kit.addr
local addr_cmp = kit.addr_cmp
local addr_str = kit.addr_str
local msg      = kit.msg
local pmsg     = kit.pmsg
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
local SERVER=1
local CLIENT=2

local net  = {}

-- recv functions
local function TAR(m)
  pmsg(m)
  C.on_matched()  
  net.reset()     -- say goodbye to matcher
  net.farside(m)
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
net.conn_matcher = nil
net.conn_farside = nil
net.host    = nil
net.working = false

--[[ state number
0: disconnected
1: start connection, wait for greetings
2: connected
9: give up
]]
net.state  = 0
net.tar    = nil  -- farside information
net.tm     = 0
net.greeting = 0

function net:tarPriAddr(i)
  if i ~= nil then
    return addr_str(net.tar.prialt)
  end
  return addr_str(net.tar.pri)
end

function net:tarPubAddr(i)
  if i ~= nil and i > 0 and i < 6 then
    return addr_str(net.tar.pubs[i])
  elseif i ~= nil and i > 100 then
    return addr_str(net.tar.pubalt)
  end
  return addr_str(net.tar.pub)
end

net.init = function(ip, port)
  dump('create host '..ip..':'..port)
  net.reset()
  net.host = enet.host_create(ip..":"..port)
end

net.matcher = function(ip, port)
  local function foo()
    --net.conn_matcher = net.host:connect(ip..":"..port)
    net.conn_matcher = net.host:connect("localhost:12345")
  end

  local ok, err = pcall(foo)

  if not ok then dump(err) end
  
  return ok
end

net.farside = function(info)
  if info then
    return ns.connect(net, info)
  end
  return ns.connect_next()
end

net.setup = function(tar)
  net.reset()
  
  net.iam = {}
  net.iam.pri = {ip=IP_LOCAL, port=PORT}  
  net.iam.prialt = {ip=IP_LOCAL, port=PORT+1000}  

  net.tar = tar

  -- for ns method 3
  net.tar.pubs = {} 
  for i = 1, 5, 1 do
    net.tar.pubs[i] = {ip=net.tar.pub.ip, port=net.tar.pub.port+i}
  end  

  -- for ns method 4
  net.tar.pubalt = {ip=net.tar.pub.ip, port=net.tar.pub.port+1000} 
  net.tar.prialt = {ip=net.tar.pri.ip, port=net.tar.pri.port+1000} 

end

net.reset = function()
  if net.conn_farside then net.conn_farside:disconnect() end
  if net.conn_matcher then net.conn_matcher:disconnect() end
  net.state  = 0
  net.greeting = 0
  net.working = false
end

net.waitGreeting = function()
    dump('wait for greetings...'..tostring(net.greeting))
    net.greeting = net.greeting + 1

  if net.greeting >= 2 then
    dump('wait too long... disconnect it')
    net.reset()
    if not net.farside() then
      net.state = 9
      dump('give up')
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
      dump("disconnected:"..tostring(e.peer))
      net.working = false
    else
      dump(e)
    end
  end


  if (os.time() - net.tm > 0) then
    net.tm = os.time()

    if net.tm % 10 == 0 then
      dump('tm='..net.tm)
    end

    if net.state==1 then
      net.waitGreeting()
    end
  end
end

net.proc_farside = function()
  if net.state < 1 then
    return false
  end
  net.tick()
  return true
end

net.proc_matcher= function()
  if net.state > 0 then
    return false
  end

  local e = net.host:service(1) -- 1 ms
  if e then
    if e.type == "receive" then
      recv(e)
    elseif e.type == "connect" then
      print("Lua: connected:", e.peer)
      if not net.conn_matcher then
        net.conn_matcher = e.peer
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


-- Entry point
-- global function so it can be called from C++
function run(sc_flag) 
  local ok = true

  IP_LOCAL = 'localhost'
  if sc_flag == SERVER then
    PORT = PORT_A
    net.init(IP_LOCAL, PORT)
    ok = net.matcher('173.255.254.41', 12345)
  elseif sc_flag == CLIENT then
    PORT = PORT_B
    net.init(IP_LOCAL, PORT)
    ok = net.matcher('173.255.254.41', 12345)
  end

  if not ok then return false end

  while not C.check_quit() do

    -- commands from app
    if net.working then
      local RECV_C = C.poll_from_C()
      if RECV_C ~= 0 then
        --dump(RECV_C)
      end
    end

    -- networking
    if net.proc_farside() then
    elseif net.proc_matcher() then
    end

  end

  net.reset()
  dump('event loop ended.')
end
