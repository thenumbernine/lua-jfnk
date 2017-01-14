local table = require 'ext.table'
local gmres = require 'solver.cl.gmres'

--[[
performs update of iteration x[n+1] = x[n] - (dF/dx)^-1 F(x[n])

args:
	f(f_of_x, x) = function reading x and writing f_of_x 
 	x = initial vector
	dx = initial direction (optional, defaults to x)
	epsilon = (optional) tolerance to stop newton descent
	maxiter = (optional) max newton iterations
	alpha = (optional) percent of dx to trace along. default 1
	errorCallback (optional) = accepts error, iteration; returns true if iterations should be stopped
	lineSearch = (optional) line search method. options: 'none', 'linear', 'bisect'.  default 'bisect'.
	lineSearchMaxIter = (optional) iterations for the particular line search method.
	jfnkEpsilon = (optional) epsilon for derivative approximation
	gmres = gmres args

	new
	dot
	norm (optiona) defaults to dot(x,x)/n
--]]
local function jfnk(args)
	local f = assert(args.f)
	local x = assert(args.x)
	local dx = args.dx or x
	local epsilon = args.epsilon or 1e-10
	local maxiter = args.maxiter or 100
	local maxAlpha = args.alpha or 1
	local errorCallback = args.errorCallback
	local lineSearch = args.lineSearch or 'bisect'
	local lineSearchMaxIter = args.lineSearchMaxIter or 100
	local jfnkEpsilon = args.jfnkEpsilon or 1e-6

	-- how should jfnk.new and gmres.new share?
	local new = assert(args.new)
	local dot = assert(args.dot)
	local norm = args.norm or function(x) return dot(x,x) / args.size end
	local mulAdd = assert(args.mulAdd)
	local scale = assert(args.scale)

	local gmresArgs = args.gmres or {}	
	gmresArgs.new = gmresArgs.new or new
	gmresArgs.dot = gmresArgs.dot or dot
	gmresArgs.mulAdd = gmresArgs.mulAdd or mulAdd
	gmresArgs.scale = gmresArgs.scale or scale

	local f_of_x = new'f_of_x' 
	local x_plus_dx = new'x_plus_dx'
	local x_minus_dx = new'x_minus_dx'
	local f_of_x_plus_dx = new'f_of_x_plus_dx'
	local f_of_x_minus_dx = new'f_of_x_minus_dx'

	local function residualAtAlpha(alpha)
		mulAdd(x_plus_dx, x, dx, -alpha)
		f(f_of_x_plus_dx, x_plus_dx)
		return norm(f_of_x_plus_dx)
	end

	local lineSearchMethods = {
		none = function() return maxAlpha end,
		linear = function()
			local bestAlpha = 0
			local bestResidual = math.huge
			for i=0,lineSearchMaxIter do
				local alpha = maxAlpha * i / lineSearchMaxIter
				local residual = residualAtAlpha(alpha)
				if residual < bestResidual then
					bestAlpha, bestResidual = alpha, residual
				end
			end
			return bestAlpha, bestResidual
		end,
		bisect = function()
			local alphaL = 0
			local alphaR = maxAlpha
			local residualL = residualAtAlpha(alphaL)
			local residualR = residualAtAlpha(alphaR)
			for i=0,lineSearchMaxIter do
				local alphaMid = .5 * (alphaL + alphaR)
				local residualMid = residualAtAlpha(alphaMid)
				if residualMid > residualL and residualMid > residualR then break end
				if residualMid < residualL and residualMid < residualR then
					if residualL <= residualR then
						alphaR, residualR  = alphaMid, residualMid
					else
						alphaL, residualL = alphaMid, residualMid
					end
				elseif residualMid < residualL then
					alphaL, residualL = alphaMid, residualMid
				else
					alphaR, residualR = alphaMid, residualMid
				end
			end
			if residualL < residualR then
				return alphaL, residualL
			else
				return alphaR, residualR
			end
		end,
	}
	local lineSearchMethod = assert(lineSearchMethods[lineSearch], "couldn't find line search method "..lineSearch)

	local cache = {}

	for iter=1,maxiter do
		f(f_of_x, x)

		local err = norm(f_of_x)
		if errorCallback and errorCallback(err, iter) then return x end
		if err < epsilon then return x end

		-- solve dx = (dF/dx)^-1 F(x) via iterative (dF/dx) dx = f(x)
		-- use jfnk approximation for dF/dx * dx
-- TODO move this 'gmres' object outside so it only builds the kernels once	
		gmres(table(gmresArgs, {
			new = function(name)
				if cache[name] then return cache[name] end
				local buffer = new(name)
				cache[name] = buffer
				return buffer
			end,
			x = dx,
			A = function(result, dx)
				mulAdd(x_plus_dx, x, dx, jfnkEpsilon)
				mulAdd(x_minus_dx, x, dx, -jfnkEpsilon)
				f(f_of_x_plus_dx, x_plus_dx)
				f(f_of_x_minus_dx, x_minus_dx)
				mulAdd(result, f_of_x_plus_dx, f_of_x_minus_dx, -1)
				scale(result, result, 1 / (2 * jfnkEpsilon))
			end,
			b = f_of_x,
		}))

		-- trace along dx to find minima of solution
		local alpha = lineSearchMethod()
	
		mulAdd(x, x, dx, -alpha)
	end

	return x
end

return jfnk
