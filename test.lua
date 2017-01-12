#!/usr/bin/env luajit
local vec3 = require 'vec.vec3'
local jfnk = require 'jfnk'

-- a cross b = c, solve for b
print(jfnk{
	x = vec3(-1,-1,-1),
	f = function(x)
		return vec3.cross({1,0,0}, x) - {0,0,1}
	end,
	errorCallback = function(err, iter)
		print('err',err,'iter',iter)
	end,
})

-- current is the divergence of the EM vector potential
-- so how about an inverse divergence function? 
-- in flat space that is just as easy solving for each xyz individually
-- in curved space the components mix together a bit 
