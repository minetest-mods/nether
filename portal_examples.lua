--[[

  Nether mod portal examples for Minetest

  To use this file, add the following line to init.lua:
    dofile(nether.path .. "/portal_examples.lua")


  Copyright (C) 2019 Treer

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

local S = nether.get_translator

nether.register_portal("floatlands_portal", {
	shape               = nether.PortalShape_Traditional,
	frame_node_name     = "default:ice",
	wormhole_node_color = 7, -- 2 is blue
	particle_texture    = {
		name      = "nether_particle_anim1.png",
		animation = {
			type = "vertical_frames",
			aspect_w = 7,
			aspect_h = 7,
			length = 1,
		},
		scale = 1.5
	},
	book_of_portals_pagetext = S([[      ──══♦♦♦◊   The Floatlands   ◊♦♦♦══──

Requiring 14 blocks of ice, but otherwise constructed the same as the portal to the Nether:

	┌═╤═╤═╤═╗
	├─╥─┴─┼─╢
	├─╢         ├─╢
	├─╢         ├─╢
	├─╚═╤═╡─╢
	└─┴─┴─┴─┘

]] .. "\u{25A9}"),

	is_within_realm = function(pos) -- return true if pos is inside the Nether
		return pos.y < nether.DEPTH
	end,

	find_realm_anchorPos = function(surface_anchorPos)
		-- divide x and z by a factor of 8 to implement Nether fast-travel
		local destination_pos = vector.divide(surface_anchorPos, nether.FASTTRAVEL_FACTOR)
		destination_pos.x = math.floor(0.5 + destination_pos.x) -- round to int
		destination_pos.z = math.floor(0.5 + destination_pos.z) -- round to int
		destination_pos.y = nether.DEPTH - 1000 -- temp value so find_nearest_working_portal() returns nether portals

		-- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are in the Nether)
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("floatlands_portal", destination_pos, 8, 0)
		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else
			local start_y = nether.DEPTH - math.random(500, 1500) -- Search starting altitude
			destination_pos.y = nether.find_nether_ground_y(destination_pos.x, destination_pos.z, start_y)
			return destination_pos
		end
	end,

	find_surface_anchorPos = function(realm_anchorPos)
		-- A portal definition doesn't normally need to provide a find_surface_anchorPos() function,
		-- since find_surface_target_y() will be used by default, but Nether portals also scale position
		-- to create fast-travel. Defining a custom function also means we can look for existing nearby portals:

		-- Multiply x and z by a factor of 8 to implement Nether fast-travel
		local destination_pos = vector.multiply(realm_anchorPos, nether.FASTTRAVEL_FACTOR)
		destination_pos.x = math.min(30900, math.max(-30900, destination_pos.x)) -- clip to world boundary
		destination_pos.z = math.min(30900, math.max(-30900, destination_pos.z)) -- clip to world boundary
		destination_pos.y = 0 -- temp value so find_nearest_working_portal() doesn't return nether portals

		-- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are outside the Nether)
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("floatlands_portal", destination_pos, 8 * nether.FASTTRAVEL_FACTOR, 0)
		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else 
			destination_pos.y = nether.find_surface_target_y(destination_pos.x, destination_pos.z, "nether_portal")
			return destination_pos
		end
	end,
})


-- These Moore Curve functions requred by circular_portal's find_surface_anchorPos() will 
-- be assigned later in this file.
local get_moore_distance -- will be function get_moore_distance(cell_count, x, y): integer
local get_moore_coords   -- will be function get_moore_coords(cell_count, distance): pos2d

nether.register_portal("circular_portal", {
	shape               = nether.PortalShape_Circular,
	frame_node_name     = "default:cobble",
	wormhole_node_color = 4, -- 4 is cyan
	book_of_portals_pagetext = S([[      ──══♦♦♦◊   Surface portal   ◊♦♦♦══──

	            ┌═╤═╤═╗
	      ┌═┼─┴─┴─┼═╗
	┌═┼─┘               └─┼═╗
	├─╢                           ├─╢
	├─╢                           ├─╢    Stargate?
	└─╚═╗               ┌═╡─┘
	      └─╚═╤═╤═┼─┘
	            └─┴─┴─┘


]] .. "\u{25A9}"),

	is_within_realm = function(pos) 
		-- Always return true, because these portals always just take you around the surface
		-- rather than taking you to a realm
		return true
	end,

	find_realm_anchorPos = function(surface_anchorPos)
		-- This function isn't needed, since this type of portal always goes to the surface
		minecraft.log("error" , "find_realm_anchorPos called for surface portal")
		return {x=0, y=0, z=0}
	end,

	find_surface_anchorPos = function(realm_anchorPos)
		-- A portal definition doesn't normally need to provide a find_surface_anchorPos() function,
		-- since find_surface_target_y() will be used by default, but these portals travel around the
		-- surface (following a Moore curve) so will be using a different x and z to realm_anchorPos. 

		local cellCount = 512
		local travelDistanceInCells = 10
		local maxDistFromOrigin = 30000 -- the world edges are at X=30927, X=−30912, Z=30927 and Z=−30912

		-- clip realm_anchorPos to maxDistFromOrigin, and move the origin so that all values are positive 
		local x = math.min(maxDistFromOrigin, math.max(-maxDistFromOrigin, realm_anchorPos.x)) + maxDistFromOrigin
		local z = math.min(maxDistFromOrigin, math.max(-maxDistFromOrigin, realm_anchorPos.z)) + maxDistFromOrigin

		local divisor = math.ceil(maxDistFromOrigin * 2 / cellCount)
		local distance = get_moore_distance(cellCount, math.floor(x / divisor + 0.5), math.floor(z / divisor + 0.5))
		local destination_distance = (distance + travelDistanceInCells) % (cellCount * cellCount)
		local moore_pos = get_moore_coords(cellCount, destination_distance)

		-- deterministically look for a location where get_spawn_level() gives us a height
		local target_x = moore_pos.x * divisor - maxDistFromOrigin
		local target_z = moore_pos.y * divisor - maxDistFromOrigin

		local prng = PcgRandom( -- seed the prng so that all portals for these Moore Curve coords will use the same random location
			moore_pos.x * 65732 +
			moore_pos.y * 729   +
			minetest.get_mapgen_setting("seed") * 3
		)

		local radius = divisor / 2 - 2
		local attemptLimit = 10
		local adj_x, adj_z
		for attempt = 1, attemptLimit do
			adj_x = math.floor(prng:rand_normal_dist(-radius, radius, 2) + 0.5)
			adj_z = math.floor(prng:rand_normal_dist(-radius, radius, 2) + 0.5)
			minetest.chat_send_all(attempt .. ": x " .. target_x + adj_x .. ", z " .. target_z + adj_z)
			if minetest.get_spawn_level(target_x + adj_x, target_z + adj_z)	~= nil then
				-- found a location which will be at ground level (unless a player has built there)
				minetest.chat_send_all("x " .. target_x + adj_x .. ", z " .. target_z + adj_z .. " is suitable")
				break
			end
		end

		local destination_pos = {x = target_x + adj_x, y = 0, z = target_z + adj_z}
		-- a y_factor of 0 makes the search ignore the altitude of the portals
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("circular_portal", destination_pos, radius, 0)
		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else 
			destination_pos.y = nether.find_surface_target_y(destination_pos.x, destination_pos.z, "circular_portal")
			return destination_pos
		end
	end
})



--=========================================--
-- Hilbert curve and Moore curve functions --
--=========================================--

-- These are space-filling curves, used by the circular_portal example as a way to determine where 
-- to place portals. https://en.wikipedia.org/wiki/Moore_curve


-- Flip a quadrant on its diagonal axis
-- cell_count is the number of cells across the square is split into, and must be a power of 2
-- if flip_twice is true then pos does not change (any even numbers of flips would cancel out)
-- if flip_direction is true then the position is flipped along the \ diagonal
-- if flip_direction is false then the position is flipped along the / diagonal
local function hilbert_flip(cell_count, pos, flip_direction, flip_twice)
	if not flip_twice then
		if flip_direction then
			pos.x = (cell_count - 1) - pos.x;
			pos.y = (cell_count - 1) - pos.y;
		end
	
		local temp_x = pos.x;
		pos.x = pos.y;
		pos.y = temp_x;
	end
end

local function test_bit(cell_count, value, flag)
	local bit_value = cell_count / 2
	while bit_value > flag and bit_value >= 1  do
		if value >= bit_value then value = value - bit_value end
		bit_value = bit_value / 2
	end
	return value >= bit_value
end

-- Converts (x,y) to distance
-- starts at bottom left corner, i.e. (0, 0)
-- ends at bottom right corner, i.e. (cell_count - 1, 0)
local function get_hilbert_distance (cell_count, x, y)
	local distance = 0
	local pos = {x=x, y=y}
	local rx, ry

	local s = cell_count / 2
	while s > 0 do

		if test_bit(cell_count, pos.x, s) then rx = 1 else rx = 0 end
		if test_bit(cell_count, pos.y, s) then ry = 1 else ry = 0 end

		local rx_XOR_ry = rx
		if ry == 1 then rx_XOR_ry = 1 - rx_XOR_ry end -- XOR'd ry against rx

		distance = distance + s * s * (2 * rx + rx_XOR_ry)
		hilbert_flip(cell_count, pos, rx > 0, ry > 0);

		s = math.floor(s / 2)
	end
	return distance;
end

-- Converts distance to (x,y)
local function get_hilbert_coords(cell_count, distance)
	local pos = {x=0, y=0}
	local rx, ry

	local s = 1
	while s < cell_count do
		rx = math.floor(distance / 2) % 2
		ry = distance % 2
		if rx == 1 then ry = 1 - ry end -- XOR ry with rx
		 
		hilbert_flip(s, pos, rx > 0, ry > 0);
		pos.x = pos.x + s * rx
		pos.y = pos.y + s * ry
		distance = math.floor(distance / 4)

		s = s * 2
	end
  return pos
end


-- Converts (x,y) to distance
-- A Moore curve is a variation of the Hilbert curve that has the start and 
-- end next to each other.
-- Top middle point is the start/end location
get_moore_distance = function(cell_count, x, y)

	local quadLength = cell_count / 2
	local quadrant = 1 - math.floor(y / quadLength)
	if math.floor(x / quadLength) == 1 then quadrant = 3 - quadrant end
	local flipDirection = x < quadLength

	local pos = {x = x % quadLength, y = y % quadLength}
	hilbert_flip(quadLength, pos, flipDirection, false)

	return (quadrant * quadLength * quadLength) + get_hilbert_distance(quadLength, pos.x, pos.y)
end


-- Converts distance to (x,y)
-- A Moore curve is a variation of the Hilbert curve that has the start and 
-- end next to each other.
-- Top middle point is the start/end location
get_moore_coords = function(cell_count, distance)
	local quadLength = cell_count / 2
	local quadDistance = quadLength * quadLength
	local quadrant = math.floor(distance / quadDistance)
	local flipDirection = distance * 2 < cell_count * cell_count
	local pos = get_hilbert_coords(quadLength, distance % quadDistance)
	hilbert_flip(quadLength, pos, flipDirection, false)

	if quadrant >= 2     then pos.x = pos.x + quadLength end
	if quadrant % 3 == 0 then pos.y = pos.y + quadLength end

	return pos
end