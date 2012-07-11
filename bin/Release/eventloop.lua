--[=[
local basepath = require 'rc/script/helper'.basepath
package.path = basepath()..[[rc/script/net/?.lua;]]..package.path
package.cpath= basepath()..[[rc/script/net/?.dll;]]..package.cpath
-- above lines added for further merges with cubeat-core
--]=]

local enet     = require 'enet'
local socket   = require 'socket'
local gettime  = require 'socket'.gettime
local sleep    = require 'socket'.sleep
local ffi      = require 'ffi'
local C        = ffi.C
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
local kindof   = kit.kindof
local eq       = kit.eq

ffi.cdef[[
void on_connected(char const*);
void on_matched(char const*);
void on_received(char const*);
void on_disconnected(char const*);
char const* poll_from_C();
bool check_quit();
]]

local PORT_A = 2501
local PORT_B = 2502
local PORT   = 2501
local IP_LOCAL = socket.dns.toip( socket.dns.gethostname() )
local SERVER = 1
local CLIENT = 2

local net  = {}
local game = {}
game.proxy_addr = {ip="192.168.1.209", port=10000}
-- game.proxy_addr = {ip="173.255.254.41", port=10000}
-- game.lobby_addr = {ip="173.255.254.41", port=54321} -- default value
game.hasPlayerList = function()
  dump('has player list? '..tostring( game.ppl ~= nil ))
  return ( game.ppl ~= nil )
end

-- state controls
local Const = {
  OFFLINE = 0,
  CONN_TO_PROXY  = 1,
  IN_PROXY       = 2,
  CONN_TO_LOBBY  = 3,
  IN_LOBBY       = 4,
  CONN_TO_PLAYER = 5,
  READY_TO_PLAY  = 6,
  IN_GAME        = 7,
  GIVE_UP = 9
}
net.gotoOffline = function()
  dump('state=OFFLINE')
  net.state = Const.OFFLINE
  net.reset()
end
net.gotoProxy = function()
  dump('state=CONN_TO_PROXY')
  net.state = Const.CONN_TO_PROXY
  net.conn_proxy = net.connect(game.proxy_addr.ip, game.proxy_addr.port)
  return net.conn_proxy
end
net.gotoProxyReady = function()
  dump('state=IN_PROXY')
  net.state = Const.IN_PROXY
end
net.gotoLobby = function()
  dump('state=CONN_TO_LOBBY')
  net.state = Const.CONN_TO_LOBBY
  return net.server(game.lobby_addr.ip, game.lobby_addr.port)
end
net.gotoLobbyReady = function()
  dump('state=IN_LOBBY')
  net.state = Const.IN_LOBBY
end
net.gotoPlayer = function(tar)
  dump('state=CONN_TO_PLAYER')
  net.state = Const.CONN_TO_PLAYER
  if tar then net.farside(tar.addr) end
end
net.gotoPlayerReady = function()
  dump('state=READY_TO_PLAY')
  net.state = Const.READY_TO_PLAY

  C.on_matched('') -- only call matched when Player is READY_TO_PLAY

  if net.asServer == true then
    dump('Pose as '..'Server')
  else
    dump('Pose as '..'Client')
  end
end

net.gotoGame   = function() net.state = Const.IN_GAME end
net.gotoGiveup = function() net.state = Const.GIVE_UP end

net.isInLobby = function() return (net.state == Const.IN_LOBBY) end
net.isPlayerReady = function() return (net.state == Const.READY_TO_PLAY) end
net.at = function(loc)
  if loc ~= nil then
    return net.state == loc
  else
    net.state = loc
  end
end
net.after = function(loc)
  return (net.state > loc)
end
net.before = function(loc)
  return (net.state < loc)
end

-- connection management
net.conn_server  = nil
net.conn_farside = nil
net.host     = nil
net.state    = Const.OFFLINE
net.tar      = nil  -- farside information
net.tm       = 0
net.greeting = 0

function net:tarPriAddr(i)
  if i ~= nil then return addr_str(net.tar.prialt) end
  return addr_str(net.tar.pri)
end

function net:tarPubAddr(i)
  if i ~= nil and i > 0 and i < 6 then return addr_str(net.tar.pubs[i])
  elseif i ~= nil and i > 100     then return addr_str(net.tar.pubalt)
  end
  return addr_str(net.tar.pub)
end

net.init = function(ip, port)
  dump('create host '..ip..':'..port)
  net.reset()
  net.host = enet.host_create(ip..":"..port)
end
net.connect = function(ip, port)
  dump('connecting to... '..ip..':'..port)
  local conn = nil
  local function foo()
    conn = net.host:connect(ip..":"..port)
  end

  local ok, err = pcall(foo)
  if not ok then dump(err) end
  return conn
end
net.server = function(ip, port)
  dump('connect to server...')
  local function foo()
    net.conn_server = net.host:connect(ip..":"..port)
  end

  local ok, err = pcall(foo)

  if not ok then dump(err) end

  return ok
end

net.farside = function(info)
  dump('connect to farside...')
  if info then return ns.connect(net, info) end
  return ns.connect_next()
end

net.setup = function(tar)
  net.greeting = 0
  -- net.state    = Const.OFFLINE

  net.iam = {}
  net.iam.pri = {ip=IP_LOCAL, port=PORT}
  net.iam.prialt = {ip=IP_LOCAL, port=PORT+1000}

  net.tar = kit.addr_ext(tar)
end

net.reset = function()
  if net.conn_farside then net.conn_farside:disconnect() end
  if net.conn_server  then net.conn_server:disconnect() end
  net.greeting = 0
  net.state    = Const.OFFLINE
end

net.waitGreeting = function()
  dump('wait for greetings...'..tostring(net.greeting))
  net.greeting = net.greeting + 1

  if net.greeting >= 3 then
    dump('wait too long...')
    if game.hasPlayerList() and (not net.farside()) then
      net.gotoGiveup()
    else
      net.gotoLobbyReady()
    end
  end
end

net.gotGreeting = function(src)
  if not net.isPlayerReady() then
    net.gotoPlayerReady()
    net.conn_farside = src
  else
    dump('ignore duplicated player connection from '..tostring(src))
  end

end

local function old_tick_poll_core(cc)
  -- if cc == 49 then
    -- if game.hasPlayerList() then
      -- prep.play_one(net.conn_server, game.ppl[1].pid)
    -- end
  -- elseif cc==50 then
    -- if net.isPlayerReady() then
      -- for i = 1, 100 do
        -- play.hit(net.conn_farside, 0, i)
        -- --net.host:flush()
      -- end
    -- end
  -- elseif cc==51 then
  -- elseif cc==52 then
    -- prep.chat_lobby(net.conn_server, string.random(6)..os.time())
  -- end
end

net.tick = function()

  -- commands from terminal
  local cc = ffi.string(C.poll_from_C())
  while cc and cc ~= '' do
    if not net.isPlayerReady() then
      if cc == '1' then
        if game.hasPlayerList() then

          for k,v in pairs(game.ppl) do
            if v.pid ~= game.pid then
              prep.play_one(net.conn_server, v.pid)
              break
            end
          end

        end
      end
    else
      local getT = loadstring(cc)
      local t = getT()
      t.tm = os.time()
      kit.send(t, net.conn_farside)
    end
    cc = ffi.string(C.poll_from_C())
  end

  if (os.time() - net.tm > 0) then
    net.tm = os.time()

    if net.at(Const.CONN_TO_PLAYER) then
      prep.poke_server(net.conn_server)
      net.waitGreeting()
    end

    -- keep-alive
    if kindof(1, net.tm) and not net.before(Const.IN_LOBBY) then
      prep.poke_server(net.conn_server)
      -- prep.chat_lobby(net.conn_server, string.random(6)..os.time())
    end

    -- re-send IAM if lobby server was full
    if kindof(10, net.tm) and net.at(Const.CONN_TO_LOBBY) then
      prep.send_iam(IP_LOCAL, PORT, net.conn_server)
    end

    -- update live server list
    if kindof(15, net.tm) and net.at(Const.IN_PROXY) then
      prep.list_lobbies(net.conn_proxy)
    end

    -- update number of players on proxy
    if kindof(20, net.tm) then
      prep.num_ppl_proxy(net.conn_proxy)
    end

    -- request full player list every 10 mins
    if kindof(600, net.tm) and net.at(Const.IN_LOBBY) then
      play.list_players(net.conn_server)
    end

  end
end

net.proc_farside = function(e)
  local is = kit.curry(eq)(e.type)

  if is('receive') then
    play.recv(e)
  elseif is('connect') then
    print("Lua: farside connected, send greeting:", e.peer)
    prep.greeting(e.peer)
  elseif is('disconnect') then
    dump("Lua: disconnected to farside: "..tostring(e.peer))
    net.state = Const.OFFLINE
  else
    dump(e)
  end
end

net.proc_server = function(e)
  local is = kit.curry(eq)(e.type)

  if is('receive') then
    prep.recv(e)
  elseif is('connect') then
    print("Lua: server connected:", e.peer)

    C.on_connected('')

    if net.state == Const.CONN_TO_PROXY then
      net.gotoProxyReady()

      -- TODO:
      -- request CLI_LS_LOB periodically and
      -- trigger gotoLobby() according to user's command
      prep.list_lobbies(net.conn_proxy)
    end

    if net.state == Const.CONN_TO_LOBBY then
      prep.send_iam(IP_LOCAL, PORT, e.peer)
    end
  elseif is('disconnect') then
    print("Lua: disconnected to server: ", e.peer)
    net.gotoOffline()
    C.on_disconnected('')
  else
    dump(e)
  end
end

-- Entry point
-- global function so it can be called from C++
function init(sc_flag)
  PORT = sc_flag
  net.asServer = (sc_flag%2==0)
  net.init(IP_LOCAL, PORT)

  prep.setup(net, game)
  play.setup(net, game)

  if not net.gotoProxy() then
    print('Lua: host:connect failed')
    return false
  end
  print('Lua: host:connect succeed, but not yet acked')
  return true
end

function run()
  local e = net.host:service(0) -- network event
  while e do
    if net.state <= Const.IN_LOBBY then
      net.proc_server(e)
    else
      net.proc_farside(e)
    end
    e = net.host:service(0)
  end
  net.tick()
end
--
function dtor()
  net.reset()
  dump('event loop ended.')
end


if arg == nil or arg[1] == nil then
  dump( "Local IP: "..IP_LOCAL )
else
  assert(Const.OFFLINE        == 0, 'Const.OFFLINE should be 0')
  assert(Const.CONN_TO_PROXY  == 1, 'Const.CONN_TO_PROXY should be 1')
  assert(Const.IN_PROXY       == 2, 'Const.IN_PROXY should be 2')
  assert(Const.CONN_TO_LOBBY  == 3, 'Const.CONN_TO_LOBBY should be 3')
  assert(Const.IN_LOBBY       == 4, 'Const.IN_LOBBY should be 4')
  assert(Const.CONN_TO_PLAYER == 5, 'Const.CONN_TO_PLAYER should be 5')
  assert(Const.READY_TO_PLAY  == 6, 'Const.READY_TO_PLAY should be 6')
  assert(Const.IN_GAME        == 7, 'Const.IN_GAME should be 7')
  assert(Const.GIVE_UP        == 9, 'Const.GIVE_UP should be 9')
  assert(game.proxy_addr.ip   == '173.255.254.41', 'Proxy ip should be 173.255.254.41')
  assert(game.proxy_addr.port == 10000           , 'Proxy port should be 10000')
  assert(game.lobby_addr.ip   == '173.255.254.41', 'Lobby\'s default ip should be 173.255.254.41')
  assert(game.lobby_addr.port == 54321           , 'Lobby\'s default port should be 173.255.254.41')
end
