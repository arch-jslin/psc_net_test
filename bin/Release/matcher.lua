local enet    = require 'enet'
local gettime = require 'socket'.gettime
local sleep   = require 'socket'.sleep


local host = enet.host_create"localhost:12345"
local self_ip = socket.dns.toip( socket.dns.gethostname() )
print( "Lua: Self IP: "..self_ip )
local ppl = {}

--[[ Protocols

onConnect:
  add peer to ppl
onDisconnect:
  remove peer from ppl
  
match:
  match two peers
  
]]


-- event handlers
function onRecv(e)
  print("Got message: ", e.data, e.peer)
  e.peer:send("howdy back at ya")
end
function onConnect(e)
  print("Connect:", e.peer)
  table.insert(ppl, e.peer)
  --host:broadcast("new client connected")
end
function onDisconnect(e)
  print("Disconnect:", e.peer)
  local tar = tostring(e.peer)
  table.foreachi(ppl, function(i,v)
    if tar==tostring(v) then table.remove(ppl, i) end
  end)
end
function onMisc(e)
  print("Got e", e.type, e.peer)
end

-- system functions
function match()
  local sz = table.getn(ppl)
  if sz > 1 then
    local p1 = ppl[1]
    local p2 = ppl[2]    
    p1:send(string.format('%s|%s', 'TAR', tostring(p2)))
    p2:send(string.format('%s|%s', 'TAR', tostring(p1)))
    table.remove(ppl, 1)
    table.remove(ppl, 1)
  end
end

function handle(t)
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
