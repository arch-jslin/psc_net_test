local gettime  = require 'socket'.gettime


-- print( math.floor(gettime()*1000) )

function memoize(f)
  -- create a new associative table to record results
  store = {}
  function anon(x)
    if store[x] then
      return store[x]
    else
      y = f(x)
      store[x] = y
      return y
    end
  end
  return anon
end

function Y(f)

	local function g(h)
  	return function (x)
    	return f(h (h)) (x)
    end
  end

  return g(g)
end

f = Y(function(recurse)
	return function (n)
		if n==0 then
			return 1
		else
			return n*recurse(n-1)
		end
	end
end)

fib = Y(function(recurse)
	return function (n)
		if n < 2 then
			return n
		else
			return recurse(n-1) + recurse(n-2)
		end
	end
end)

local sz = 32

local tm = gettime()
print(fib(sz))
print('fib1 takes '..(gettime()-tm)..' secs')

Ymem = memoize(Y)
fib3 = Ymem(function(recurse)
	return function (n)
		if n < 2 then
			return n
		else
			return recurse(n-1) + recurse(n-2)
		end
	end
end)

local tm = gettime()
print(fib3(sz))
print('fib3 takes '..(gettime()-tm)..' secs')

function fib2(n)
	if n < 2 then
		return n
	else
		return fib(n-1)+fib(n-2)
	end
end

local tm = gettime()
print(fib2(sz))
print('fib2 takes '..(gettime()-tm)..' secs')

fib4 = memoize(fib2)
local tm = gettime()
print(fib4(sz))
print('fib4 takes '..(gettime()-tm)..' secs')
