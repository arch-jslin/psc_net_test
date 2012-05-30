local enet   = require 'enet'
local socket = require 'socket'
local ffi    = require 'ffi'
local C      = ffi.C
local kit    = require 'kit'
local msg    = kit.msg
local pmsg   = kit.pmsg
local dump   = kit.getDump('Protocol_Preproc')

local EXPORT = {}
local net    = nil
local game   = nil

-- recv functions
local RECV = {}

RECV.URE = function(m)
  dump(m.T..' '..m.pid)

  if m.pid == 'error' then -- server full
    dump('server is full')
    return
  end

  game.pid = m.pid
  table.foreach(m.ppl, function(k, v) v.addr = kit.addr_ext(v.addr) end)
  game.ppl = m.ppl

  net.gotoLobbyReady()

  EXPORT.list_players(m.src)  -- test
end

RECV.GREETING = function(m)
  pmsg(m)

  net.gotGreeting(m.src)
end

RECV.PLS_R = function(m)
  dump(m.T)
  if m.C==0 then
    table.foreach(m.ppl, function(k, v) v.addr = kit.addr_ext(v.addr) end)
    game.ppl = m.ppl
  end
end

RECV.CHAT = function(m)
  dump(m)
  local sid = m.sid
  local txt = m.txt
  local type= m.type
  if type=='b' then
    dump(sid..' says '..txt..' at Lobby')
  end
end

RECV.PLAY_W = function(m)
  pmsg(m)
  if m.C == 0 then
    m.tar.addr = kit.addr_ext(m.tar.addr)
    game.ppl[m.tar.pid] = m.tar

    net.gotoPlayer(m.tar)
  else
    dump('no such player: '..m.tar.pid)
  end
end

RECV.CLI_RT_LOB = function(m)
  dump(m)

  if table.getn(m.servs) > 0 then
    game.lobbys = m.servs

    -- use the first one anyway
    game.lobby_addr = {ip=m.servs[1].ip, port=m.servs[1].port}
    net.gotoLobby()
  end
end

RECV.PLS_D_R = function(m)
  dump(m.T)
  local function _add_array(tar, itm)
    local exist = false
    table.foreach(tar, function(k,v)
      if v.pid ==itm.pid then
        tar[k] = itm
        exist = true
        print('add overwrite '.. itm.pid)
      end
    end)

    if exist == false then
      table.insert(tar, 1, itm)
      -- print('add append '.. itm.pid)
    end
  end

  local function _del_array(tar, itm)
    local exist = false
    table.foreach(tar, function(k,v)
      if v.pid == itm.pid then
        tar[k] = nil
        exist = true
        print('del one '.. itm.pid)
      end
    end)

    if exist == false then
      print('del skip '.. itm.pid)
    end
  end

  table.foreach(m.add, function(k, v)
    _add_array(game.ppl, v)
  end)
  table.foreach(m.del, function(k, v)
    _del_array(game.ppl, v)
  end)
end

-- receiver
local recv = kit.getRecv(function (m)
  if RECV[m.T]==nil then
    dump('Incoming msg is not supported: '..m.T)
    return
  end
  RECV[m.T](m)
end)

-- outgoing messages
local function greeting(peer)
  local m = msg('GREETING')
  kit.send(m, peer)
end
local function send_iam(ip, port, pserv)
  local m = msg('IAM')
  m.ip    = ip
  m.port  = port
  m.nick  = 'nick '..string.random(4, '%d')
  kit.send(m, pserv)
end
local function list_players(pserv)
  local m = msg('PLS')
  m.pid   = game.pid
  kit.send(m, pserv)
end
local function poke_server(pserv)
  local m = msg('POKE')
  m.pid   = game.pid
  kit.send(m, pserv)
end
local function chat_lobby(pserv, txt)
  local m = msg('CHAT')
  m.pid   = game.pid
  m.txt   = txt
  m.type  = 'b' -- lobby
  kit.send(m, pserv)
end
local function play_one(pserv, pid)
  local m = msg('PLAY_1')
  m.pid_me  = game.pid
  m.pid_tar = pid
  kit.send(m, pserv)
end
local function list_lobbies(lserv)
  local m = msg('CLI_LS_LOB')
  kit.send(m, lserv)
end

EXPORT.on = function(k,f) ON[k] = f end
EXPORT.chat_lobby  = chat_lobby
EXPORT.poke_server = poke_server
EXPORT.play_one = play_one
EXPORT.send_iam = send_iam
EXPORT.greeting = greeting
EXPORT.recv  = recv
EXPORT.list_players = list_players
EXPORT.list_lobbies = list_lobbies
EXPORT.setup = function(n, g)
  net  = n
  game = g
end

return EXPORT
