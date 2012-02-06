local enet    = require 'enet'
local gettime = require 'socket'.gettime
local sleep   = require 'socket'.sleep
local ffi     = require 'ffi'
local C = ffi.C

ffi.cdef[[
void on_connected();
void on_matched();
void on_disconnected();
int  poll_from_C();
bool check_quit();
]]

local SERVER, CLIENT = 1, 2

function TAR(v)
  print(debug.getinfo(1, "n"), v)
  C.on_matched()
end
local CMD = {}
CMD.TAR = TAR

-- protocol
function parse(s)
  for k, v in string.gmatch(s, "(%w+)=(.+)") do
    CMD[k](v)
  end
end

-- loop
function run(sc_flag) -- global function so it can be called from C++
  local self_ip = socket.dns.toip( socket.dns.gethostname() )
  print( "Lua: Self IP: "..self_ip )

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

  while not C.check_quit() do
    local event = host:service(1) -- 1 ms
    if event then
      if event.type == "receive" then
        parse(event.data)
        print("Lua: Got origin message: ", event.data, event.peer)

        -- process event.data here

      elseif event.type == "connect" then
        print("Lua: connected:", event.peer)
        if not farside then
          farside = event.peer
        end
        C.on_connected()
        connected = true
        event.peer:send("Greetings.")
      elseif event.type == "disconnect" then
        print("Lua: disconnected:", event.peer)
        C.on_disconnected()
      end
    end

    if connected then
      local cmd = C.poll_from_C()

      -- we might want to translate the cmd polled here to conform our networking protocol

      if farside and cmd ~= 0 then
        farside:send( tostring(cmd) )
      end
    end
  end

  if farside then
    farside:disconnect_now() -- if you disconnect here by disconnect_now()
                             -- farside is not guaranteed to get disconnect event.
  end

  print 'Lua: event loop ended.'
end
