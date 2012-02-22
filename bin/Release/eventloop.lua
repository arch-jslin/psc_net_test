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

-- connection management
local net  = {}
net.host_matcher = nil
net.client = nil  -- enet.host_create:connect
net.host   = nil  -- pose as a client or a server
net.state  = nil
net.type   = nil  -- 1:server 2:client
net.tar    = nil  -- target information
net.tm     = 0
net.init = function(tar)
  net.reset()
  net.tar = tar
end
net.reset = function()
  if net.client then net.client:disconnect() end
  net.state  = nil
  net.type   = nil
  net.client = nil
end
net.runAsClient = function()
  if net.tar == nil then
    dump('Needs target address')
    return
  end

  net.client = net.host:connect(addr_str(net.tar.pri))
  net.type = 1
  dump('Connect to '..tostring(net.client))
end
net.isReady = function()
end
net.tick = function()
  local e = net.host:service(1) -- 1 ms

  if e then
    if e.type == "receive" then
      print("Lua: Got origin message: ", e.data, e.peer)
    elseif e.type == "connect" then
      e.peer:send("Greetings.")
      dump('connected: '..e.peer)
    elseif e.type == "disconnect" then
      print("Lua: disconnected:", e.peer)
    else
      dump(e)
    end
  end


  if (os.time() - net.tm > 0) then
    print(os.time())
    net.tm = os.time()
  end
end

-- recv functions
local function TAR(m)
  C.on_matched()

  -- say goodbye to matcher server
  net.host_matcher:disconnect_now()

  -- say hello to target
  net.init(m)
  net.state = 1
  net.runAsClient()
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
      net.host_matcher = net.host:connect('173.255.254.411:12345')
    end
    local ret = pcall(foo)
    --net.host_matcher = net.host:connect("173.255.254.411:12345")

  elseif sc_flag == CLIENT then
    PORT = PORT_B
    net.host = enet.host_create(IP_LOCAL..":"..PORT)
    -- net.host_matcher = net.host:connect("localhost:12345")
    net.host_matcher = net.host:connect("173.255.254.41:12345")
  end

  -- parse unpack hnd
  -- hnd pack send
  while not C.check_quit() do
    repeat -- wrapper for continue

    -- Stage 2: connect to target
    if net.state == 1 then
      net.tick()
      break
    end


    -- Stage 1: connect to matcher
    local e = net.host:service(1) -- 1 ms
    if e then
      if e.type == "receive" then
        --print("Lua: Got origin message: ", e.data, e.peer)
        recv(e)
      elseif e.type == "connect" then
        print("Lua: connected:", e.peer)
        if not net.host_matcher then
          net.host_matcher = e.peer
        end
        C.on_connected()
        connected = true
        --e.peer:send("Greetings.")
        send(IAM(), e.peer)
      elseif e.type == "disconnect" then
        print("Lua: disconnected:", e.peer)
        C.on_disconnected()
      end
    end



    if connected then
      local RECV_C = C.poll_from_C()
      -- we might want to translate the RECV polled here to conform our networking protocol
      if net.host_matcher and RECV_C ~= 0 then
        net.host_matcher:send( tostring(RECV_C) )
      end
    end

  until true   -- repeat
  end          -- while

  if net.host_matcher then
    net.host_matcher:disconnect_now() -- if you disconnect here by disconnect_now()
                             -- net.host_matcher is not guaranteed to get disconnect e.
  end

  print 'Lua: event loop ended.'
end
