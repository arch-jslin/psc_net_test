local gettime  = require 'socket'.gettime


print( math.floor(gettime()*1000) )
