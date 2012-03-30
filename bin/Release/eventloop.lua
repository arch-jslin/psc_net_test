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
local prep     = require 'protocol_preproc'
local play     = require 'protocol_gameplay'

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


-- connection management
net.conn_matcher = nil
net.conn_farside = nil
net.host    = nil
net.working = false

--[[ state number
0: disconnected
1: start connection, wait for greetings
2: connected
3: ready to play
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

  --ip = 'localhost'

  dump('create host '..ip..':'..port)
  net.reset()
  net.host = enet.host_create(ip..":"..port)
end

net.matcher = function(ip, port)
  local function foo()
    dump('connect to '..ip..":"..port)
    net.conn_matcher = net.host:connect(ip..":"..port)
    --net.conn_matcher = net.host:connect("localhost:12345")
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

  if net.greeting >= 5 then
    dump('wait too long... disconnect it')
    net.reset()
    if not net.farside() then
      net.state = 9
      dump('give up')
    end
  end
end

net.gotGreeting = function(src)
  net.state = 2
  net.working = true
  net.conn_farside = src
  dump('got greetings. state=2 from '..tostring(src))
end

net.readyToPlay = function()
  net.state = 3
  if net.tar.code == 0 then
    net.asServer = true
    net.asClient = false
    dump('Pose as '..'Server')
  else
    net.asServer = false
    net.asClient = true
    dump('Pose as '..'Client')
  end
end

net.tick = function(cc)
  if cc ~= 0 and cc ~= nil then
    if net.working then 
      kit.send(msg('cmd', cc), net.conn_farside)
      print("RTT: "..net.conn_farside:get_rtt())
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

net.proc_farside = function(e)
  if e.type == "receive" then

    if net.state <= 2 then
      prep.recv(e)
      dump(e.data)
    elseif net.state == 3 then
      play.recv(e)
    end

  elseif e.type == "connect" and net.state < 2 then
    prep.greeting(e.peer)
  elseif e.type == "disconnect" then
    dump("disconnected:"..tostring(e.peer))
    net.working = false
  else
    dump(e)
  end
end

net.proc_matcher= function(e)
  if e.type == "receive" then
    prep.recv(e)
  elseif e.type == "connect" then
    print("Lua: connected:", e.peer)

    if not net.conn_matcher then
      net.conn_matcher = e.peer
    end

    net.working = true
    C.on_connected()

    prep.send_iam(IP_LOCAL, PORT, e.peer)

  elseif e.type == "disconnect" then
    print("Lua: disconnected:", e.peer)
    net.working = false
    C.on_disconnected()
  else
    dump(e)
  end
end


-- Entry point
-- global function so it can be called from C++
function run(sc_flag) 
  local ok = true

  if sc_flag == SERVER then
    PORT = PORT_A
    net.init(IP_LOCAL, PORT)
    ok = net.matcher("173.255.254.41", "12345")
  elseif sc_flag == CLIENT then
    PORT = PORT_B
    net.init(IP_LOCAL, PORT)
    ok = net.matcher("173.255.254.41", "12345")
  end

  if not ok then return false end

  prep.setup(net)
  play.setup(net)

  while not C.check_quit() do

    local c = C.poll_from_C()      -- commands from c
    local e = net.host:service(1)  -- network event

    if net.state < 1 then
      if e then net.proc_matcher(e) end
    elseif net.state >= 1 then
      if e then net.proc_farside(e) end
      net.tick(c)
    end

  end

  net.reset()
  dump('event loop ended.')
end
