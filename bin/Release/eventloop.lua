local enet    = require 'enet'
local gettime = require 'socket'.gettime
local sleep   = require 'socket'.sleep
local ffi     = require 'ffi'
local C       = ffi.C
local addr     = require 'kit'.addr
local addr_cmp = require 'kit'.addr_cmp
local msg      = require 'kit'.msg
local pmsg     = require 'kit'.pmsg
local ptab     = require 'kit'.ptab

ffi.cdef[[
void on_connected();
void on_matched();
void on_disconnected();
int  poll_from_C();
bool check_quit();
]]

local SERVER, CLIENT = 1, 2
local PORT_AS_SERVER = 2501
local PORT_AS_CLIENT = 2502
local IP_LOCAL = socket.dns.toip( socket.dns.gethostname() )
print( "Lua: Local IP: "..IP_LOCAL )
local OPPONENT = {}

-- recv functions
local function TAR(m)
  pmsg(m)
  C.on_matched()
end

local RECV = {}
RECV.TAR = TAR

local send = require 'kit'.send
local recv = require 'kit'.getRecv(function (m) RECV[m.T](m) end)

-- outgoing messages
local function IAM()
  local m = msg('IAM')
  m.ip = IP_LOCAL
  m.port = PORT_AS_CLIENT
  return m
end


-- loop
function run(sc_flag) -- global function so it can be called from C++

  local host, farside = nil, nil
  local connected = false

  if sc_flag == SERVER then
    --host = enet.host_create("localhost:12345")
    host = enet.host_create("localhost:12347")
    farside = host:connect("localhost:12345")
  elseif sc_flag == CLIENT then
    host = enet.host_create("localhost:12346")
    farside = host:connect("localhost:12345")
  end


  -- parse unpack hnd
  -- hnd pack send
  while not C.check_quit() do
    local e = host:service(1) -- 1 ms
    if e then
      if e.type == "receive" then
        print("Lua: Got origin message: ", e.data, e.peer)
        recv(e)
      elseif e.type == "connect" then
        print("Lua: connected:", e.peer)
        if not farside then
          farside = e.peer
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
      local RECV = C.poll_from_C()

      -- we might want to translate the RECV polled here to conform our networking protocol

      if farside and RECV ~= 0 then
        farside:send( tostring(RECV) )
      end
    end
  end

  if farside then
    farside:disconnect_now() -- if you disconnect here by disconnect_now()
                             -- farside is not guaranteed to get disconnect e.
  end

  print 'Lua: event loop ended.'
end
