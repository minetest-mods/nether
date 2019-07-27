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

	within_realm = function(pos) -- return true if pos is inside the Nether
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

nether.register_portal("stargate_portal", {
	shape               = nether.PortalShape_Circular,
	frame_node_name     = "default:stone",
	wormhole_node_color = 4, -- 4 is cyan
	book_of_portals_pagetext = S([[      ──══♦♦♦◊   Shape testing portal   ◊♦♦♦══──

	            ┌═╤═╤═╗
	      ┌═┼─┴─┴─┼═╗
	┌═┼─┘               └─┼═╗
	├─╢                           ├─╢
	├─╢                           ├─╢    Stargate?
	└─╚═╗               ┌═╡─┘
	      └─╚═╤═╤═┼─┘
	            └─┴─┴─┘


]] .. "\u{25A9}"),

	within_realm = function(pos) -- return true if pos is inside the Nether
		return pos.y < nether.DEPTH
	end,

	find_realm_anchorPos = function(surface_anchorPos)
		-- divide x and z by a factor of 8 to implement Nether fast-travel
		local destination_pos = vector.divide(surface_anchorPos, nether.FASTTRAVEL_FACTOR)
		destination_pos.x = math.floor(0.5 + destination_pos.x) -- round to int
		destination_pos.z = math.floor(0.5 + destination_pos.z) -- round to int
		destination_pos.y = nether.DEPTH - 1000 -- temp value so find_nearest_working_portal() returns nether portals

		-- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are in the Nether)
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("stargate_portal", destination_pos, 8, 0)
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
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("stargate_portal", destination_pos, 8 * nether.FASTTRAVEL_FACTOR, 0)
		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else 
			destination_pos.y = nether.find_surface_target_y(destination_pos.x, destination_pos.z, "stargate_portal")
			return destination_pos
		end
	end
})
