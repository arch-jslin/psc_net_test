local kit      = require 'kit'
local dump     = kit.getDump('Lua-NS')


local EXPORT = {}
local net = nil
local step = 0
local inc = 1
local proc = {}

local function _step1() -- connect to private ip
  dump('connect to '..net.tarPriAddr())
  net.client = net.host:connect(net.tarPriAddr())
end

local function _step2() -- connect to public ip
  dump('connect to '..net.tarPubAddr())
  net.client = net.host:connect(net.tarPubAddr())
end

local function _step3() -- connect to public ip by increasing port number
  dump('method 3 inc '..net.tarPubAddr(inc))
  net.client = net.host:connect(net.tarPubAddr(inc))
end

local function _step4() -- connect to public ip by opening new port
-- port沒被改變但不能連 => 開新 port (port 被限制給 matcher server )
end


EXPORT.connect = function (n, t, s)
  -- init target information
  net = n
  net.init(t)

  proc[1] = _step1
  proc[2] = _step2
  proc[3] = _step3
  proc[4] = _step4
 
  step = s
  EXPORT.connect_next()
end

EXPORT.connect_next = function ()

  if step == nil then
    step = 1
    inc = 1
  elseif step > table.getn(proc) then
    dump('Out of methods')
    inc = 1
    return false
  end

  dump('try method '..step)
  local ok, err = pcall(proc[step])

  if ok==false then
    dump(err)
  else
    net.state = 1
  end  

  if step == 3 and inc < 5 then
    inc = inc + 1
  else
    step = step + 1
  end
  return true
end

return EXPORT
