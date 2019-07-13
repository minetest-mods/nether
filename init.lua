--[[

  Nether mod for minetest

  Copyright (C) 2013 PilzAdam

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

local S = minetest.get_translator("nether")

-- Global Nether namespace
nether = {}
nether.path = minetest.get_modpath("nether")
nether.get_translator = S

-- Settings
nether.DEPTH                      = -5000
nether.FASTTRAVEL_FACTOR          =     8 -- 10 could be better value for Minetest, since there's no sprint, but ex-Minecraft players will be mathing for 8
nether.PORTAL_BOOK_LOOT_WEIGHTING =   0.9 -- Likelyhood of finding the Book of Portals (guide) in dungeon chests. Set to 0 to disable.


-- Load files
dofile(nether.path .. "/portal_api.lua")
dofile(nether.path .. "/nodes.lua")
dofile(nether.path .. "/mapgen.lua")


-- Portals are ignited by right-clicking with a mese crystal fragment
nether.register_portal_ignition_item("default:mese_crystal_fragment")


-- Use the Portal API to add a portal type which goes to the Nether
-- See portal_api.txt for documentation
nether.register_portal("nether_portal", {
	shape               = nether.PortalShape_Traditional,
	frame_node_name     = "default:obsidian",
	wormhole_node_name  = "nether:portal",
	wormhole_node_color = 0, -- 0 is magenta
	-- Warning: "Four per Em" spaces have been used to align the diagram in this text, rather 
	-- than ASCII spaces. If Minetest changes font this may need to be updated.
	book_of_portals_pagetext = S([[      ──══♦♦♦◊   The Nether   ◊♦♦♦══──

Requiring 14 blocks of obsidian, which we found deep underground where water had solidified molten rock. The frame must be constructed in the following fashion:

   ┌═╤═╤═╤═╗
   ├─╥─┴─┼─╢
   ├─╢         ├─╢
   ├─╢         ├─╢     four blocks wide
   ├─╚═╤═╡─╢     five blocks high
   └─┴─┴─┴─┘     Standing vertically, like a doorway

This opens to a truly hellish place, though for small mercies the air there is still breathable. There is an intriguing dimensional mismatch happening between this realm and ours, as after opening the second portal into it we observed that 10 strides taken in the Nether appear to be an equivalent of @1 in the natural world.

The expedition parties have found no diamonds or gold, and after an experienced search party failed to return from the trail of a missing expedition party, I must conclude this is a dangerous place.
]], 10 * nether.FASTTRAVEL_FACTOR),
	sound_ambient       = "nether_portal_hum",
	sound_ignite        = "",
	sound_extinguish    = "",
	sound_teleport      = "",

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
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("nether_portal", destination_pos, 8, 0)
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
		-- to create fast-travel:

		-- Multiply x and z by a factor of 8 to implement Nether fast-travel
		local destination_pos = vector.multiply(realm_anchorPos, nether.FASTTRAVEL_FACTOR)
		destination_pos.x = math.min(30900, math.max(-30900, destination_pos.x)) -- clip to world boundary
		destination_pos.z = math.min(30900, math.max(-30900, destination_pos.z)) -- clip to world boundary
		destination_pos.y = 0 -- temp value so find_nearest_working_portal() doesn't return nether portals

		-- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are outside the Nether)
		local existing_portal_location, existing_portal_orientation = nether.find_nearest_working_portal("nether_portal", destination_pos, 8 * nether.FASTTRAVEL_FACTOR, 0)
		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else 
			destination_pos.y = nether.find_surface_target_y(destination_pos.x, destination_pos.z, "nether_portal")
			return destination_pos
		end
	end
})
