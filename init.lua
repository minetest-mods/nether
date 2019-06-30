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


-- Parameters

local NETHER_DEPTH = -5000
local TCAVE = 0.6
local BLEND = 128
local DEBUG = false


-- 3D noise

local np_cave = {
	offset = 0,
	scale = 1,
	spread = {x = 384, y = 128, z = 384}, -- squashed 3:1
	seed = 59033,
	octaves = 5,
	persist = 0.7,
	lacunarity = 2.0,
	--flags = ""
}


-- Stuff

local yblmax = NETHER_DEPTH - BLEND * 2


netherportal = {} -- portal API

-- Functions


--[[
  For this TraditionalPortalShape implementation, anchorPos and wormholdPos are defined as follows:
                                          .
    +--------+--------+--------+--------+
    |        |      Frame      |        |
    |        |        |        |   p2   |
    +--------+--------+--------+--------+
    |        |                 |        |
    |        |                 |        |
    +--------+        +        +--------+
    |        |     Wormhole    |        |
    |        |                 |        |
    +--------+        +        +--------+
    |        |Wormhole         |        |
    |        |  Pos            |        |
    +--------+--------+--------+--------+
    AnchorPos|  Node  |        |        |
    |   p1   | Timer  |        |        |
    +--------+--------+--------+--------+

    +X/East or +Z/North ----->

A better location for AnchorPos would be directly under WormholePos, as it's more centered
and you don't need to know the portal's orientation to find AnchorPos from the WormholePos
or vice-versa, however AnchorPos is in the bottom/south/west-corner to keep compatibility
with earlier versions of nether mod (which only records portal corners p1 & p2 in the node 
metadata).

Orientation is 0 or 90, 0 meaning a portal that faces north/south - i.e. obsidian running
east/west.
]]


-- This object defines a portal's shape, segregating the shape logic code from portal behaviour code.
-- You can create a new "PortalShape" definition object which implements the same
-- functions if you wish to register a custom shaped portal in register_portal().
-- Since it's symmetric, this PortalShape definition has only implemented orientations of 0 and 90
local TraditionalPortalShape = {
	size = vector.new(4, 5, 1), -- size of the portal, and not necessarily the size of the schematic, which may clear area around the portal.
	schematic_filename = minetest.get_modpath("nether") .. "/schematics/nether_portal.mts",

	-- returns the coords for minetest.place_schematic() that will place the schematic on the anchorPos
	get_schematicPos_from_anchorPos = function(anchorPos, orientation)
		assert(orientation, "no orientation passed")
		if orientation == 0 then
			return {x = anchorPos.x,     y = anchorPos.y, z = anchorPos.z - 2}
		else
			return {x = anchorPos.x - 2, y = anchorPos.y, z = anchorPos.z    }
		end
	end,

	get_wormholePos_from_anchorPos = function(anchorPos, orientation)
		assert(orientation, "no orientation passed")
		if orientation == 0 then
			return {x = anchorPos.x + 1, y = anchorPos.y + 1, z = anchorPos.z    }
		else
			return {x = anchorPos.x,     y = anchorPos.y + 1, z = anchorPos.z + 1}
		end
	end,

	get_anchorPos_from_wormholePos = function(wormholePos, orientation)
		assert(orientation, "no orientation passed")
		if orientation == 0 then
			return {x = wormholePos.x - 1, y = wormholePos.y - 1, z = wormholePos.z    }
		else
			return {x = wormholePos.x,     y = wormholePos.y - 1, z = wormholePos.z - 1}
		end
	end,

	-- todo - convert TraditionalPortalShape to class so this doesn't need to be passed portal_shape
	--
	-- p1 and p2 are used to keep maps backwards compatible with earlier versions of this mod.
	-- p1 is the bottom/west/south corner of the portal, and p2 is the opposite corner, together
	-- they define the bounding volume for the portal.
	get_p1_and_p2_from_anchorPos = function(portal_shape, anchorPos, orientation)
		assert(orientation, "no orientation passed")
		local p1 = anchorPos -- TraditionalPortalShape puts the anchorPos at p1 for backwards&forwards compatibility
		local p2

		if orientation == 0 then
			p2 = {x = p1.x + portal_shape.size.x - 1, y = p1.y + portal_shape.size.y - 1, z = p1.z                          }
		else
			p2 = {x = p1.x,                           y = p1.y + portal_shape.size.y - 1, z = p1.z + portal_shape.size.x - 1}
		end
		return p1, p2
	end,

	get_anchorPos_and_orientation_from_p1_and_p2 = function(p1, p2)
		if p1.z == p2.z then
			return p1, 0
		elseif p1.x == p2.x then
			return p1, 90
		else
			-- this KISS implementation will break you've made a 3D PortalShape definition
			minetest.log("error", "get_anchorPos_and_orientation_from_p1_and_p2 failed on  p1=" .. meta:get_string("p1") .. " p2=" .. meta:get_string("p2"))
		end
	end,

	apply_func_to_frame_nodes = function(anchorPos, orientation, func)
		-- a 4x5 portal is small enough that hardcoded positions is simpler that procedural code
		local shortCircuited
		if orientation == 0 then
			-- use short-circuiting of boolean evaluation to allow func() to cause an abort by returning true
			shortCircuited =
				func({x = anchorPos.x + 0, y = anchorPos.y,     z = anchorPos.z}) or
				func({x = anchorPos.x + 1, y = anchorPos.y,     z = anchorPos.z}) or
				func({x = anchorPos.x + 2, y = anchorPos.y,     z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y,     z = anchorPos.z}) or
				func({x = anchorPos.x + 0, y = anchorPos.y + 4, z = anchorPos.z}) or
				func({x = anchorPos.x + 1, y = anchorPos.y + 4, z = anchorPos.z}) or
				func({x = anchorPos.x + 2, y = anchorPos.y + 4, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 4, z = anchorPos.z}) or

				func({x = anchorPos.x,     y = anchorPos.y + 1, z = anchorPos.z}) or
				func({x = anchorPos.x,     y = anchorPos.y + 2, z = anchorPos.z}) or
				func({x = anchorPos.x,     y = anchorPos.y + 3, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 1, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 2, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 3, z = anchorPos.z})
		else
			shortCircuited =
				func({x = anchorPos.x, y = anchorPos.y,     z = anchorPos.z + 0}) or
				func({x = anchorPos.x, y = anchorPos.y,     z = anchorPos.z + 1}) or
				func({x = anchorPos.x, y = anchorPos.y,     z = anchorPos.z + 2}) or
				func({x = anchorPos.x, y = anchorPos.y,     z = anchorPos.z + 3}) or
				func({x = anchorPos.x, y = anchorPos.y + 4, z = anchorPos.z + 0}) or
				func({x = anchorPos.x, y = anchorPos.y + 4, z = anchorPos.z + 1}) or
				func({x = anchorPos.x, y = anchorPos.y + 4, z = anchorPos.z + 2}) or
				func({x = anchorPos.x, y = anchorPos.y + 4, z = anchorPos.z + 3}) or

				func({x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z    }) or
				func({x = anchorPos.x, y = anchorPos.y + 2, z = anchorPos.z    }) or
				func({x = anchorPos.x, y = anchorPos.y + 3, z = anchorPos.z    }) or
				func({x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z + 3}) or
				func({x = anchorPos.x, y = anchorPos.y + 2, z = anchorPos.z + 3}) or
				func({x = anchorPos.x, y = anchorPos.y + 3, z = anchorPos.z + 3})
		end
		return not shortCircuited
	end,

	apply_func_to_wormhole_nodes = function(anchorPos, orientation, func)
		local shortCircuited
		if orientation == 0 then
			local wormholePos = {x = anchorPos.x + 1, y = anchorPos.y + 1, z = anchorPos.z}
			-- use short-circuiting of boolean evaluation to allow func() to cause an abort by returning true
			shortCircuited =
				func({x = wormholePos.x + 0, y = wormholePos.y + 0, z = wormholePos.z}) or
			    func({x = wormholePos.x + 1, y = wormholePos.y + 0, z = wormholePos.z}) or
				func({x = wormholePos.x + 0, y = wormholePos.y + 1, z = wormholePos.z}) or
				func({x = wormholePos.x + 1, y = wormholePos.y + 1, z = wormholePos.z}) or
				func({x = wormholePos.x + 0, y = wormholePos.y + 2, z = wormholePos.z}) or
				func({x = wormholePos.x + 1, y = wormholePos.y + 2, z = wormholePos.z})
		else
			local wormholePos = {x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z + 1}
			shortCircuited =
				func({x = wormholePos.x, y = wormholePos.y + 0, z = wormholePos.z + 0}) or
				func({x = wormholePos.x, y = wormholePos.y + 0, z = wormholePos.z + 1}) or
				func({x = wormholePos.x, y = wormholePos.y + 1, z = wormholePos.z + 0}) or
				func({x = wormholePos.x, y = wormholePos.y + 1, z = wormholePos.z + 1}) or
				func({x = wormholePos.x, y = wormholePos.y + 2, z = wormholePos.z + 0}) or
				func({x = wormholePos.x, y = wormholePos.y + 2, z = wormholePos.z + 1})
		end
		return not shortCircuited
	end,

	-- Check for whether the portal is blocked in, and if so then provide a safe way
	-- on one side for the player to step out of the portal. Suggest including a roof
	-- incase the portal was blocked with lava flowing from above.
	disable_portal_trap = function(anchorPos, orientation)
		assert(orientation, "no orientation passed")

		-- Not implemented yet. It may not need to be implemented because if you
		-- wait in a portal long enough you teleport again. So a trap portal would have to link
		-- to one of two blocked-in portals which link to each other - which is possible, but
		-- quite extreme.
	end
}

local registered_portals = {
	["default:obsidian"] = {
		shape = TraditionalPortalShape,
		wormhole_node_name = "nether:portal",
		frame_node_name    = "default:obsidian",

		find_realm_anchorPos = function(pos)
		end,

		find_surface_anchorPos = function(pos)
		end
	}
}


local function get_timerPos_from_p1_and_p2(p1, p2)
	-- Pick a frame node for the portal's timer.
	--
	-- The timer event will need to know the portal definition, which can be determined by
	-- what the portal frame is made from, so the timer node should be on the frame.
	-- The timer event will also need to know its portal orientation, but unless someone
	-- makes a cubic portal shape, orientation can be determined from p1 and p2 in the node's
	-- metadata (frame nodes don't have orientation set in param2 like wormhole nodes do).
	--
	-- We shouldn't pick p1 (or p2) as it's possible for two orthogonal portals to share
	-- the same p1, etc.
	--
	-- I'll pick the bottom center node of the portal, since that works for rectangular portals
	-- and if someone want to make a circular portal then that positon will still likely be part
	-- of the frame.
	return {
		x = math.floor((p1.x + p2.x) / 2),
		y = p1.y,
		z = math.floor((p1.z + p2.z) / 2),
	}
end

-- orientation is the rotation degrees passed to place_schematic: 0, 90, 180, or 270
local function get_param2_from_orientation(param2, orientation)
	return orientation / 90
end

local function get_orientation_from_param2(param2)
	return param2 * 90
end

local function set_portal_metadata(portal_definition, anchorPos, orientation, destination_wormholePos, ignite)

	-- p1 and p2 are used here to keep maps backwards compatible with earlier versions of this mod
	-- (p2's value is the opposite corner of the portal frame to p1, according to the fixed portal shape of earlier versions of this mod)
	local p1, p2 = portal_definition.shape.get_p1_and_p2_from_anchorPos(portal_definition.shape, anchorPos, orientation)
	local param2 = get_param2_from_orientation(0, orientation)

	local updateFunc = function(pos)
		if ignite and minetest.get_node(pos).name == "air" then
			minetest.set_node(pos, {name = portal_definition.wormhole_node_name, param2 = param2})
		end

		local meta = minetest.get_meta(pos)
		meta:set_string("p1",              minetest.pos_to_string(p1))
		meta:set_string("p2",              minetest.pos_to_string(p2))
		meta:set_string("target",          minetest.pos_to_string(destination_wormholePos))
		-- including "frame_node_name" in the metadata lets us know which kind of portal this is.
		-- It's not strictly necessary for TraditionalPortalShape as we know that p1 is part of
		-- the frame, and legacy portals don't have this extra metadata - indicating obsidian, 
		-- but p1 isn't always loaded so reading this from the metadata saves an extra call to 
		-- minetest.getnode().
		meta:set_string("frame_node_name", portal_definition.frame_node_name)
	end

	portal_definition.shape.apply_func_to_frame_nodes(anchorPos, orientation, updateFunc)
	portal_definition.shape.apply_func_to_wormhole_nodes(anchorPos, orientation, updateFunc)

	local timerPos = get_timerPos_from_p1_and_p2(p1, p2)
	minetest.get_node_timer(timerPos):start(1)
end

local function set_portal_metadata_and_ignite(portal_definition, anchorPos, orientation, destination_wormholePos)
	set_portal_metadata(portal_definition, anchorPos, orientation, destination_wormholePos, true)
end

-- Checks pos, and if it's part of a portal or portal frame then three values are returned: anchorPos, orientation, is_ignited
-- where orientation is 0 or 90 (0 meaning a portal that faces north/south - i.e. obsidian running east/west)
local function is_portal_frame(portal_definition, pos)

	local nodes_are_valid   -- using closures to allow the check functions to return extra information - by setting this variable
	local portal_is_ignited -- using closures to allow the check functions to return extra information - by setting this variable

	local frame_node_name = portal_definition.frame_node_name
	local check_frame_Func = function(check_pos)
		if minetest.get_node(check_pos).name ~= frame_node_name then
			nodes_are_valid = false
			return true -- short-circuit the search
		end
	end

	local wormhole_node_name = portal_definition.wormhole_node_name
	local check_wormhole_Func = function(check_pos)
		local node_name = minetest.get_node(check_pos).name
		if node_name ~= wormhole_node_name then
			portal_is_ignited = false;
			if node_name ~= "air" then
				nodes_are_valid = false
				return true -- short-circuit the search
			end
		end
	end

	-- this function returns two bools: portal found, portal is lit
	local is_portal_at_anchorPos = function(anchorPos, orientation)

		nodes_are_valid   = true
		portal_is_ignited = true
		portal_definition.shape.apply_func_to_frame_nodes(anchorPos, orientation, check_frame_Func) -- check_frame_Func affects nodes_are_valid, portal_is_ignited

		if nodes_are_valid then
			-- a valid frame exists at anchorPos, check the wormhole is either ignited or unobstructed
			portal_definition.shape.apply_func_to_wormhole_nodes(anchorPos, orientation, check_wormhole_Func) -- check_wormhole_Func affects nodes_are_valid, portal_is_ignited
		end

		return nodes_are_valid, portal_is_ignited and nodes_are_valid -- returns two bools: portal was found, portal is lit
	end

	local width_minus_1  = portal_definition.shape.size.x - 1
	local height_minus_1 = portal_definition.shape.size.y - 1
	local depth_minus_1  = portal_definition.shape.size.z - 1

	for d = -depth_minus_1, depth_minus_1 do
		for w = -width_minus_1, width_minus_1 do
			for y = -height_minus_1, height_minus_1 do

				local testAnchorPos_x = {x = pos.x + w, y = pos.y + y, z = pos.z + d}
				local portal_found, portal_lit = is_portal_at_anchorPos(testAnchorPos_x, 0)

				if portal_found then
					return testAnchorPos_x, 0, portal_lit
				else
					-- try orthogonal orientation
					local testForAnchorPos_z = {x = pos.x + d, y = pos.y + y, z = pos.z + w}
					portal_found, portal_lit = is_portal_at_anchorPos(testForAnchorPos_z, 90)

					if portal_found then return testForAnchorPos_z, 90, portal_lit end
				end
			end
		end
	end
end


local function build_portal(portal_definition, anchorPos, orientation, destination_wormholePos)

	minetest.place_schematic(
		portal_definition.shape.get_schematicPos_from_anchorPos(anchorPos, orientation),
		portal_definition.shape.schematic_filename,
		orientation,
		nil,
		true
	)
	if DEBUG then minetest.chat_send_all("Placed portal schematic at " ..  minetest.pos_to_string(portal_definition.shape.get_schematicPos_from_anchorPos(anchorPos, orientation)) .. ", orientation " .. orientation) end

	set_portal_metadata(portal_definition, anchorPos, orientation, destination_wormholePos)
end


-- Used to find or build the remote twin after a portal is opened.
-- If a portal is found that is already lit then the destination_wormholePos argument is ignored - the anchorPos
-- of the portal that was found will be returned but its destination will be unchanged.
-- * suggested_anchorPos indicates where the portal should be built
-- * destination_wormholePos is the wormholePos of the destination portal this one will be linked to.
-- * suggested_orientation is the suggested schematic rotation: 0, 90, 180, 270 (0 meaning a portal that faces north/south - i.e. obsidian running east/west)
--
-- Returns the final (anchorPos, orientation), as they may differ from the anchorPos and orientation that was
-- specified if an existing portal was already found there.
local function locate_or_build_portal(portal_definition, suggested_anchorPos, suggested_orientation, destination_wormholePos)

	if DEBUG then minetest.chat_send_all("locate_or_build_portal at " .. minetest.pos_to_string(suggested_anchorPos) .. ", targetted to " .. minetest.pos_to_string(destination_wormholePos) .. ", orientation " .. suggested_orientation) end

	local result_anchorPos   = suggested_anchorPos;
	local result_orientation = suggested_orientation;
	local place_new_portal   = true

	-- Searching for an existing portal at wormholePos seems better than at anchorPos, though isn't important
	local suggested_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(suggested_anchorPos, suggested_orientation)
	local found_anchorPos, found_orientation, is_ignited = is_portal_frame(portal_definition, suggested_wormholePos)

	if found_anchorPos ~= nil then
		-- A portal is already here, we don't have to build one, though we may need to ignite it
		result_anchorPos   = found_anchorPos
		result_orientation = found_orientation

		if is_ignited then
			if DEBUG then minetest.chat_send_all("Build aborted: already a portal at " ..  minetest.pos_to_string(found_anchorPos) .. ", orientation " .. result_orientation) end
		else
			if DEBUG then minetest.chat_send_all("Build aborted: already an unlit portal at " ..  minetest.pos_to_string(found_anchorPos) .. ", orientation " .. result_orientation) end
			-- ignite the portal
			set_portal_metadata_and_ignite(portal_definition, result_anchorPos, result_orientation, destination_wormholePos)
		end
	else
		build_portal(portal_definition, result_anchorPos, result_orientation, destination_wormholePos)
	end
	return result_anchorPos, result_orientation
end


-- use this when determining where to spawn a portal, to avoid overwriting player builds
local function volume_is_natural(minp, maxp)
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")

	local vm = minetest.get_voxel_manip()
	local pos1 = {x = minp.x, y = minp.y, z = minp.z}
	local pos2 = {x = maxp.x, y = maxp.y, z = maxp.z}
	local emin, emax = vm:read_from_map(pos1, pos2)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	for z = pos1.z, pos2.z do
	for y = pos1.y, pos2.y do
		local vi = area:index(pos1.x, y, z)
		for x = pos1.x, pos2.x do
			local id = data[vi] -- Existing node
			if id ~= c_air and id ~= c_ignore then -- These are natural
				local name = minetest.get_name_from_content_id(id)
				if not minetest.registered_nodes[name].is_ground_content then
					return false
				end
			end
			vi = vi + 1
		end
	end
	end

	return true
end


local function find_nether_target_y(target_x, target_z, start_y)
	local nobj_cave_point = minetest.get_perlin(np_cave)
	local air = 0 -- Consecutive air nodes found

	for y = start_y, start_y - 4096, -1 do
		local nval_cave = nobj_cave_point:get3d({x = target_x, y = y, z = target_z})

		if nval_cave > TCAVE then -- Cavern
			air = air + 1
		else -- Not cavern, check if 4 nodes of space above
			if air >= 4 then
				-- Check volume for non-natural nodes
				local minp = {x = target_x - 1, y = y - 1, z = target_z - 2}
				local maxp = {x = target_x + 2, y = y + 3, z = target_z + 2}
				if volume_is_natural(minp, maxp) then
					return y + 2
				else -- Restart search a little lower
					find_nether_target_y(target_x, target_z, y - 16)
				end
			else -- Not enough space, reset air to zero
				air = 0
			end
		end
	end

	return start_y -- Fallback
end


--[[
The normal realm portal has a particular X, Z, it searches downwards for a suitable Y.
It can't be placed in mid-air, and for performance the test for a suitable placement position cannot move downwards in 1 node steps, instead it moves downwards in 16 node steps, so it will almost always be placed buried in solid nodes.
The portal cannot be placed in any volume that contains non-natural nodes (is_ground_content = false) to not grief player builds. This makes it even more likely the portal will be a little way underground.

The portal is placed with air nodes around it to create a space so it isn't embedded in stone.
It is expected that the player has a pickaxe to dig their way out, this is highly likely if they have built a portal and are exploring the nether. The player will not be trapped.

Note that MC also often places portals embedded in stone.

The code could be altered to first try to find a surface position, but if this surface position is unsuitable due to being near player builds, the portal will still move downwards into the ground, so this is unavoidable.

Any search for a suitable resting-on-surface or resting-on-cave-surface position will be somewhat complex, to avoid placement on a tiny floating island or narrow spike etc. which would be impractical or deadly to the player.
A portal room embedded underground is the safest and the most accessible for the player.

So i decided to start the placement position search at y = -16 as that, or a little below, is the most likely suitable position: Ground is almost always present there, it's below any lakes or seas, below most player builds.
Also, the search for non-natural nodes doesn't actually guarantee avoiding player builds, as a player build can be composed of only natural nodes (is_ground_content = true). So even more good reason to start the search a little way underground where player builds are more unlikely. Y = -16 seemed a reasonable compromise between safety and distance from surface.

Each placement position search has to search a volume of nodes for non-natural nodes, this is not lightweight, and many searches may happen if there a lot of underground player builds present. So the code has been written to avoid intensive procedures.
https://github.com/minetest-mods/nether/issues/5#issuecomment-506983676
]]
local function find_surface_target_y(portal_definition, target_x, target_z, start_y)
	for y = start_y, start_y - 256, -16 do
		-- Check volume for non-natural nodes
		local minp = {x = target_x - 1, y = y - 1, z = target_z - 2}
		local maxp = {x = target_x + 2, y = y + 3, z = target_z + 2}
		if volume_is_natural(minp, maxp) then
			return y
		else
			-- players have built here - don't grief.
			-- but reigniting existing portals in portal rooms is fine - desirable even.
			local anchorPos, orientation, is_ignited = is_portal_frame(portal_definition, {x = target_x, y = y, z = target_z})
			if anchorPos ~= nil then
				return y
			end
		end
	end

	return start_y - 256 -- Fallback
end


-- invoked when a player attempts to turn obsidian nodes into an open portal
local function ignite_portal(ignition_pos)

	local ignition_node_name = minetest.get_node(ignition_pos).name

	-- find which sort of portals are made from the node that was clicked on
	local portal_definition = registered_portals[ignition_node_name]
	if portal_definition == nil then
		return false -- no portals are made from the node at ignition_pos
	end

	-- check it was a portal frame that the player is trying to ignite
	local anchorPos, orientation, is_ignited = is_portal_frame(portal_definition, ignition_pos)
	if anchorPos == nil then
		if DEBUG then minetest.chat_send_all("No portal frame found at " .. minetest.pos_to_string(ignition_pos)) end
		return false -- no portal is here
	elseif is_ignited then
		if DEBUG then
			local meta = minetest.get_meta(ignition_pos)
			if meta ~= nil then minetest.chat_send_all("This portal links to " .. meta:get_string("target") .. ". p1=" .. meta:get_string("p1") .. " p2=" .. meta:get_string("p2")) end
		end
		return false -- portal is already ignited
	end
	if DEBUG then minetest.chat_send_all("Found portal frame. Looked at " .. minetest.pos_to_string(ignition_pos) .. ", found at " .. minetest.pos_to_string(anchorPos) .. " orientation " .. orientation) end

	-- pick a destination
	local destination_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(anchorPos, orientation)
	if anchorPos.y < NETHER_DEPTH then
		destination_wormholePos.y = find_surface_target_y(portal_definition, destination_wormholePos.x, destination_wormholePos.z, -16)
	else
		local start_y = NETHER_DEPTH - math.random(500, 1500) -- Search start
		destination_wormholePos.y = find_nether_target_y(destination_wormholePos.x, destination_wormholePos.z, start_y)
	end
	if DEBUG then minetest.chat_send_all("Destinaton set to " .. minetest.pos_to_string(destination_wormholePos)) end

	-- ignition/BURN_BABY_BURN
	set_portal_metadata_and_ignite(portal_definition, anchorPos, orientation, destination_wormholePos)

	return true
end


-- WARNING - this is invoked by on_destruct, so you can't assume there's an accesible node at pos
local function extinguish_portal(pos, node_name)

	-- find which sort of portals are made from the node that was clicked on
	local portal_definition = registered_portals[node_name]
	if portal_definition == nil then
		minetest.log("error", "extinguish_portal() invoked on " .. node_name .. " but no registered portal is constructed from " .. node_name)
		return false -- no portal frames are made from this type of node
	end
	local frame_node_name    = portal_definition.frame_node_name
	local wormhole_node_name = portal_definition.wormhole_node_name

	local meta = minetest.get_meta(pos)
	local p1 = minetest.string_to_pos(meta:get_string("p1"))
	local p2 = minetest.string_to_pos(meta:get_string("p2"))
	local target = minetest.string_to_pos(meta:get_string("target"))
	if not p1 or not p2 then
		return
	end

	minetest.get_node_timer(p1):stop(1)

	for x = p1.x, p2.x do
	for y = p1.y, p2.y do
	for z = p1.z, p2.z do
		local nn = minetest.get_node({x = x, y = y, z = z}).name
		if nn == frame_node_name or nn == wormhole_node_name then
			if nn == wormhole_node_name then
				minetest.remove_node({x = x, y = y, z = z})
			end
			local m = minetest.get_meta({x = x, y = y, z = z})
			m:set_string("p1", "")
			m:set_string("p2", "")
			m:set_string("target", "")
			m:set_string("frame_node_name", "")
		end
	end
	end
	end

	if target ~= nil then extinguish_portal(target, node_name) end
end


-- Sometimes after a portal is placed, concurrent mapgen routines overwrite it.
-- Make portals immortal for ~20 seconds after creation
local function remote_portal_checkup(elapsed, portal_definition, anchorPos, orientation, destination_wormholePos)

	local wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(anchorPos, orientation)
	local wormhole_node = minetest.get_node_or_nil(wormholePos)

	if wormhole_node == nil or wormhole_node.name ~= portal_definition.wormhole_node_name then
		-- ruh roh
		local message = "Newly created portal at " .. minetest.pos_to_string(anchorPos) .. " was overwritten. Attempting to recreate. Issue spotted after " .. elapsed .. " seconds"
		minetest.log("warning", message)
		if DEBUG then minetest.chat_send_all("!!! " .. message) end

		-- A pre-existing portal frame wouldn't have been immediately overwritten, so no need to check for one, just place the portal.
		build_portal(portal_definition, anchorPos, orientation, destination_wormholePos)
	end

	if elapsed < 20 then -- stop checking after 20 seconds
		local delay = elapsed * 2
		minetest.after(delay, remote_portal_checkup, elapsed + delay, portal_definition, anchorPos, orientation, destination_wormholePos)
	end
end


-- invoked when a player is standing in a portal
local function ensure_remote_portal_then_teleport(player, portal_definition, local_anchorPos, local_orientation, destination_wormholePos)

	-- check player is still standing in a portal
	local playerPos = player:getpos()
	playerPos.y = playerPos.y + 0.1 -- Fix some glitches at -8000
	if minetest.get_node(playerPos).name ~= portal_definition.wormhole_node_name then
		return -- the player has moved out of the portal
	end

	-- debounce - check player is still standing in the same portal that called this function
	local meta = minetest.get_meta(playerPos)
	if not vector.equals(local_anchorPos, minetest.string_to_pos(meta:get_string("p1"))) then
		if DEBUG then minetest.chat_send_all("the player already teleported from " .. minetest.pos_to_string(local_anchorPos) .. ", and is now standing in a different portal - " .. meta:get_string("p1")) end
		return -- the player already teleported, and is now standing in a different portal
	end

	local destination_anchorPos = portal_definition.shape.get_anchorPos_from_wormholePos(destination_wormholePos, local_orientation)
	local dest_wormhole_node = minetest.get_node_or_nil(destination_wormholePos)

	if dest_wormhole_node == nil then
		-- area not emerged yet, delay and retry
		if DEBUG then minetest.chat_send_all("ensure_remote_portal_then_teleport() could not find anything yet at " .. minetest.pos_to_string(destination_wormholePos)) end
		minetest.after(1, ensure_remote_portal_then_teleport, player, portal_definition, local_anchorPos, local_orientation, destination_wormholePos)
	else
		local local_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(local_anchorPos, local_orientation)

		if dest_wormhole_node.name == portal_definition.wormhole_node_name then
			-- portal exists
			local destination_orientation = get_orientation_from_param2(dest_wormhole_node.param2)
			portal_definition.shape.disable_portal_trap(destination_anchorPos, destination_orientation)

			-- rotate the player if the destination portal is a different orientation
			local rotation_angle = math.rad(destination_orientation - local_orientation)
			local offset = vector.subtract(playerPos, local_wormholePos) -- preserve player's position in the portal
			local rotated_offset = {x = math.cos(rotation_angle) * offset.x - math.sin(rotation_angle) * offset.z, y = offset.y, z = math.sin(rotation_angle) * offset.x + math.cos(rotation_angle) * offset.z}
			player:setpos(vector.add(destination_wormholePos, rotated_offset))
			player:set_look_horizontal(player:get_look_horizontal() + rotation_angle)
		else
			-- destination portal still needs to be built
			if DEBUG then minetest.chat_send_all("ensure_remote_portal_then_teleport() saw " .. dest_wormhole_node.name .. " at " .. minetest.pos_to_string(destination_wormholePos) .. " rather than a wormhole. Calling locate_or_build_portal()") end

			local new_dest_anchorPos, new_dest_orientation = locate_or_build_portal(portal_definition, destination_anchorPos, local_orientation, local_wormholePos)

			if local_orientation ~= new_dest_orientation or not vector.equals(destination_anchorPos, new_dest_anchorPos) then
				-- Update the local portal's target to match where the existing remote portal was found
				destination_anchorPos   = new_dest_anchorPos
				destination_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(new_dest_anchorPos, new_dest_orientation)
				if DEBUG then minetest.chat_send_all("update target to " .. minetest.pos_to_string(destination_wormholePos)) end

				set_portal_metadata(
					portal_definition,
					local_anchorPos,
					local_orientation,
					destination_wormholePos
				)
			end
			minetest.after(0.1, ensure_remote_portal_then_teleport, player, portal_definition, local_anchorPos, local_orientation, destination_wormholePos)

			-- make sure portal isn't overwritten by ongoing generation/emerge
			minetest.after(2, remote_portal_checkup, 2, portal_definition, new_dest_anchorPos, new_dest_orientation, local_wormholePos)
		end
	end
end


-- run_wormhole() is invoked once per second per portal, handling teleportation and particle effects.
-- See get_timerPos_from_p1_and_p2() for an explanation of where pos will be
function run_wormhole(pos, time_elapsed)

	local run_wormhole_node_func = function(pos)

		if math.random(2) == 1 then -- lets run only 3 particlespawners instead of 6 per portal
			minetest.add_particlespawner({
				amount = 16,
				time = 2,
				minpos = {x = pos.x - 0.25, y = pos.y - 0.25, z = pos.z - 0.25},
				maxpos = {x = pos.x + 0.25, y = pos.y + 0.25, z = pos.z + 0.25},
				minvel = {x = -0.8, y = -0.8, z = -0.8},
				maxvel = {x = 0.8, y = 0.8, z = 0.8},
				minacc = {x = 0, y = 0, z = 0},
				maxacc = {x = 0, y = 0, z = 0},
				minexptime = 0.5,
				maxexptime = 1.5,
				minsize = 0.5,
				maxsize = 1.5,
				collisiondetection = false,
				texture = "nether_particle.png",
				glow = 5
			})
		end

		for _, obj in ipairs(minetest.get_objects_inside_radius(pos, 1)) do
			if obj:is_player() then
				local meta = minetest.get_meta(pos)
				local destination_wormholePos = minetest.string_to_pos(meta:get_string("target"))
				local local_p1                = minetest.string_to_pos(meta:get_string("p1"))
				if destination_wormholePos ~= nil and local_p1 ~= nil then

					-- find out what sort of portal we're in
					local p1_node_name = minetest.get_node(local_p1).name -- todo: use a better way
					local portal_definition = registered_portals[p1_node_name]
					if portal_definition == nil then
						if p1_node_name ~= "ignore" then
							-- I've seen cases where the p1_node_name temporarily returns "ignore", but it comes right - perhaps it happens when playerPos and anchorPos are in different chunks?
							if DEBUG then minetest.chat_send_all("Weirdness: No portal with a \"" .. p1_node_name .. "\" frame is registered. Portal metadata at " .. minetest.pos_to_string(pos) .. " claims node ".. minetest.pos_to_string(local_p1) .. " is its portal corner (p1), but that location contains \"" .. p1_node_name .. "\"") end
						else
							minetest.log("error", "No portal with a \"" .. p1_node_name .. "\" frame is registered. Portal metadata at " .. minetest.pos_to_string(pos) .. " claims node ".. minetest.pos_to_string(local_p1) .. " is its portal corner (p1), but that location contains \"" .. p1_node_name .. "\"")
						end
						return
					end

					-- force emerge of target area
					minetest.get_voxel_manip():read_from_map(destination_wormholePos, destination_wormholePos)
					if not minetest.get_node_or_nil(destination_wormholePos) then
						minetest.emerge_area(vector.subtract(destination_wormholePos, 4), vector.add(destination_wormholePos, 4))
					end

					local local_orientation  = get_orientation_from_param2(minetest.get_node(pos).param2)
					minetest.after(
						3, -- hopefully target area is emerged in 3 seconds
						function()
							ensure_remote_portal_then_teleport(
								obj,
								portal_definition,
								local_p1,
								local_orientation,
								destination_wormholePos
							)
						end
					)
				end
			end
		end
	end

	local p1, p2, frame_node_name
	local meta = minetest.get_meta(pos)
	if meta ~= nil then
		p1              = minetest.string_to_pos(meta:get_string("p1"))
		p2              = minetest.string_to_pos(meta:get_string("p2"))
		--frame_node_name = minetest.string_to_pos(meta:get_string("frame_node_name")) don't rely on this yet until you're sure everything works with old portals that don't have this set
	end
	if p1 ~= nil and p2 ~= nil then
		-- look up the portal shape by what it's built from, so we know where the wormhole nodes will be located
		if frame_node_name == nil then frame_node_name = minetest.get_node(pos).name end -- pos should be a frame node
		local portal_definition = registered_portals[frame_node_name]
		if portal_definition == nil then
			minetest.log("error", "No portal with a \"" .. frame_node_name .. "\" frame is registered. run_wormhole" .. minetest.pos_to_string(pos) .. " was invoked but that location contains \"" .. frame_node_name .. "\"")
		else
			local anchorPos, orientation = portal_definition.shape.get_anchorPos_and_orientation_from_p1_and_p2(p1, p2)
			portal_definition.shape.apply_func_to_wormhole_nodes(anchorPos, orientation, run_wormhole_node_func)
		end
	end
end


minetest.register_lbm({
	label = "Start portal timer",
	name  = "nether:start_portal_timer",
	nodenames = {"nether:portal"},
	run_at_every_load = false,
	action = function(pos, node)
		local p1, p2
		local meta = minetest.get_meta(pos)
		if meta ~= nil then
			p1 = minetest.string_to_pos(meta:get_string("p1"))
			p2 = minetest.string_to_pos(meta:get_string("p1"))
		end
		if p1 ~= nil and p2 ~= nil then
			local timerPos = get_timerPos_from_p1_and_p2(p1, p2)
			local timer = minetest.get_node_timer(timerPos)
			if timer ~= nil then
				timer:start(1)
			elseif DEBUG then
				minetest.chat_send_all("get_node_timer" .. minetest.pos_to_string(timerPos) .. " returned null")
			end
		end
	end
})


-- Nodes

minetest.register_node("nether:portal", {
	description = "Nether Portal",
	tiles = {
		"nether_transparent.png",
		"nether_transparent.png",
		"nether_transparent.png",
		"nether_transparent.png",
		{
			name = "nether_portal.png",
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
		{
			name = "nether_portal.png",
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
	},
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	use_texture_alpha = true,
	walkable = false,
	diggable = false,
	pointable = false,
	buildable_to = false,
	is_ground_content = false,
	drop = "",
	light_source = 5,
	post_effect_color = {a = 180, r = 128, g = 0, b = 128},
	alpha = 192,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.1,  0.5, 0.5, 0.1},
		},
	},
	groups = {not_in_creative_inventory = 1}
})

minetest.register_node(":default:obsidian", {
	description = "Obsidian",
	tiles = {"default_obsidian.png"},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	groups = {cracky = 1, level = 2},

	mesecons = {effector = {
		action_on = function (pos, node)
			ignite_portal(pos, node.name)
		end,
		action_off = function (pos, node)
			extinguish_portal(pos, node.name)
		end
	}},
	on_destruct = function(pos)
		extinguish_portal(pos, "default:obsidian")
	end,
	on_timer = function(pos, elapsed)
		run_wormhole(pos, elapsed)
		return true
	end
})

minetest.register_node("nether:rack", {
	description = "Netherrack",
	tiles = {"nether_rack.png"},
	is_ground_content = true,
	groups = {cracky = 3, level = 2},
	sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("nether:sand", {
	description = "Nethersand",
	tiles = {"nether_sand.png"},
	is_ground_content = true,
	groups = {crumbly = 3, level = 2, falling_node = 1},
	sounds = default.node_sound_gravel_defaults({
		footstep = {name = "default_gravel_footstep", gain = 0.45},
	}),
})

minetest.register_node("nether:glowstone", {
	description = "Glowstone",
	tiles = {"nether_glowstone.png"},
	is_ground_content = true,
	light_source = 14,
	paramtype = "light",
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	sounds = default.node_sound_glass_defaults(),
})

minetest.register_node("nether:brick", {
	description = "Nether Brick",
	tiles = {"nether_brick.png"},
	is_ground_content = false,
	groups = {cracky = 2, level = 2},
	sounds = default.node_sound_stone_defaults(),
})

local fence_texture =
	"default_fence_overlay.png^nether_brick.png^default_fence_overlay.png^[makealpha:255,126,126"

minetest.register_node("nether:fence_nether_brick", {
	description = "Nether Brick Fence",
	drawtype = "fencelike",
	tiles = {"nether_brick.png"},
	inventory_image = fence_texture,
	wield_image = fence_texture,
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	selection_box = {
		type = "fixed",
		fixed = {-1/7, -1/2, -1/7, 1/7, 1/2, 1/7},
	},
	groups = {cracky = 2, level = 2},
	sounds = default.node_sound_stone_defaults(),
})


-- Register stair and slab

stairs.register_stair_and_slab(
	"nether_brick",
	"nether:brick",
	{cracky = 2, level = 2},
	{"nether_brick.png"},
	"nether stair",
	"nether slab",
	default.node_sound_stone_defaults()
)

-- StairsPlus

if minetest.get_modpath("moreblocks") then
	stairsplus:register_all(
		"nether", "brick", "nether:brick", {
			description = "Nether Brick",
			groups = {cracky = 2, level = 2},
			tiles = {"nether_brick.png"},
			sounds = default.node_sound_stone_defaults(),
	})
end


-- Craftitems

minetest.override_item("default:mese_crystal_fragment", {
	on_place = function(stack, _, pt)
		if pt.under and minetest.get_node(pt.under).name == "default:obsidian" then
			local done = ignite_portal(pt.under)
			if done and not minetest.settings:get_bool("creative_mode") then
				stack:take_item()
			end
		end

		return stack
	end,
})

-- Crafting

minetest.register_craft({
	output = "nether:brick 4",
	recipe = {
		{"nether:rack", "nether:rack"},
		{"nether:rack", "nether:rack"},
	}
})

minetest.register_craft({
	output = "nether:fence_nether_brick 6",
	recipe = {
		{"nether:brick", "nether:brick", "nether:brick"},
		{"nether:brick", "nether:brick", "nether:brick"},
	},
})


-- Mapgen

-- Initialize noise object, localise noise and data buffers

local nobj_cave = nil
local nbuf_cave = nil
local dbuf = nil


-- Content ids

local c_air = minetest.get_content_id("air")

--local c_stone_with_coal = minetest.get_content_id("default:stone_with_coal")
--local c_stone_with_iron = minetest.get_content_id("default:stone_with_iron")
local c_stone_with_mese = minetest.get_content_id("default:stone_with_mese")
local c_stone_with_diamond = minetest.get_content_id("default:stone_with_diamond")
local c_stone_with_gold = minetest.get_content_id("default:stone_with_gold")
--local c_stone_with_copper = minetest.get_content_id("default:stone_with_copper")
local c_mese = minetest.get_content_id("default:mese")

local c_gravel = minetest.get_content_id("default:gravel")
local c_dirt = minetest.get_content_id("default:dirt")
local c_sand = minetest.get_content_id("default:sand")

local c_cobble = minetest.get_content_id("default:cobble")
local c_mossycobble = minetest.get_content_id("default:mossycobble")
local c_stair_cobble = minetest.get_content_id("stairs:stair_cobble")

local c_lava_source = minetest.get_content_id("default:lava_source")
local c_lava_flowing = minetest.get_content_id("default:lava_flowing")
local c_water_source = minetest.get_content_id("default:water_source")
local c_water_flowing = minetest.get_content_id("default:water_flowing")

local c_glowstone = minetest.get_content_id("nether:glowstone")
local c_nethersand = minetest.get_content_id("nether:sand")
local c_netherbrick = minetest.get_content_id("nether:brick")
local c_netherrack = minetest.get_content_id("nether:rack")


-- On-generated function

minetest.register_on_generated(function(minp, maxp, seed)
	if minp.y > NETHER_DEPTH then
		return
	end

	local x1 = maxp.x
	local y1 = maxp.y
	local z1 = maxp.z
	local x0 = minp.x
	local y0 = minp.y
	local z0 = minp.z

	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data(dbuf)

	local x11 = emax.x -- Limits of mapchunk plus mapblock shell
	local y11 = emax.y
	local z11 = emax.z
	local x00 = emin.x
	local y00 = emin.y
	local z00 = emin.z

	local ystride = x1 - x0 + 1
	local zstride = ystride * ystride
	local chulens = {x = ystride, y = ystride, z = ystride}
	local minposxyz = {x = x0, y = y0, z = z0}

	nobj_cave = nobj_cave or minetest.get_perlin_map(np_cave, chulens)
	local nvals_cave = nobj_cave:get3dMap_flat(minposxyz, nbuf_cave)

	for y = y00, y11 do -- Y loop first to minimise tcave calculations
		local tcave
		local in_chunk_y = false
		if y >= y0 and y <= y1 then
			if y > yblmax then
				tcave = TCAVE + ((y - yblmax) / BLEND) ^ 2
			else
				tcave = TCAVE
			end
			in_chunk_y = true
		end

		for z = z00, z11 do
			local vi = area:index(x00, y, z) -- Initial voxelmanip index
			local ni
			local in_chunk_yz = in_chunk_y and z >= z0 and z <= z1

			for x = x00, x11 do
				if in_chunk_yz and x == x0 then
					-- Initial noisemap index
					ni = (z - z0) * zstride + (y - y0) * ystride + 1
				end
				local in_chunk_yzx = in_chunk_yz and x >= x0 and x <= x1 -- In mapchunk

				local id = data[vi] -- Existing node
				-- Cave air, cave liquids and dungeons are overgenerated,
				-- convert these throughout mapchunk plus shell
				if id == c_air or -- Air and liquids to air
						id == c_lava_source or
						id == c_lava_flowing or
						id == c_water_source or
						id == c_water_flowing then
					data[vi] = c_air
				-- Dungeons are preserved so we don't need
				-- to check for cavern in the shell
				elseif id == c_cobble or -- Dungeons (preserved) to netherbrick
						id == c_mossycobble or
						id == c_stair_cobble then
					data[vi] = c_netherbrick
				end

				if in_chunk_yzx then -- In mapchunk
					if nvals_cave[ni] > tcave then -- Only excavate cavern in mapchunk
						data[vi] = c_air
					elseif id == c_mese then -- Mese block to lava
						data[vi] = c_lava_source
					elseif id == c_stone_with_gold or -- Precious ores to glowstone
							id == c_stone_with_mese or
							id == c_stone_with_diamond then
						data[vi] = c_glowstone
					elseif id == c_gravel or -- Blob ore to nethersand
							id == c_dirt or
							id == c_sand then
						data[vi] = c_nethersand
					else -- All else to netherstone
						data[vi] = c_netherrack
					end

					ni = ni + 1 -- Only increment noise index in mapchunk
				end

				vi = vi + 1
			end
		end
	end

	vm:set_data(data)
	vm:set_lighting({day = 0, night = 0})
	vm:calc_lighting()
	vm:update_liquids()
	vm:write_to_map()
end)
