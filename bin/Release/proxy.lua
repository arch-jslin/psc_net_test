local enet     = require 'enet'
local gettime  = require 'socket'.gettime
local sleep    = require 'socket'.sleep
local kit      = require 'kit'
local addr     = kit.addr
local addr_cmp = kit.addr_cmp
local addr_str = kit.addr_str
local msg      = kit.msg
local pmsg     = kit.pmsg
local dump     = kit.getDump('Proxy')
local send = require 'kit'.send

local self_ip  = socket.dns.toip( socket.dns.gethostname() )
print( "Start Proxy: "..self_ip )

--
-- variables
--
local net = {}


--
-- tool functions
--
local function read_conf()
  local function _parse(s)
  	local words = {}
  	for w in s:gmatch("%S+") do table.insert(words, w) end
    local ret = addr(words[2])
    ret.name = words[1]
    ret.key  = words[2]
    ret.num_ppl = 0
    ret.status = 'dead'  -- green/red/dead/full
    ret.conn = nil
    return ret
  end

  local file = io.open('proxy.conf', 'r')

  if file == nil then return nil end

  local machines = {}
  local count = 1
  while true do
    local line = file:read("*l")
    if line == nil then break end
    local m = _parse(line)
    machines[m.key] = m
    count = count + 1
  end
  return machines;
end


--
-- outgoing messages
--
local send = require 'kit'.send

-- assign player id (session) to client
local function PS_POKE(pid)
  -- proxy pokes game server
  local m = msg('PS_POKE')
  return m
end

local function CLI_RT_LOB()
  -- proxy responds server list to client
  local m = msg('CLI_RT_LOB')
  return m
end

--
-- recv functions
--
local function PS_POKE_R(m)
  -- update server status
  local key = tostring(m.src)
  local num = m.num_ppl
  local sta = m.status
  net.servers[key].num_ppl = num
  net.servers[key].status = sta
  dump(net.servers)
end
local function CLI_LS_LOB(m)
  -- game client ask for a live server
  dump(m)

  local res = CLI_RT_LOB()

  res.servs = {}

  table.foreach(net.servers, function(k,v)
    if v.status ~= 'dead' then
      table.insert(res.servs, {ip=v.ip, port=v.port, num_ppl=v.num_ppl, status=v.status})
    end
  end)

  send(res, m.src)
end

local RECV = {}
RECV.PS_POKE_R = PS_POKE_R
RECV.CLI_LS_LOB = CLI_LS_LOB

local recv = require 'kit'.getRecv(function (m)
  dump(m)
  RECV[m.T](m) end)

net.tm = 0
net.num_tick = 0
net.servers = nil
net.host = enet.host_create(self_ip..":10000", 1024)
net.connect = function(ip, port)
  dump('connecting to... '..ip..':'..port)
  local conn = nil
  local function foo()
    conn = net.host:connect(ip..":"..port)
    -- conn = net.host:connect(IP_LOCAL..":"..port)
  end

  local ok, err = pcall(foo)
  if not ok then dump(err) end
  return conn
end

net.connect_all = function()
  table.foreach(net.servers, function(k,v)
    if v.status == 'dead' then
      v.conn = net.connect(v.ip, v.port)
    end
  end)
end
net.poke_all = function()
  table.foreach(net.servers, function(k,v)
    if v.status ~= 'dead' then
      send(PS_POKE(), v.conn)
    end
  end)
end

--
-- event handlers
--
local HAND = {}
HAND.receive = function(e)
  recv(e)
  return true
end

HAND.disconnect = function(e)
  print("Disconnect:", e.peer)
  return true
end

HAND.connect = function(e)
  print("Connect:", e.peer)

  -- game server's conenction
  local key = tostring(e.peer)
  if net.servers[key] ~= nil then
    net.servers[key].status = 'green'
    dump(net.servers)
  end

  return true
end

--
-- system functions
--
local function handle(t)
  local e = net.host:service(t)
  if e == nil then return false end

  local hnd = HAND[e.type]
  if hnd == nil then return false end

  return hnd(e)
end

local function tick()
  if math.floor(gettime()*1000) > net.tm then
    net.num_tick = net.num_tick + 1
    net.tm = math.floor(gettime()*1000)
  end

  -- every 100ms
  if net.num_tick % 100 == 0 then

  end

  -- every 10 secs
  if net.num_tick % 10000 == 0 then
    net.poke_all()
  end

  -- every 60 secs
  if net.num_tick % 60000 == 0 then
    net.connect_all()
  end

end

--
-- main loop
--
net.servers = read_conf()
dump(net.servers)
net.connect_all()

while true do
  handle(1)     -- handle messages
  tick()
end

