--[[

  Nether mod for minetest

  This file contains helper functions for generating geode interiors,
  a proof-of-concept to demonstrate how the secondary/spare region
  in the nether might be put to use by someone.


  Copyright (C) 2021 Treer

  Permission to use, copy, modify, and/or distribute this software for
  any purpose with or without fee is hereby granted, provided that the
  above copyright notice and this permission notice appear in all copies.

  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
  WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR
  BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES
  OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
  WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
  ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
  SOFTWARE.

]]--


local debugf = nether.debug
local mapgen = nether.mapgen


-- Content ids

local c_air              = minetest.get_content_id("air")
local c_crystal          = minetest.get_content_id("nether:geodelite") -- geodelite has a faint glow
local c_netherrack       = minetest.get_content_id("nether:rack")
local c_glowstone        = minetest.get_content_id("nether:glowstone")

-- Math funcs
local math_max, math_min, math_abs, math_floor, math_pi = math.max, math.min, math.abs, math.floor, math.pi -- avoid needing table lookups each time a common math function is invoked


-- Create a tiling space of close-packed spheres, using Hexagonal close packing
-- of spheres with radius 0.5.
-- With a layer of spheres on a flat surface, if the pack-z distance is 1 due to 0.5
-- radius then the pack-x distance will be the height of an equilateral triangle: sqrt(3) / 2,
-- and the pack-y distance between each layer will be sqrt(6) / 3,
-- The tessellating space will be a rectangular box of 2*pack-x by 1*pack-z by 3*pack-y

local xPack = math.sqrt(3)/2      -- 0.866, height of an equalateral triangle
local xPack2 = xPack * 2          -- 1.732
local yPack = math.sqrt(6) / 3    -- 0.816, y height of each layer
local yPack2 = yPack * 2
local yPack3 = yPack * 3
local layer2offsetx = xPack / 3   -- 0.289, height to center of equalateral triangle
local layer3offsetx = xPack2 / 3  -- 0.577
local structureSize = 50 -- magic numbers may need retuning if this changes too much

local layer1 = {
    {0,      0,  0},
    {0,      0,  1},
    {xPack,  0, -0.5},
    {xPack,  0,  0.5},
    {xPack,  0,  1.5},
    {xPack2, 0,  0},
    {xPack2, 0,  1},
}
local layer2 = {
    {layer2offsetx - xPack,  yPack,  0},
    {layer2offsetx - xPack,  yPack,  1},
    {layer2offsetx,          yPack, -0.5},
    {layer2offsetx,          yPack,  0.5},
    {layer2offsetx,          yPack,  1.5},
    {layer2offsetx + xPack,  yPack,  0},
    {layer2offsetx + xPack,  yPack,  1},
    {layer2offsetx + xPack2, yPack, -0.5},
    {layer2offsetx + xPack2, yPack,  0.5},
    {layer2offsetx + xPack2, yPack,  1.5},
}
local layer3 = {
    {layer3offsetx - xPack,  yPack2, -0.5},
    {layer3offsetx - xPack,  yPack2,  0.5},
    {layer3offsetx - xPack,  yPack2,  1.5},
    {layer3offsetx,          yPack2,  0},
    {layer3offsetx,          yPack2,  1},
    {layer3offsetx + xPack,  yPack2, -0.5},
    {layer3offsetx + xPack,  yPack2,  0.5},
    {layer3offsetx + xPack,  yPack2,  1.5},
    {layer3offsetx + xPack2, yPack2,  0},
    {layer3offsetx + xPack2, yPack2,  1},
}
local layer4 = {
    {0,      yPack3,  0},
    {0,      yPack3,  1},
    {xPack,  yPack3, -0.5},
    {xPack,  yPack3,  0.5},
    {xPack,  yPack3,  1.5},
    {xPack2, yPack3,  0},
    {xPack2, yPack3,  1},
}
local layers = {
    {y = layer1[1][2], points = layer1}, -- layer1[1][2] is the y value of the first point in layer1, and all spheres in a layer have the same y
    {y = layer2[1][2], points = layer2},
    {y = layer3[1][2], points = layer3},
    {y = layer4[1][2], points = layer4},
}


-- Geode mapgen functions (AKA proof of secondary/spare region concept)


-- fast for small lists
function insertionSort(array)
    local i
    for i = 2, #array do
        local key = array[i]
        local j = i - 1
        while j > 0 and array[j] > key do
            array[j + 1] = array[j]
            j = j - 1
        end
        array[j + 1] = key
    end
    return array
end


local distSquaredList = {}
local adj_x = 0
local adj_y = 0
local adj_z = 0
local lasty, lastz
local warpx, warpz


-- It's quite a lot to calculate for each air node, but its not terribly slow and
-- it'll be pretty darn rare for chunks in the secondary region to ever get emerged.
mapgen.getGeodeInteriorNodeId = function(x, y, z)

	if z ~= lastz then
		lastz = z
		-- Calculate structure warping
		-- To avoid calculating this for each node there's no warping as you look along the x axis :(
		adj_y = math.sin(math_pi / 222 * y) * 30

		if y ~= lasty then
			lasty = y
			warpx = math.sin(math_pi / 100 * y) * 10
			warpz = math.sin(math_pi /  43 * y) * 15
		end
		local twistRadians = math_pi / 73 * y
		local sinTwist, cosTwist = math.sin(twistRadians), math.cos(twistRadians)
		adj_x = cosTwist * warpx - sinTwist * warpz
		adj_z = sinTwist * warpx + cosTwist * warpz
	end

	-- convert x, y, z into a position in the tessellating space
	local cell_x = (((x + adj_x) / xPack2 + 0.5) % structureSize) / structureSize * xPack2
	local cell_y = (((y + adj_y) / yPack3 + 0.5) % structureSize) / structureSize * yPack3
	local cell_z = (((z + adj_z) + 0.5) % structureSize) / structureSize -- zPack = 1, so can be omitted

	local iOut = 1
	local i, j
	local canSkip = false

	for i = 1, #layers do

		local layer = layers[i]
		local dy = cell_y - layer.y

		if dy > -0.71 and dy < 0.71 then -- optimization - don't include points to far away to make a difference. (0.71 comes from sin(45°))
			local points = layer.points

			for j = 1, #points do

				local point = points[j]
				local dx = cell_x - point[1]
				local dz = cell_z - point[3]
				local distSquared = dx*dx + dy*dy + dz*dz

				if distSquared < 0.25 then
					-- optimization - point is inside a sphere, so cannot be a wall edge. (0.25 comes from radius of 0.5 squared)
					return c_air
				end

				distSquaredList[iOut] = distSquared
				iOut = iOut + 1
			end
		end
	end

	-- clear the rest of the array instead of creating a new one to hopefully reduce luajit mem leaks.
	while distSquaredList[iOut] ~= nil do
		rawset(distSquaredList, iOut, nil)
		iOut = iOut + 1
	end

	insertionSort(distSquaredList)

	local d3_1 = distSquaredList[3] - distSquaredList[1]
	local d3_2 = distSquaredList[3] - distSquaredList[2]
	--local d4_1 = distSquaredList[4] - distSquaredList[1]
	--local d4_3 = distSquaredList[4] - distSquaredList[3]

	-- Some shape formulas (tuned for a structureSize of 50)
	--   (d3_1 < 0.05) gives connective lines
	--   (d3_1 < 0.05 or d3_2 < .02) give fancy elven bridges - prob doesn't need the d3_1 part
	--  ((d3_1 < 0.05 or d3_2 < .02) and distSquaredList[1] > .3) tapers the fancy connections in the middle
	--   (d4_3 < 0.03 and d3_2 < 0.03) produces caltrops at intersections
	--   (d4_1 < 0.1) produces spherish balls at intersections
	-- The idea is voronoi based - edges in a voronoi diagram are where each nearby point is at equal distance.
	-- In this case we use squared distances to avoid calculating square roots.

	if (d3_1 < 0.05 or d3_2 < .02) and distSquaredList[1] > .3 then
		return c_crystal
	elseif (distSquaredList[4] - distSquaredList[1]) < 0.08 then
		return c_glowstone
	else
		return c_air
	end
end