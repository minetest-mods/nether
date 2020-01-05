-- see portal_api.txt for documentation
local DEBUG = false
local IGNORE_MODSTORAGE_PORTALS = false -- set true if you don't want portals to remember where they were linked - sometimes it's handy for debugging to have the portal always recalculate its target

nether.registered_portals = {}

-- gives the colour values in nether_portals_palette.png that are used by the wormhole colorfacedir
-- hardware colouring.
nether.portals_palette = {
	[0] = {r = 128, g =   0, b = 128}, -- traditional/magenta
	[1] = {r =   0, g =   0, b =   0}, -- black
	[2] = {r =  19, g =  19, b = 255}, -- blue
	[3] = {r =  55, g = 168, b =   0}, -- green
	[4] = {r = 141, g = 237, b = 255}, -- cyan
	[5] = {r = 221, g =   0, b =   0}, -- red
	[6] = {r = 255, g = 240, b =   0}, -- yellow
	[7] = {r = 255, g = 255, b = 255}  -- white
}


--[[

Positions
=========

p1 & p2       p1 and p2 is the system used by earlier versions of the nether mod, which the portal_api
              is forwards and backwards compatible with.
              p1 is the bottom/west/south corner of the portal, and p2 is the opposite corner, together
              they define the bounding volume for the portal.
              The value of p1 and p2 is kept in the metadata of every node in the portal

WormholePos   The location of the node that a portal's target is set to, and a player is teleported 
              to. It can also be used to test whether a portal is active.

AnchorPos     Introduced by the portal_api. Coordinates for portals are normally given in terms of 
              the AnchorPos. The AnchorPos does not change with portal orientation - portals rotate
              around the AnchorPos. Ideally an AnchorPos would be near the bottom center of a portal
              shape, but this is not the case with PortalShape_Traditional to keep comptaibility with 
              earlier versions of the nether mod.
              Usually an orientation is required with an AnchorPos.

TimerPos      The portal_api replaces ABMs with a single node timer per portal, and the TimerPos is the 
              node in which that timer is located. Extra metadata is also kept in the TimerPos node.


Portal shapes
=============


  For the PortalShape_Traditional implementation, p1, p2, anchorPos, wormholdPos and TimerPos are defined 
  as follows:
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
    AnchorPos|TimerPos|        |        |
    |   p1   |        |        |        |
    +--------+--------+--------+--------+

    +X/East or +Z/North ----->

A better location for AnchorPos would be directly under WormholePos, as it's more centered
and you don't need to know the portal's orientation to find AnchorPos from the WormholePos
or vice-versa, however AnchorPos is in the bottom/south/west-corner to keep compatibility
with earlier versions of nether mod (which only records portal corners p1 & p2 in the node
metadata).

Orientation is yaw, either 0 or 90, 0 meaning a portal that faces north/south - i.e. obsidian 
running east/west.
]]


-- This object defines a portal's shape, segregating the shape logic code from portal behaviour code.
-- You can create a new "PortalShape" definition object which implements the same
-- functions if you wish to register a custom shaped portal in register_portal(). Examples of other
-- shapes follow after PortalShape_Traditional.
-- Since it's symmetric, this PortalShape definition has only implemented orientations of 0 and 90
nether.PortalShape_Traditional = {
	name = "Traditional",
	size = vector.new(4, 5, 1), -- size of the portal, and not necessarily the size of the schematic,
	                            -- which may clear area around the portal.
	schematic_filename = nether.path .. "/schematics/nether_portal.mts",
	is_horizontal  = false, -- whether the wormhole is a vertical or horizontal surface

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

	-- p1 and p2 are used to keep maps compatible with earlier versions of this mod.
	-- p1 is the bottom/west/south corner of the portal, and p2 is the opposite corner, together
	-- they define the bounding volume for the portal.
	get_p1_and_p2_from_anchorPos = function(self, anchorPos, orientation)
		assert(orientation, "no orientation passed")
		assert(self ~= nil and self.name == nether.PortalShape_Traditional.name, "Must pass self as first argument, or use shape:func() instead of shape.func()")
		local p1 = anchorPos -- PortalShape_Traditional puts the anchorPos at p1 for backwards&forwards compatibility
		local p2

		if orientation == 0 then
			p2 = {x = p1.x + self.size.x - 1, y = p1.y + self.size.y - 1, z = p1.z                  }
		else
			p2 = {x = p1.x,                   y = p1.y + self.size.y - 1, z = p1.z + self.size.x - 1}
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
			minetest.log("error", "get_anchorPos_and_orientation_from_p1_and_p2 failed on  p1=" .. minetest.pos_to_string(p1) .. " p2=" .. minetest.pos_to_string(p2))
		end
	end,

	-- returns true if function was applied to all frame nodes
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

	-- returns true if function was applied to all wormhole nodes
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
	-- If portal can appear in mid-air then can also check for that and add a platform.
	disable_portal_trap = function(anchorPos, orientation)
		assert(orientation, "no orientation passed")

		-- Not implemented yet. It may not need to be implemented because if you
		-- wait in a portal long enough you teleport again. So a trap portal would have to link
		-- to one of two blocked-in portals which link to each other - which is possible, but
		-- quite extreme.
	end
} -- End of PortalShape_Traditional class


-- Example alternative PortalShape
nether.PortalShape_Circular = {
	name = "Circular",
	size = vector.new(7, 7, 1), -- size of the portal, and not necessarily the size of the schematic,
	                            -- which may clear area around the portal.
	schematic_filename = nether.path .. "/schematics/nether_portal_circular.mts",
	is_horizontal  = false, -- whether the wormhole is a vertical or horizontal surface

	-- returns the coords for minetest.place_schematic() that will place the schematic on the anchorPos
	get_schematicPos_from_anchorPos = function(anchorPos, orientation)
		assert(orientation, "no orientation passed")
		if orientation == 0 then
			return {x = anchorPos.x - 3,     y = anchorPos.y, z = anchorPos.z - 3}
		else
			return {x = anchorPos.x - 3, y = anchorPos.y, z = anchorPos.z - 3   }
		end
	end,

	get_wormholePos_from_anchorPos = function(anchorPos, orientation)
		-- wormholePos is the node above anchorPos
		return {x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z}
	end,

	get_anchorPos_from_wormholePos = function(wormholePos, orientation)
		-- wormholePos is the node above anchorPos
		return {x = wormholePos.x, y = wormholePos.y - 1, z = wormholePos.z}
	end,

	-- p1 and p2 are used to keep maps compatible with earlier versions of this mod.
	-- p1 is the bottom/west/south corner of the portal, and p2 is the opposite corner, together
	-- they define the bounding volume for the portal.
	get_p1_and_p2_from_anchorPos = function(self, anchorPos, orientation)
		assert(orientation, "no orientation passed")
		assert(self ~= nil and self.name == nether.PortalShape_Circular.name, "Must pass self as first argument, or use shape:func() instead of shape.func()")
		local p1 = anchorPos -- PortalShape_Traditional puts the anchorPos at p1 for backwards&forwards compatibility
		local p2

		if orientation == 0 then
			p1 = {x = anchorPos.x - 3,        y = anchorPos.y,            z = anchorPos.z           }
			p2 = {x = p1.x + self.size.x - 1, y = p1.y + self.size.y - 1, z = p1.z                  }
		else
			p1 = {x = anchorPos.x,            y = anchorPos.y,            z = anchorPos.z - 3       }
			p2 = {x = p1.x,                   y = p1.y + self.size.y - 1, z = p1.z + self.size.x - 1}
		end
		return p1, p2
	end,

	get_anchorPos_and_orientation_from_p1_and_p2 = function(p1, p2)
		if p1.z == p2.z then
			return {x= p1.x + 3, y = p1.y, z = p1.z    },  0
		elseif p1.x == p2.x then
			return {x= p1.x,     y = p1.y, z = p1.z + 3}, 90
		end
	end,

	apply_func_to_frame_nodes = function(anchorPos, orientation, func)
		local shortCircuited
		if orientation == 0 then
			-- use short-circuiting of boolean evaluation to allow func() to cause an abort by returning true
			shortCircuited =
				func({x = anchorPos.x + 0, y = anchorPos.y + 0, z = anchorPos.z}) or
				func({x = anchorPos.x + 1, y = anchorPos.y + 0, z = anchorPos.z}) or func({x = anchorPos.x - 1, y = anchorPos.y + 0, z = anchorPos.z}) or
				func({x = anchorPos.x + 2, y = anchorPos.y + 1, z = anchorPos.z}) or func({x = anchorPos.x - 2, y = anchorPos.y + 1, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 2, z = anchorPos.z}) or func({x = anchorPos.x - 3, y = anchorPos.y + 2, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 3, z = anchorPos.z}) or func({x = anchorPos.x - 3, y = anchorPos.y + 3, z = anchorPos.z}) or
				func({x = anchorPos.x + 3, y = anchorPos.y + 4, z = anchorPos.z}) or func({x = anchorPos.x - 3, y = anchorPos.y + 4, z = anchorPos.z}) or
				func({x = anchorPos.x + 2, y = anchorPos.y + 5, z = anchorPos.z}) or func({x = anchorPos.x - 2, y = anchorPos.y + 5, z = anchorPos.z}) or
				func({x = anchorPos.x + 1, y = anchorPos.y + 6, z = anchorPos.z}) or func({x = anchorPos.x - 1, y = anchorPos.y + 6, z = anchorPos.z}) or
				func({x = anchorPos.x + 0, y = anchorPos.y + 6, z = anchorPos.z})
		else
			shortCircuited =
				func({x = anchorPos.x, y = anchorPos.y + 0, z = anchorPos.z + 0}) or
				func({x = anchorPos.x, y = anchorPos.y + 0, z = anchorPos.z + 1}) or func({x = anchorPos.x, y = anchorPos.y + 0, z = anchorPos.z - 1}) or
				func({x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z + 2}) or func({x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z - 2}) or
				func({x = anchorPos.x, y = anchorPos.y + 2, z = anchorPos.z + 3}) or func({x = anchorPos.x, y = anchorPos.y + 2, z = anchorPos.z - 3}) or
				func({x = anchorPos.x, y = anchorPos.y + 3, z = anchorPos.z + 3}) or func({x = anchorPos.x, y = anchorPos.y + 3, z = anchorPos.z - 3}) or
				func({x = anchorPos.x, y = anchorPos.y + 4, z = anchorPos.z + 3}) or func({x = anchorPos.x, y = anchorPos.y + 4, z = anchorPos.z - 3}) or
				func({x = anchorPos.x, y = anchorPos.y + 5, z = anchorPos.z + 2}) or func({x = anchorPos.x, y = anchorPos.y + 5, z = anchorPos.z - 2}) or
				func({x = anchorPos.x, y = anchorPos.y + 6, z = anchorPos.z + 1}) or func({x = anchorPos.x, y = anchorPos.y + 6, z = anchorPos.z - 1}) or
				func({x = anchorPos.x, y = anchorPos.y + 6, z = anchorPos.z + 0})
		end
		return not shortCircuited
	end,

	-- returns true if function was applied to all wormhole nodes
	apply_func_to_wormhole_nodes = function(anchorPos, orientation, func)
		local xRange = 2
		local zRange = 0
		if orientation ~= 0 then
			xRange = 0
			zRange = 2	
		end
		
		local xEdge, yEdge, zEdge
		local pos = {}
		for x = -xRange, xRange do
			pos.x = anchorPos.x + x
			xEdge = x == -xRange or x == xRange
			for z = -zRange, zRange do
				zEdge = z == -zRange or z == zRange
				pos.z = anchorPos.z + z
				for y = 1, 5 do
					yEdge = y == 1 or y == 5			
					if not (yEdge and xEdge and zEdge) then
						pos.y = anchorPos.y + y
						if func(pos) then
							-- func() caused an abort by returning true
							return false
						end
					end
				end
			end
		end

		return true
	end,

	-- Check for whether the portal is blocked in, and if so then provide a safe way
	-- on one side for the player to step out of the portal. Suggest including a roof
	-- incase the portal was blocked with lava flowing from above.
	-- If portal can appear in mid-air then can also check for that and add a platform.
	disable_portal_trap = function(anchorPos, orientation)
		assert(orientation, "no orientation passed")

		-- Not implemented.
	end
} -- End of PortalShape_Circular class


-- Example alternative PortalShape
-- This platform shape is symmetrical around the y-axis, so the orientation value never matters.
nether.PortalShape_Platform = {
	name = "Platform",
	size = vector.new(5, 2, 5), -- size of the portal, and not necessarily the size of the schematic,
	                            -- which may clear area around the portal.
	schematic_filename = nether.path .. "/schematics/nether_portal_platform.mts",
	is_horizontal  = true, -- whether the wormhole is a vertical or horizontal surface

	-- returns the coords for minetest.place_schematic() that will place the schematic on the anchorPos
	get_schematicPos_from_anchorPos = function(anchorPos, orientation)
		return {x = anchorPos.x - 2, y = anchorPos.y, z = anchorPos.z - 2}
	end,

	get_wormholePos_from_anchorPos = function(anchorPos, orientation)
		-- wormholePos is the node above anchorPos
		return {x = anchorPos.x, y = anchorPos.y + 1, z = anchorPos.z}
	end,

	get_anchorPos_from_wormholePos = function(wormholePos, orientation)
		-- wormholePos is the node above anchorPos
		return {x = wormholePos.x, y = wormholePos.y - 1, z = wormholePos.z}
	end,

	-- p1 and p2 are used to keep maps compatible with earlier versions of this mod.
	-- p1 is the bottom/west/south corner of the portal, and p2 is the opposite corner, together
	-- they define the bounding volume for the portal.
	get_p1_and_p2_from_anchorPos = function(self, anchorPos, orientation)
		assert(self ~= nil and self.name == nether.PortalShape_Platform.name, "Must pass self as first argument, or use shape:func() instead of shape.func()")
		local p1 = {x = anchorPos.x - 2, y = anchorPos.y,     z = anchorPos.z - 2}
		local p2 = {x = anchorPos.x + 2, y = anchorPos.y + 1, z = anchorPos.z + 2}
		return p1, p2
	end,

	get_anchorPos_and_orientation_from_p1_and_p2 = function(p1, p2)
		return {x= p1.x + 2, y = p1.y, z = p1.z + 2},  0
	end,

	apply_func_to_frame_nodes = function(anchorPos, orientation, func)
		local shortCircuited
		local yPlus1 = anchorPos.y + 1
		-- use short-circuiting of boolean evaluation to allow func() to cause an abort by returning true
		shortCircuited =
			func({x = anchorPos.x - 2, y = yPlus1, z = anchorPos.z - 1}) or func({x = anchorPos.x + 2, y = yPlus1, z = anchorPos.z - 1}) or
			func({x = anchorPos.x - 2, y = yPlus1, z = anchorPos.z    }) or func({x = anchorPos.x + 2, y = yPlus1, z = anchorPos.z    }) or
			func({x = anchorPos.x - 2, y = yPlus1, z = anchorPos.z + 1}) or func({x = anchorPos.x + 2, y = yPlus1, z = anchorPos.z + 1}) or

			func({x = anchorPos.x - 1, y = yPlus1, z = anchorPos.z - 2}) or func({x = anchorPos.x - 1, y = yPlus1, z = anchorPos.z + 2}) or
			func({x = anchorPos.x    , y = yPlus1, z = anchorPos.z - 2}) or func({x = anchorPos.x    , y = yPlus1, z = anchorPos.z + 2}) or
			func({x = anchorPos.x + 1, y = yPlus1, z = anchorPos.z - 2}) or func({x = anchorPos.x + 1, y = yPlus1, z = anchorPos.z + 2}) or

			func({x = anchorPos.x - 1, y = anchorPos.y, z = anchorPos.z - 1}) or
			func({x = anchorPos.x - 1, y = anchorPos.y, z = anchorPos.z    }) or
			func({x = anchorPos.x - 1, y = anchorPos.y, z = anchorPos.z + 1}) or
			func({x = anchorPos.x    , y = anchorPos.y, z = anchorPos.z - 1}) or
			func({x = anchorPos.x    , y = anchorPos.y, z = anchorPos.z    }) or
			func({x = anchorPos.x    , y = anchorPos.y, z = anchorPos.z + 1}) or
			func({x = anchorPos.x + 1, y = anchorPos.y, z = anchorPos.z - 1}) or
			func({x = anchorPos.x + 1, y = anchorPos.y, z = anchorPos.z    }) or
			func({x = anchorPos.x + 1, y = anchorPos.y, z = anchorPos.z + 1})
		return not shortCircuited
	end,

	-- returns true if function was applied to all wormhole nodes
	apply_func_to_wormhole_nodes = function(anchorPos, orientation, func)
		local shortCircuited
		local yPlus1 = anchorPos.y + 1
		-- use short-circuiting of boolean evaluation to allow func() to cause an abort by returning true
		shortCircuited =
			func({x = anchorPos.x - 1, y = yPlus1, z = anchorPos.z - 1}) or
			func({x = anchorPos.x - 1, y = yPlus1, z = anchorPos.z    }) or
			func({x = anchorPos.x - 1, y = yPlus1, z = anchorPos.z + 1}) or
			func({x = anchorPos.x    , y = yPlus1, z = anchorPos.z - 1}) or
			func({x = anchorPos.x    , y = yPlus1, z = anchorPos.z    }) or
			func({x = anchorPos.x    , y = yPlus1, z = anchorPos.z + 1}) or
			func({x = anchorPos.x + 1, y = yPlus1, z = anchorPos.z - 1}) or
			func({x = anchorPos.x + 1, y = yPlus1, z = anchorPos.z    }) or
			func({x = anchorPos.x + 1, y = yPlus1, z = anchorPos.z + 1})
		return not shortCircuited
	end,

	-- Check for suffocation
	disable_portal_trap = function(anchorPos, orientation)

		-- Not implemented.
	end
} -- End of PortalShape_Platform class


--====================================================--
--======== End of PortalShape implementations ========--
--====================================================--




-- Portal implementation functions --
-- =============================== --

-- list of node names that are used as frame nodes by registered portals
local is_frame_node = {}
local ignition_item_name
local S = nether.get_translator
local mod_storage = minetest.get_mod_storage()
local malleated_filenames = {}


local function get_timerPos_from_p1_and_p2(p1, p2)
	-- Pick a frame node for the portal's timer.
	--
	-- The timer event will need to know the portal definition, which can be determined by
	-- what the portal frame is made from, so the timer node should be on the frame.
	-- The timer event will also need to know its portal orientation, but unless someone
	-- makes a cubic portal shape, orientation can be determined from p1 and p2 in the node's
	-- metadata (frame nodes don't have orientation set in param2 like wormhole nodes do).
	--
	-- We shouldn't pick p1 or p2 as it's possible for two orthogonal portals to share
	-- the same p1, etc. - or at least it was - there's code to try to stop that now.
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

-- orientation is the yaw rotation degrees passed to place_schematic: 0, 90, 180, or 270
-- color is a value from 0 to 7 corresponding to the color of pixels in nether_portals_palette.png
-- portal_is_horizontal is a bool indicating whether the portal lies flat or stands vertically
local function get_colorfacedir_from_color_and_orientation(color, orientation, portal_is_horizontal)
	assert(orientation, "no orientation passed")

	local axis_direction, rotation
	local dir = math.floor((orientation % 360) / 90 + 0.5)

	-- if the portal is vertical then node axis direction will be +Y (up) and portal orientation
	-- will set the node's rotation.
	-- if the portal is horizontal then the node axis direction reflects the yaw orientation and
	-- the node's rotation will be whatever's needed to keep the texture horizontal (either 0 or 1)
	if portal_is_horizontal then
		if dir == 0 then axis_direction = 1 end -- North
		if dir == 1 then axis_direction = 3 end -- East
		if dir == 2 then axis_direction = 2 end -- South
		if dir == 3 then axis_direction = 4 end -- West
		rotation = math.floor(axis_direction / 2); -- a rotation is only needed if axis_direction is east or west
	else
		axis_direction = 0 -- 0 is up, or +Y
		rotation = dir
	end
	
	-- wormhole nodes have a paramtype2 of colorfacedir, which means the
	-- high 3 bits are palette, followed by 3 direction bits and 2 rotation bits.
	-- We set the palette bits and rotation
	return rotation + axis_direction * 4 + color * 32
end

local function get_orientation_from_colorfacedir(param2)

	local axis_direction = 0
	-- Strip off the top 6 bits to leave the 2 rotation bits, unfortunately MT lua has no bitwise '&'
	-- (high 3 bits are palette, followed by 3 direction bits then 2 rotation bits)
	if param2 >= 128 then param2 = param2 - 128 end
	if param2 >=  64 then param2 = param2 -  64 end
	if param2 >=  32 then param2 = param2 -  32 end
	if param2 >=  16 then param2 = param2 -  16; axis_direction = axis_direction + 4 end
	if param2 >=   8 then param2 = param2 -   8; axis_direction = axis_direction + 2 end
	if param2 >=   4 then param2 = param2 -   4; axis_direction = axis_direction + 1 end

	-- if the portal is vertical then node axis direction will be +Y (up) and portal orientation
	-- will set the node's rotation.
	-- if the portal is horizontal then the node axis direction reflects the yaw orientation and
	-- the node's rotation will be whatever's needed to keep the texture horizontal (either 0 or 1)
	if axis_direction == 0 or axis_direction == 5 then
		-- portal is vertical
		return param2 * 90
	else
		if axis_direction == 1 then return   0 end
		if axis_direction == 3 then return  90 end
		if axis_direction == 2 then return 180 end
		if axis_direction == 4 then return 270 end
	end
end

-- Combining frame_node_name, p1, and p2 will always be enough to uniquely identify a portal_definition
-- WITHOUT needing to inspect the world. register_portal() will enforce this.
-- This function does not require the portal to be in a loaded chunk.
-- Returns nil if no portal_definition matches the arguments
local function get_portal_definition(frame_node_name, p1, p2)

	local size = vector.add(vector.subtract(p2, p1), 1)
	local rotated_size = {x = size.z, y = size.y, z = size.x}

	for _, portal_def in pairs(nether.registered_portals) do
		if portal_def.frame_node_name == frame_node_name then
			if vector.equals(size, portal_def.shape.size) or vector.equals(rotated_size, portal_def.shape.size) then
				return portal_def
			end
		end
	end
	return nil
end

-- Returns a list of all portal_definitions with a frame made of frame_node_name.
-- Ideally no two portal types will be built from the same frame material so this call might be enough
-- to uniquely identify a portal_definition without needing to inspect the world, HOWEVER we shouldn't
-- cramp anyone's style and prohibit non-nether use of obsidian to make portals, so it returns a list.
-- If the list contains more than one item then routines like ignite_portal() will have to search twice
-- for a portal and take twice the CPU.
local function list_portal_definitions_for_frame_node(frame_node_name)
	local result = {}
	for _, portal_def in pairs(nether.registered_portals) do
		if portal_def.frame_node_name == frame_node_name then table.insert(result, portal_def) end
	end
	return result
end


-- Add portal information to mod storage, so new portals may find existing portals near the target location.
-- Do this whenever a portal is created or changes its ignition state
local function store_portal_location_info(portal_name, anchorPos, orientation, ignited)
	if not IGNORE_MODSTORAGE_PORTALS then 
		mod_storage:set_string(
			minetest.pos_to_string(anchorPos) .. " is " .. portal_name, 
			minetest.serialize({orientation = orientation, active = ignited})
		)
	end
end

-- Remove portal information from mod storage.
-- Do this if a portal frame is destroyed such that it cannot be ignited anymore.
local function remove_portal_location_info(portal_name, anchorPos)
	if not IGNORE_MODSTORAGE_PORTALS then 
		mod_storage:set_string(minetest.pos_to_string(anchorPos) .. " is " .. portal_name, "")
	end
end

-- Returns a table of the nearest portals to anchorPos indexed by distance, based on mod_storage
-- data.
-- Only portals in the same realm as the anchorPos will be returned, even if y_factor is 0.
-- WARNING: Portals are not checked, and inactive portals especially may have been damaged without
-- being removed from the mod_storage data. Check these portals still exist before using them, and
-- invoke remove_portal_location_info() on any found to no longer exist.
--
-- A y_factor of 0 means y does not affect the distance_limit, a y_factor of 1 means y is included,
-- and a y_factor of 2 would squash the search-sphere by a factor of 2 on the y-axis, etc.
-- Pass a nil or negative distance_limit to indicate no distance limit
local function list_closest_portals(portal_definition, anchorPos, distance_limit, y_factor)

	local result = {}

	if not IGNORE_MODSTORAGE_PORTALS then 

		local isRealm = portal_definition.is_within_realm(anchorPos)
		if distance_limit == nil then distance_limit = -1 end
		if       y_factor == nil then       y_factor =  1 end

		for key, value in pairs(mod_storage:to_table().fields) do
			local closingBrace = key:find(")", 6, true)
			if closingBrace ~= nil then 
				local found_anchorPos = minetest.string_to_pos(key:sub(0, closingBrace))
				if found_anchorPos ~= nil and portal_definition.is_within_realm(found_anchorPos) == isRealm then
					local found_name = key:sub(closingBrace + 5)
					if found_name == portal_definition.name then
						local x = anchorPos.x - found_anchorPos.x
						local y = anchorPos.y - found_anchorPos.y
						local z = anchorPos.z - found_anchorPos.z
						local distance = math.hypot(y * y_factor, math.hypot(x, z))
						if distance <= distance_limit or distance_limit < 0 then
							local info = minetest.deserialize(value) or {}
							if DEBUG then minetest.chat_send_all("found " .. found_name .. " listed at distance " .. distance ..  " (within " .. distance_limit .. ") from dest " .. minetest.pos_to_string(anchorPos) .. ", found: " .. minetest.pos_to_string(found_anchorPos) .. " orientation " .. info.orientation) end
							info.anchorPos = found_anchorPos
							info.distance  = distance
							result[distance] = info
						end
					end
				end
			end
		end
	end
	return result
end


-- the timerNode is used to keep the metadata as that node already needs to be known any time a portal is stopped or run
-- see also ambient_sound_stop()
function ambient_sound_play(portal_definition, soundPos, timerNodeMeta)
	if portal_definition.sounds.ambient ~= nil then
		local soundLength = portal_definition.sounds.ambient.length
		if soundLength == nil then soundLength = 3 end
		local lastPlayed = timerNodeMeta:get_int("ambient_sound_last_played")

		-- Using "os.time() % soundLength == 0" is lightweight but means delayed starts, so trying a stored lastPlayed
		if os.time() >= lastPlayed + soundLength then
			local soundHandle = minetest.sound_play(portal_definition.sounds.ambient, {pos = soundPos, max_hear_distance = 8})
			if timerNodeMeta ~= nil then 
				timerNodeMeta:set_int("ambient_sound_handle", soundHandle)
				timerNodeMeta:set_int("ambient_sound_last_played", os.time())
			end
		end
	end
end

-- the timerNode is used to keep the metadata as that node already needs to be known any time a portal is stopped or run
-- see also ambient_sound_play()
function ambient_sound_stop(timerNodeMeta)
	if timerNodeMeta ~= nil then
		local soundHandle = timerNodeMeta:get_int("ambient_sound_handle")
		minetest.sound_fade(soundHandle, -3, 0)
		
		-- clear the metadata
		timerNodeMeta:set_string("ambient_sound_handle", "")
		timerNodeMeta:set_string("ambient_sound_last_played", "")
	end
end


-- WARNING - this is invoked by on_destruct, so you can't assume there's an accesible node at pos
function extinguish_portal(pos, node_name, frame_was_destroyed)

	-- mesecons seems to invoke action_off() 6 times every time you place a block?
	if DEBUG then minetest.chat_send_all("extinguish_portal" .. minetest.pos_to_string(pos) .. " " .. node_name) end

	local meta = minetest.get_meta(pos)
	local p1 = minetest.string_to_pos(meta:get_string("p1"))
	local p2 = minetest.string_to_pos(meta:get_string("p2"))
	local target = minetest.string_to_pos(meta:get_string("target"))
	if p1 == nil or p2 == nil then
		if DEBUG then minetest.chat_send_all("    no active portal found to extinguish") end
		return
	end

	local portal_definition = get_portal_definition(node_name, p1, p2)
	if portal_definition == nil then
		minetest.log("error", "extinguish_portal() invoked on " .. node_name .. " but no registered portal is constructed from " .. node_name)
		return -- no portal frames are made from this type of node
	end
	
	if portal_definition.sounds.extinguish ~= nil then
		minetest.sound_play(portal_definition.sounds.extinguish, {pos = p1})
	end

	-- stop timer and ambient sound
	local timerPos = get_timerPos_from_p1_and_p2(p1, p2)
	minetest.get_node_timer(timerPos):stop()
	ambient_sound_stop(minetest.get_meta(timerPos))

	-- update the ignition state in the portal location info
	local anchorPos, orientation = portal_definition.shape.get_anchorPos_and_orientation_from_p1_and_p2(p1, p2)
	if frame_was_destroyed then 
		remove_portal_location_info(portal_definition.name, anchorPos)
	else
		store_portal_location_info(portal_definition.name, anchorPos, orientation, false)
	end

	local frame_node_name    = portal_definition.frame_node_name
	local wormhole_node_name = portal_definition.wormhole_node_name


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
			m:set_string("portal_type", "")
		end
	end
	end
	end

	if target ~= nil then
		if DEBUG then minetest.chat_send_all("    attempting to also extinguish target with wormholePos " .. minetest.pos_to_string(target)) end
		extinguish_portal(target, node_name) 
	end

	if portal_definition.on_extinguish ~= nil then 
		portal_definition.on_extinguish(portal_definition, anchorPos, orientation)
	end
end




-- Note: will extinguish any portal using the same nodes that are being set
local function set_portal_metadata(portal_definition, anchorPos, orientation, destination_wormholePos, ignite)

	if DEBUG then minetest.chat_send_all("set_portal_metadata(ignite=" .. tostring(ignite) .. ") at " .. minetest.pos_to_string(anchorPos) .. " orient " .. orientation .. ", setting to target " .. minetest.pos_to_string(destination_wormholePos)) end

	-- Portal position is stored in metadata as p1 and p2 to keep maps compatible with earlier versions of this mod.
	-- p1 is the bottom/west/south corner of the portal, and p2 is the opposite corner, together
	-- they define the bounding volume for the portal.
	local p1, p2 = portal_definition.shape:get_p1_and_p2_from_anchorPos(anchorPos, orientation)
	local p1_string, p2_string = minetest.pos_to_string(p1), minetest.pos_to_string(p2)
	local param2 = get_colorfacedir_from_color_and_orientation(portal_definition.wormhole_node_color, orientation, portal_definition.shape.is_horizontal)

	local update_aborted-- using closures to allow the updateFunc to return extra information - by setting this variable

	local updateFunc = function(pos)

		local meta = minetest.get_meta(pos)

		if ignite then
			local node_name = minetest.get_node(pos).name
			if node_name == "air" then
				minetest.set_node(pos, {name = portal_definition.wormhole_node_name, param2 = param2})
			end

			local existing_p1 = meta:get_string("p1")
			if existing_p1 ~= "" then
				local existing_p2 = meta:get_string("p2")
				if existing_p1 ~= p1_string or existing_p2 ~= p2_string then
					if DEBUG then minetest.chat_send_all("set_portal_metadata() found existing metadata from another portal: existing_p1 " .. existing_p1 .. ", existing_p2" .. existing_p2 .. ", p1 " .. p1_string .. ", p2 " .. p2_string .. ", will existinguish existing portal...") end
					-- this node is already part of another portal, so extinguish that, because nodes only
					-- contain a link in the metadata to one portal, and being part of two allows a slew of bugs
					extinguish_portal(pos, node_name, false)

					-- clear the metadata to avoid causing a loop if extinguish_portal() fails on this node (e.g. it only works on frame nodes)
					meta:set_string("p1",          nil)
					meta:set_string("p2",          nil)
					meta:set_string("target",      nil)
					meta:set_string("portal_type", nil)

					update_aborted = true
					return true -- short-circuit the update
				end
			end
		end

		meta:set_string("p1",              minetest.pos_to_string(p1))
		meta:set_string("p2",              minetest.pos_to_string(p2))
		meta:set_string("target",          minetest.pos_to_string(destination_wormholePos))

		if portal_definition.name ~= "nether_portal" then
			-- Legacy portals won't have this extra metadata, so don't rely on it.
			-- It's not strictly necessary for PortalShape_Traditional as we know that p1 is part of
			-- the frame and we can look up the portal type from p1, p2, and frame node name.
			-- Being able to read this from the metadata means other portal shapes needn't have their
			-- frame at the timerPos, it may handle unloaded nodes better, and it saves an extra call
			-- to minetest.getnode().
			meta:set_string("portal_type", portal_definition.name)
		end
	end

	repeat
		update_aborted = false
		portal_definition.shape.apply_func_to_frame_nodes(anchorPos, orientation, updateFunc)
		portal_definition.shape.apply_func_to_wormhole_nodes(anchorPos, orientation, updateFunc)
	until not update_aborted

	local timerPos = get_timerPos_from_p1_and_p2(p1, p2)
	minetest.get_node_timer(timerPos):start(1)

	store_portal_location_info(portal_definition.name, anchorPos, orientation, true)
end

local function set_portal_metadata_and_ignite(portal_definition, anchorPos, orientation, destination_wormholePos)
	set_portal_metadata(portal_definition, anchorPos, orientation, destination_wormholePos, true)
end


-- this function returns two bools: portal found, portal is lit
local function is_portal_at_anchorPos(portal_definition, anchorPos, orientation, force_chunk_load)

	local nodes_are_valid   -- using closures to allow the check functions to return extra information - by setting this variable
	local portal_is_ignited -- using closures to allow the check functions to return extra information - by setting this variable

	local frame_node_name = portal_definition.frame_node_name
	local check_frame_Func = function(check_pos)
		local foundName = minetest.get_node(check_pos).name
		if foundName ~= frame_node_name then

			if force_chunk_load and foundName == "ignore" then
				-- area isn't loaded, force loading/emerge of check area
				minetest.get_voxel_manip():read_from_map(check_pos, check_pos)
				foundName = minetest.get_node(check_pos).name
				if DEBUG then minetest.chat_send_all("Forced loading of 'ignore' node at " .. minetest.pos_to_string(check_pos) .. ", got " .. foundName) end

				if foundName ~= frame_node_name then
					nodes_are_valid = false
					return true -- short-circuit the search
				end
			else
				nodes_are_valid = false
				return true -- short-circuit the search
			end
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

	nodes_are_valid   = true
	portal_is_ignited = true
	portal_definition.shape.apply_func_to_frame_nodes(anchorPos, orientation, check_frame_Func) -- check_frame_Func affects nodes_are_valid, portal_is_ignited

	if nodes_are_valid then
		-- a valid frame exists at anchorPos, check the wormhole is either ignited or unobstructed
		portal_definition.shape.apply_func_to_wormhole_nodes(anchorPos, orientation, check_wormhole_Func) -- check_wormhole_Func affects nodes_are_valid, portal_is_ignited
	end

	return nodes_are_valid, portal_is_ignited and nodes_are_valid -- returns two bools: portal was found, portal is lit
end

-- Checks pos, and if it's part of a portal or portal frame then three values are returned: anchorPos, orientation, is_ignited
-- where orientation is 0 or 90 (0 meaning a portal that faces north/south - i.e. obsidian running east/west)
local function is_within_portal_frame(portal_definition, pos)

	local width_minus_1  = portal_definition.shape.size.x - 1
	local height_minus_1 = portal_definition.shape.size.y - 1
	local depth_minus_1  = portal_definition.shape.size.z - 1

	for d = -depth_minus_1, depth_minus_1 do
		for w = -width_minus_1, width_minus_1 do
			for y = -height_minus_1, height_minus_1 do

				local testAnchorPos_x = {x = pos.x + w, y = pos.y + y, z = pos.z + d}
				local portal_found, portal_lit = is_portal_at_anchorPos(portal_definition, testAnchorPos_x, 0, true)

				if portal_found then
					return testAnchorPos_x, 0, portal_lit
				else
					-- try orthogonal orientation
					local testForAnchorPos_z = {x = pos.x + d, y = pos.y + y, z = pos.z + w}
					portal_found, portal_lit = is_portal_at_anchorPos(portal_definition, testForAnchorPos_z, 90, true)

					if portal_found then return testForAnchorPos_z, 90, portal_lit end
				end
			end
		end
	end
end


local function build_portal(portal_definition, anchorPos, orientation, destination_wormholePos)

	minetest.place_schematic(
		portal_definition.shape.get_schematicPos_from_anchorPos(anchorPos, orientation),
		portal_definition.schematic_filename,
		orientation,
		{ -- node replacements
			["default:obsidian"] = portal_definition.frame_node_name, 
			["nether:portal"]    = portal_definition.wormhole_node_name
		},
		true
	)
	-- set the param2 on wormhole nodes to ensure they are the right color
	local wormholeNode = {
		name = portal_definition.wormhole_node_name,
		param2 = get_colorfacedir_from_color_and_orientation(portal_definition.wormhole_node_color, orientation, portal_definition.shape.is_horizontal)
	}
	portal_definition.shape.apply_func_to_wormhole_nodes(
		anchorPos, 
		orientation,
		function(pos) minetest.swap_node(pos, wormholeNode) end
	)

	if DEBUG then minetest.chat_send_all("Placed " .. portal_definition.name .. " portal schematic at " ..  minetest.pos_to_string(portal_definition.shape.get_schematicPos_from_anchorPos(anchorPos, orientation)) .. ", orientation " .. orientation) end

	set_portal_metadata(portal_definition, anchorPos, orientation, destination_wormholePos)

	if portal_definition.on_created ~= nil then
		portal_definition.on_created(portal_definition, anchorPos, orientation)
	end
end


-- Sometimes after a portal is placed, concurrent mapgen routines overwrite it.
-- Make portals immortal for ~20 seconds after creation
local function remote_portal_checkup(elapsed, portal_definition, anchorPos, orientation, destination_wormholePos)

	if DEBUG then minetest.chat_send_all("portal checkup at " .. elapsed .. " seconds") end

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

	if elapsed < 10 then -- stop checking after ~20 seconds
		local delay = elapsed * 2
		minetest.after(delay, remote_portal_checkup, elapsed + delay, portal_definition, anchorPos, orientation, destination_wormholePos)
	end
end


-- Used to find or build the remote twin after a portal is opened.
-- If a portal is found that is already lit then it will be extinguished first and its destination_wormholePos updated,
-- this is to enforce that portals only link together in mutual pairs. It would be better for gameplay if I didn't apply
-- that restriction, but it would require maintaining an accurate list of every portal that links to a portal so they 
-- could be updated if the portal is destroyed. To keep the code simple I'm going to limit portals to only being the
-- destination of one lit portal at a time.
-- * suggested_wormholePos indicates where the portal should be built - note this not an anchorPos!
-- * suggested_orientation is the suggested schematic rotation to use if no useable portal is found at suggested_wormholePos:
--   0, 90, 180, 270 (0 meaning a portal that faces north/south - i.e. obsidian running east/west)
-- * destination_wormholePos is the wormholePos of the destination portal this one will be linked to.
--
-- Returns the final (anchorPos, orientation), as they may differ from the anchorPos and orientation that was
-- specified if an existing portal was already found there.
local function locate_or_build_portal(portal_definition, suggested_wormholePos, suggested_orientation, destination_wormholePos)

	if DEBUG then minetest.chat_send_all("locate_or_build_portal() called at wormholePos" .. minetest.pos_to_string(suggested_wormholePos) .. " with suggested orient " .. suggested_orientation .. ", targetted to " .. minetest.pos_to_string(destination_wormholePos)) end

	local result_anchorPos;
	local result_orientation;

	-- Searching for an existing portal at wormholePos seems better than at anchorPos, though isn't important
	local found_anchorPos, found_orientation, is_ignited = is_within_portal_frame(portal_definition, suggested_wormholePos) -- can be optimized - check for portal at exactly suggested_wormholePos first

	if found_anchorPos ~= nil then
		-- A portal is already here, we don't have to build one, though we may need to ignite it
		result_anchorPos   = found_anchorPos
		result_orientation = found_orientation

		if is_ignited then
			if DEBUG then minetest.chat_send_all("    Build unnecessary: already a lit portal at " ..  minetest.pos_to_string(found_anchorPos) .. ", orientation " .. result_orientation .. ". Extinguishing...") end
			extinguish_portal(found_anchorPos, portal_definition.frame_node_name, false)
		else
			if DEBUG then minetest.chat_send_all("    Build unnecessary: already an unlit portal at " ..  minetest.pos_to_string(found_anchorPos) .. ", orientation " .. result_orientation) end
		end
		-- ignite the portal
		set_portal_metadata_and_ignite(portal_definition, result_anchorPos, result_orientation, destination_wormholePos)

	else
		result_orientation = suggested_orientation
		result_anchorPos = portal_definition.shape.get_anchorPos_from_wormholePos(suggested_wormholePos, result_orientation)
		build_portal(portal_definition, result_anchorPos, result_orientation, destination_wormholePos)
		-- make sure portal isn't overwritten by ongoing generation/emerge
		minetest.after(2, remote_portal_checkup, 2, portal_definition, result_anchorPos, result_orientation, destination_wormholePos)
	end
	return result_anchorPos, result_orientation
end


-- invoked when a player attempts to turn obsidian nodes into an open portal
-- ignition_node_name is optional
local function ignite_portal(ignition_pos, ignition_node_name)

	if ignition_node_name == nil then ignition_node_name = minetest.get_node(ignition_pos).name end
	if DEBUG then minetest.chat_send_all("IGNITE the " .. ignition_node_name .. " at " .. minetest.pos_to_string(ignition_pos)) end

	-- find which sort of portals are made from the node that was clicked on
	local portal_definition_list = list_portal_definitions_for_frame_node(ignition_node_name)

	for _, portal_definition in ipairs(portal_definition_list) do
		local continue = false -- WRT the for loop, since lua has no continue keyword

		-- check it was a portal frame that the player is trying to ignite
		local anchorPos, orientation, is_ignited = is_within_portal_frame(portal_definition, ignition_pos)
		if anchorPos == nil then
			if DEBUG then minetest.chat_send_all("No " .. portal_definition.name .. " portal frame found at " .. minetest.pos_to_string(ignition_pos)) end
			continue = true -- no portal is here, but perhaps there's more than one portal type we need to search for
		elseif is_ignited then
			-- Found a portal, check its metadata and timer is healthy.
			local repair = false
			local meta = minetest.get_meta(ignition_pos)
			if meta ~= nil then
				local p1, p2, target = meta:get_string("p1"), meta:get_string("p2"), meta:get_string("target")
				if p1 == "" or p2 == "" or target == "" then
					-- metadata is missing, the portal frame node must have been removed without calling 
					-- on_destruct - perhaps by an ABM, then replaced - presumably by a player.
					-- allowing reigniting will repair the portal
					if DEBUG then minetest.chat_send_all("Broken portal detected, allowing reignition/repair") end
					repair = true
				else				
					if DEBUG then minetest.chat_send_all("This portal links to " .. meta:get_string("target") .. ". p1=" .. meta:get_string("p1") .. " p2=" .. meta:get_string("p2")) end
				
					-- Check the portal's timer is running, and fix if it's not.
					-- A portal's timer can stop running if the game is played without that portal type being 
					-- registered, e.g. enabling one of the example portals then later disabling it, then enabling it again.
					-- (if this is a frequent problem, then change the value of "run_at_every_load" in the lbm)
					local timer = minetest.get_node_timer(get_timerPos_from_p1_and_p2(minetest.string_to_pos(p1), minetest.string_to_pos(p2)))
					if timer ~= nil and timer:get_timeout() == 0 then
						if DEBUG then minetest.chat_send_all("Portal timer was not running: restarting the timer.") end
						timer:start(1) 
					end
				end
			end
			if not repair then return false end -- portal is already ignited (or timer has been fixed)
		end

		if continue == false then
			if DEBUG then minetest.chat_send_all("Found portal frame. Looked at " .. minetest.pos_to_string(ignition_pos) .. ", found at " .. minetest.pos_to_string(anchorPos) .. " orientation " .. orientation) end

			local destination_anchorPos, destination_orientation
			if portal_definition.is_within_realm(ignition_pos) then
				destination_anchorPos, destination_orientation = portal_definition.find_surface_anchorPos(anchorPos)
			else
				destination_anchorPos, destination_orientation = portal_definition.find_realm_anchorPos(anchorPos)
			end
			if DEBUG and destination_orientation == nil then minetest.chat_send_all("No destination_orientation given") end
			if destination_orientation == nil then destination_orientation = orientation end
			
			local destination_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(destination_anchorPos, destination_orientation)
			if DEBUG then minetest.chat_send_all("Destination set to " .. minetest.pos_to_string(destination_anchorPos)) end

			-- ignition/BURN_BABY_BURN
			set_portal_metadata_and_ignite(portal_definition, anchorPos, orientation, destination_wormholePos)

			if portal_definition.sounds.ignite ~= nil then
				local local_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(anchorPos, orientation)
				minetest.sound_play(portal_definition.sounds.ignite, {pos = local_wormholePos, max_hear_distance = 20})
			end

			if portal_definition.on_ignite ~= nil then
				portal_definition.on_ignite(portal_definition, anchorPos, orientation)
			end
			
			return true
		end
	end
end

-- invoked when a player is standing in a portal
local function ensure_remote_portal_then_teleport(player, portal_definition, local_anchorPos, local_orientation, destination_wormholePos)

	-- check player is still standing in a portal
	local playerPos = player:get_pos()
	if playerPos == nil then 
		return -- player quit the game while teleporting
	end 
	playerPos.y = playerPos.y + 0.1 -- Fix some glitches at -8000
	if minetest.get_node(playerPos).name ~= portal_definition.wormhole_node_name then
		return -- the player has moved out of the portal
	end

	-- debounce - check player is still standing in the *same* portal that called this function
	local meta = minetest.get_meta(playerPos)
	local local_p1, local_p2 = portal_definition.shape:get_p1_and_p2_from_anchorPos(local_anchorPos, local_orientation)
	local p1_at_playerPos = minetest.string_to_pos(meta:get_string("p1"))
	if p1_at_playerPos == nil or not vector.equals(local_p1, p1_at_playerPos) then
		if DEBUG then minetest.chat_send_all("the player already teleported from " .. minetest.pos_to_string(local_anchorPos) .. ", and is now standing in a different portal - " .. meta:get_string("p1")) end
		return -- the player already teleported, and is now standing in a different portal
	end

	local dest_wormhole_node = minetest.get_node_or_nil(destination_wormholePos)

	if dest_wormhole_node == nil then
		-- area not emerged yet, delay and retry
		if DEBUG then minetest.chat_send_all("ensure_remote_portal_then_teleport() could not find anything yet at " .. minetest.pos_to_string(destination_wormholePos)) end
		minetest.after(1, ensure_remote_portal_then_teleport, player, portal_definition, local_anchorPos, local_orientation, destination_wormholePos)
	else
		local local_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(local_anchorPos, local_orientation)

		if dest_wormhole_node.name == portal_definition.wormhole_node_name then
			-- portal exists

			local destination_orientation = get_orientation_from_colorfacedir(dest_wormhole_node.param2)
			local destination_anchorPos = portal_definition.shape.get_anchorPos_from_wormholePos(destination_wormholePos, destination_orientation)
			portal_definition.shape.disable_portal_trap(destination_anchorPos, destination_orientation)

			-- if the portal is already linked to a different portal then extinguish the other portal and 
			-- update the target portal to point back at this one.
			local remoteMeta = minetest.get_meta(destination_wormholePos)
			local remoteTarget = minetest.string_to_pos(remoteMeta:get_string("target"))
			if remoteTarget == nil then
				if DEBUG then minetest.chat_send_all("Failed to test whether target portal links back to this one") end
			elseif not vector.equals(remoteTarget, local_wormholePos) then
				if DEBUG then minetest.chat_send_all("Target portal is already linked, extinguishing then relighting to point back at this one") end
				extinguish_portal(remoteTarget, portal_definition.frame_node_name, false)
				set_portal_metadata_and_ignite(
					portal_definition,
					destination_anchorPos,
					destination_orientation,
					local_wormholePos
				)
			end

			if DEBUG then minetest.chat_send_all("Teleporting player from wormholePos" .. minetest.pos_to_string(local_wormholePos) .. " to wormholePos" .. minetest.pos_to_string(destination_wormholePos)) end

			-- play the teleport sound
			if portal_definition.sounds.teleport ~= nil then
				minetest.sound_play(portal_definition.sounds.teleport, {to_player = player.name})
			end

			-- rotate the player if the destination portal is a different orientation
			local rotation_angle = math.rad(destination_orientation - local_orientation)
			local offset = vector.subtract(playerPos, local_wormholePos) -- preserve player's position in the portal
			local rotated_offset = {x = math.cos(rotation_angle) * offset.x - math.sin(rotation_angle) * offset.z, y = offset.y, z = math.sin(rotation_angle) * offset.x + math.cos(rotation_angle) * offset.z}
			local new_playerPos = vector.add(destination_wormholePos, rotated_offset)
			player:set_pos(new_playerPos)
			player:set_look_horizontal(player:get_look_horizontal() + rotation_angle)

			if portal_definition.on_player_teleported ~= nil then
				portal_definition.on_player_teleported(portal_definition, player, playerPos, new_playerPos)
			end
		else
			-- no wormhole node at destination - destination portal either needs to be built or ignited.
			-- Note: A very rare edge-case that is difficult to set up: 
			--   If the destination portal is unlit and its frame shares a node with a lit portal that is linked to this 
			--   portal (but has not been travelled through, thus not linking this portal back to it), then igniting
			--   the destination portal will extinguish the portal it's touching, which will extinguish this portal
			--   which will leave a confused player.
			--   I don't think this is worth preventing, but I document it incase someone describes entering a portal 
			--   and then the portal turning off.
			if DEBUG then minetest.chat_send_all("ensure_remote_portal_then_teleport() saw " .. dest_wormhole_node.name .. " at " .. minetest.pos_to_string(destination_wormholePos) .. " rather than a wormhole. Calling locate_or_build_portal()") end

			local new_dest_anchorPos, new_dest_orientation = locate_or_build_portal(portal_definition, destination_wormholePos, local_orientation, local_wormholePos)
			local new_dest_wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(new_dest_anchorPos, new_dest_orientation)

			if not vector.equals(destination_wormholePos, new_dest_wormholePos) then
				-- Update the local portal's target to match where the existing remote portal was found
				destination_wormholePos = new_dest_wormholePos
				if DEBUG then minetest.chat_send_all("    updating target to where remote portal was found - " .. minetest.pos_to_string(destination_wormholePos)) end

				set_portal_metadata(
					portal_definition,
					local_anchorPos,
					local_orientation,
					destination_wormholePos
				)
			end
			minetest.after(0.1, ensure_remote_portal_then_teleport, player, portal_definition, local_anchorPos, local_orientation, destination_wormholePos)
		end
	end
end


-- run_wormhole() is invoked once per second per portal, handling teleportation and particle effects.
-- See get_timerPos_from_p1_and_p2() for an explanation of the timerPos location
function run_wormhole(timerPos, time_elapsed)

	local portal_definition -- will be used inside run_wormhole_node_func()

	local run_wormhole_node_func = function(pos)

		if math.random(2) == 1 then -- lets run only 3 particlespawners instead of 6 per portal
			minetest.add_particlespawner({
				amount = 16,
				time   = 2,
				minpos = {x = pos.x - 0.25, y = pos.y - 0.25, z = pos.z - 0.25},
				maxpos = {x = pos.x + 0.25, y = pos.y + 0.25, z = pos.z + 0.25},
				minvel = {x = -0.8, y = -0.8, z = -0.8},
				maxvel = {x = 0.8, y = 0.8, z = 0.8},
				minacc = {x = 0, y = 0, z = 0},
				maxacc = {x = 0, y = 0, z = 0},
				minexptime = 0.5,
				maxexptime = 1.7,
				minsize = 0.5 * portal_definition.particle_texture_scale,
				maxsize = 1.5 * portal_definition.particle_texture_scale,
				collisiondetection = false,
				texture   = portal_definition.particle_texture_colored,
				animation = portal_definition.particle_texture_animation,
				glow = 5
			})
		end

		for _, obj in ipairs(minetest.get_objects_inside_radius(pos, 1)) do
			if obj:is_player() then
				local meta = minetest.get_meta(pos)
				local destination_wormholePos = minetest.string_to_pos(meta:get_string("target"))
				local local_p1                = minetest.string_to_pos(meta:get_string("p1"))
				local local_p2                = minetest.string_to_pos(meta:get_string("p2"))
				if destination_wormholePos ~= nil and local_p1 ~= nil and local_p2 ~= nil then

					-- force emerge of target area
					minetest.get_voxel_manip():read_from_map(destination_wormholePos, destination_wormholePos) -- force load
					if minetest.get_node_or_nil(destination_wormholePos) == nil then
						minetest.emerge_area(vector.subtract(destination_wormholePos, 4), vector.add(destination_wormholePos, 4))
					end

					local local_anchorPos, local_orientation = portal_definition.shape.get_anchorPos_and_orientation_from_p1_and_p2(local_p1, local_p2)
					minetest.after(
						3, -- hopefully target area is emerged in 3 seconds
						function()
							ensure_remote_portal_then_teleport(
								obj,
								portal_definition,
								local_anchorPos,
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
	local meta = minetest.get_meta(timerPos)
	if meta ~= nil then
		p1          = minetest.string_to_pos(meta:get_string("p1"))
		p2          = minetest.string_to_pos(meta:get_string("p2"))
		portal_name = minetest.string_to_pos(meta:get_string("portal_type")) -- don't rely on this yet until you're sure everything works with old portals that don't have this set
	end
	if p1 ~= nil and p2 ~= nil then
		-- figure out the portal shape so we know where the wormhole nodes will be located
		local frame_node_name
		if portal_name ~= nil and nether.registered_portals[portal_name] ~= nil then
			portal_definition = nether.registered_portals[portal_name]
		else
			frame_node_name = minetest.get_node(timerPos).name -- timerPos should be a frame node if the shape is traditionalPortalShape
			portal_definition = get_portal_definition(frame_node_name, p1, p2)
		end

		if portal_definition == nil then
			minetest.log("error", "No portal with a \"" .. frame_node_name .. "\" frame is registered. run_wormhole" .. minetest.pos_to_string(timerPos) .. " was invoked but that location contains \"" .. frame_node_name .. "\"")
		else
			local anchorPos, orientation = portal_definition.shape.get_anchorPos_and_orientation_from_p1_and_p2(p1, p2)
			portal_definition.shape.apply_func_to_wormhole_nodes(anchorPos, orientation, run_wormhole_node_func)

			if portal_definition.on_run_wormhole ~= nil then 
				portal_definition.on_run_wormhole(portal_definition, anchorPos, orientation)
			end

			local wormholePos = portal_definition.shape.get_wormholePos_from_anchorPos(anchorPos, orientation)
			ambient_sound_play(portal_definition, wormholePos, meta)
		end
	end
end


local function create_book(item_name, inventory_description, inventory_image, title, author, page1_text, page2_text)

	local display_book = function(itemstack, user, pointed_thing)
		local player_name = user:get_player_name()

		minetest.sound_play("nether_book_open", {to_player = player_name, gain = 0.25})

		local formspec =
		"size[18,12.122]" ..

		"label[3.1,0.5;" .. minetest.formspec_escape(title) .. "]" ..
		"label[3.6,0.9;" .. author .. "]" ..

		"textarea[ 0.9,1.7;7.9,12.0;;" .. minetest.formspec_escape(page1_text) .. ";]" ..
		"textarea[10.1,0.8;7.9,12.9;;" .. minetest.formspec_escape(page2_text) .. ";]" ..

		"background[0,0;18,11;nether_book_background.png;true]"..
		"image_button_exit[17.3,0;0.8,0.8;nether_book_close.png;;]"

		minetest.show_formspec(player_name, item_name, formspec)
	end

	minetest.register_craftitem(item_name, {
		description     = inventory_description,
		inventory_image = inventory_image,
		groups          = {book = 1},
		on_use          = display_book
	})
end

-- Updates nether:book_of_portals
-- A book the player can read to lean how to build the different portals
local function create_book_of_portals()

	local page1_text
	local page2_text = ""

	-- tell the player how many portal types there are
	local portalCount = 0
	for _ in pairs(nether.registered_portals) do portalCount = portalCount + 1 end
	if portalCount == 1 then
		page1_text = S("In all my travels, and time spent in the Great Libraries, I have encountered no shortage of legends surrounding preternatural doorways said to open into other worlds, yet only one can I confirm as being more than merely a story.")
	else
		page1_text = S("In all my travels, and time spent in the Great Libraries, I have encountered no shortage of legends surrounding preternatural doorways said to open into other worlds, yet only @1 can I confirm as being more than merely stories.", portalCount)
	end

	-- tell the player how to ignite portals
	local ignition_item_description = "<error - ignition item not set>"
	if ignition_item_name ~= nil and minetest.registered_items[ignition_item_name] ~= nil then
		ignition_item_description = minetest.registered_items[ignition_item_name].description
	end
	page1_text = page1_text ..
		S("\n\nThe key to opening such a doorway is to strike the frame with a @1, at which point the very air inside begins to crackle and glow.\n\n\n", string.lower(ignition_item_description))

	-- Describe how to create each type of portal, or perhaps just give clues or flavor text,
	-- but ensure the Nether is always listed first on the first page so other definitions can
	-- refer to it (pairs() returns order based on a random hash).
	local i = 1
	if nether.registered_portals["nether_portal"] then
		page1_text = page1_text .. nether.registered_portals["nether_portal"].book_of_portals_pagetext .. "\n\n\n"
		i = i + 1
	end
	for portalName, portalDef in pairs(nether.registered_portals) do
		if portalName ~= "nether_portal" then
			if i <= portalCount / 2 then
				page1_text = page1_text .. portalDef.book_of_portals_pagetext .. "\n\n\n"
			else
				page2_text = page2_text .. portalDef.book_of_portals_pagetext .. "\n\n\n"
			end
			i = i + 1
		end
	end

	create_book(
		"nether:book_of_portals",
		S("Book of Portals"),
		"nether_book_of_portals.png",
		S("A treatise on Rifts and Portals"),
		"Riccard F. Burton", -- perhaps a Richard F. Burton of an alternate universe
		page1_text,
		page2_text
	)
end

-- This is hack to work around how place_schematic() never invalidates its cache.
-- A unique schematic filename is generated for each unique set of node replacements
function get_malleated_schematic_filename(portal_definition)

	local result

	if portal_definition.shape ~= nil and portal_definition.shape.schematic_filename ~= nil then
		
		local schematicFileName = portal_definition.shape.schematic_filename
		local uniqueId = portal_definition.frame_node_name .. " " .. portal_definition.wormhole_node_name

		if malleated_filenames[schematicFileName] == nil then malleated_filenames[schematicFileName] = {} end
		local filenamesForSchematic = malleated_filenames[schematicFileName]

		-- Split the schematic's filename into the path and filename
		local lastSlashPos,     _ = schematicFileName:find("/[^/]+$")   -- find the rightmost slash
		local lastBackslashPos, _ = schematicFileName:find("\\[^\\]+$") -- find the rightmost backslash
		if lastSlashPos     == nil then lastSlashPos = -1 end
		if lastBackslashPos ~= nil then lastSlashPos = math.max(lastSlashPos, lastBackslashPos) end
		local part_path     = schematicFileName:sub(0, math.max(0, lastSlashPos - 1))
		local part_filename = schematicFileName:sub(lastSlashPos + 1)

		if filenamesForSchematic[uniqueId] == nil then

			local malleationCount = 0
			for _ in pairs(filenamesForSchematic) do malleationCount = malleationCount + 1 end

			local malleatedFilename = part_path .. DIR_DELIM
			for i = 1, malleationCount do
				malleatedFilename = malleatedFilename .. '.' .. DIR_DELIM -- should work on both Linux and Windows
			end
			malleatedFilename = malleatedFilename .. part_filename
			filenamesForSchematic[uniqueId] = malleatedFilename
		end
		result = filenamesForSchematic[uniqueId]
	end

	return result
end


function register_frame_node(frame_node_name)

	-- copy the existing node definition
	local node = minetest.registered_nodes[frame_node_name]
	local extended_node_def = {}
	for key, value in pairs(node) do extended_node_def[key] = value end

	extended_node_def.replaced_by_portalapi = {} -- allows chaining or restoration of original functions, if necessary

	-- add portal portal functionality
	extended_node_def.replaced_by_portalapi.mesecons = extended_node_def.mesecons
	extended_node_def.mesecons = {effector = {
		action_on = function (pos, node)
			if DEBUG then minetest.chat_send_all("portal frame material: mesecons action ON") end
			ignite_portal(pos, node.name)
		end,
		action_off = function (pos, node)
			if DEBUG then minetest.chat_send_all("portal frame material: mesecons action OFF") end
			extinguish_portal(pos, node.name, false)
		end
	}}
	extended_node_def.replaced_by_portalapi.on_destruct = extended_node_def.on_destruct
	extended_node_def.on_destruct = function(pos)
		if DEBUG then minetest.chat_send_all("portal frame material: destruct") end
		extinguish_portal(pos, frame_node_name, true)
	end
	extended_node_def.replaced_by_portalapi.on_timer = extended_node_def.on_timer
	extended_node_def.on_timer = function(pos, elapsed)
		run_wormhole(pos, elapsed)
		return true
	end

	-- replace the node with the new extended definition
	minetest.register_node(":" .. frame_node_name, extended_node_def)
end

function unregister_frame_node(frame_node_name)

	-- copy the existing node definition
	local node = minetest.registered_nodes[frame_node_name]
	local restored_node_def = {}
	for key, value in pairs(node) do restored_node_def[key] = value end

	-- remove portal portal functionality
	restored_node_def.mesecons              = nil
	restored_node_def.on_destruct           = nil
	restored_node_def.on_timer              = nil
	restored_node_def.replaced_by_portalapi = nil

	if node.replaced_by_portalapi ~= nil then
		for key, value in pairs(node.replaced_by_portalapi) do restored_node_def[key] = value end
	end

	-- replace the node with the restored definition
	minetest.register_node(":" .. frame_node_name, restored_node_def)
end


-- check for mistakes people might make in custom shape definitions
function test_shapedef_is_valid(shape_defintion)
	assert(shape_defintion      ~= nil, "shape definition cannot be nil")
	assert(shape_defintion.name ~= nil, "shape definition must have a name")

	local result = true

	local origin = vector.new()
	local p1, p2 = shape_defintion:get_p1_and_p2_from_anchorPos(origin, 0)
	assert(vector.equals(shape_defintion.size, vector.add(vector.subtract(p2, p1), 1)), "p1 and p2 of shape definition '" .. shape_defintion.name .. "' don't match shapeDef.size")

	-- todo

	return result
end


-- check for mistakes people might make in portal definitions
function test_portaldef_is_valid(portal_definition)

	local result = test_shapedef_is_valid(portal_definition.shape)

	assert(portal_definition.wormhole_node_color >= 0 and portal_definition.wormhole_node_color < 8, "portaldef.wormhole_node_color must be between 0 and 7 (inclusive)")
	assert(portal_definition.is_within_realm      ~= nil, "portaldef.is_within_realm() must be implemented")
	assert(portal_definition.find_realm_anchorPos ~= nil, "portaldef.find_realm_anchorPos() must be implemented")
	-- todo

	return result
end


-- convert portals made with old ABM version of nether mod to use the timer instead
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
			p2 = minetest.string_to_pos(meta:get_string("p2"))
		end
		if p1 ~= nil and p2 ~= nil then
			local timerPos = get_timerPos_from_p1_and_p2(p1, p2)
			local timer = minetest.get_node_timer(timerPos)
			if timer ~= nil then
				timer:start(1)
				if DEBUG then minetest.chat_send_all("LBM started portal timer " .. minetest.pos_to_string(timerPos)) end
			elseif DEBUG then
				minetest.chat_send_all("get_node_timer" .. minetest.pos_to_string(timerPos) .. " returned null")
			end
		end
	end
})

minetest.register_on_mods_loaded(function()

	-- Make the Book of Portals available as treasure/loot
	if nether.PORTAL_BOOK_LOOT_WEIGHTING > 0 and minetest.registered_items["nether:book_of_portals"] ~= nil then

		-- All portals should be registered now.
		-- If the Nether is the only registered portal then lower the amount of these books
		-- found as treasure, since many players already know the shape of a Nether portal
		-- and what to build one out of, so would probably prefer other treasures.
		local portalCount = 0
		for _ in pairs(nether.registered_portals) do portalCount = portalCount + 1 end
		local weight_adjust = 1
		if portalCount <= 1 then weight_adjust = 0.5 end

		if minetest.get_modpath("loot") then
			loot.register_loot({
				weights = { generic = nether.PORTAL_BOOK_LOOT_WEIGHTING * 1000 * weight_adjust,
							books   = 100 },
				payload = { stack = "nether:book_of_portals" }
			})
		end

		if minetest.get_modpath("dungeon_loot") then
			dungeon_loot.register({name = "nether:book_of_portals", chance = nether.PORTAL_BOOK_LOOT_WEIGHTING * weight_adjust})
		end

		-- todo: add to Treasurer mod TRMP https://github.com/poikilos/trmp_minetest_game
		-- todo: add to help modpack       https://forum.minetest.net/viewtopic.php?t=15912
	end
end)


-- Portal API functions --
-- ==================== --


-- The fallback defaults for registered portaldef tables
local portaldef_default = {
	shape                        = PortalShape_Traditional,
	wormhole_node_name           = "nether:portal",
	wormhole_node_color          = 0,
	frame_node_name              = "default:obsidian",
	particle_texture             = "nether_particle.png",
	particle_texture_animation   = nil,
	particle_texture_scale       = 1,
	sounds = {
		ambient    = {name = "nether_portal_ambient",    gain = 0.6, length = 3},
		ignite     = {name = "nether_portal_ignite",     gain = 0.7},
		extinguish = {name = "nether_portal_extinguish", gain = 0.6},
		teleport   = {name = "nether_portal_teleport",   gain = 0.3}
	}
}


function nether.register_portal(name, portaldef)

	assert(name ~= nil,      "Unable to register portal: Name is nil")
	assert(portaldef ~= nil, "Unable to register portal ''" .. name .. "'': portaldef is nil")
	if nether.registered_portals[name] ~= nil then
		minetest.log("error", "Unable to register portal: '" .. name .. "' is already in use")
		return false;
	end

	portaldef.name     = name
	portaldef.mod_name = minetest.get_current_modname()

	-- use portaldef_default for any values missing from portaldef or portaldef.sounds
	if portaldef.sounds ~= nil then setmetatable(portaldef.sounds, {__index = portaldef_default.sounds}) end
	setmetatable(portaldef, {__index = portaldef_default})

	portaldef.schematic_filename = get_malleated_schematic_filename(portaldef)

	if portaldef.particle_color == nil then
		-- default the particle colours to be the same as the wormhole colour
		assert(portaldef.wormhole_node_color >= 0 and portaldef.wormhole_node_color < 8, "portaldef.wormhole_node_color must be between 0 and 7 (inclusive)")
		local rgb = nether.portals_palette[portaldef.wormhole_node_color]
		portaldef.particle_color = minetest.rgba(rgb.r, rgb.g, rgb.b)
	end
	if portaldef.particle_texture_colored == nil then
		-- Combine the particle texture with the particle color unless a particle_texture_colored was specified.
		if type(portaldef.particle_texture) == "table" and portaldef.particle_texture.animation ~= nil then
			portaldef.particle_texture_colored   = portaldef.particle_texture.name .. "^[colorize:" .. portaldef.particle_color .. ":alpha"
			portaldef.particle_texture_animation = portaldef.particle_texture.animation
			portaldef.particle_texture_scale     = portaldef.particle_texture.scale or 1
		else
			portaldef.particle_texture_colored   = portaldef.particle_texture .. "^[colorize:" .. portaldef.particle_color .. ":alpha"
		end
	end

	if portaldef.find_surface_anchorPos == nil then	-- default to using find_surface_target_y()
		portaldef.find_surface_anchorPos = function(pos)
			
			local destination_pos = {x = pos.x, y = 0, z = pos.z}
			local existing_portal_location, existing_portal_orientation = 
				nether.find_nearest_working_portal(name, destination_pos, 10, 0) -- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are outside the realm)
			if existing_portal_location ~= nil then
				return existing_portal_location, existing_portal_orientation
			else 
				destination_pos.y = nether.find_surface_target_y(destination_pos.x, destination_pos.z, name)
				return destination_pos
			end
		end
	end

	if test_portaldef_is_valid(portaldef) then

		-- check whether the portal definition clashes with anyone else's portal
		local p1, p2 = portaldef.shape:get_p1_and_p2_from_anchorPos(vector.new(), 0)
		local existing_portaldef = get_portal_definition(portaldef.frame_node_name, p1, p2)
		if existing_portaldef ~= nil then
			minetest.log("error", 
				portaldef.mod_name .." tried to register a portal '" .. portaldef.name .. "' made of " .. portaldef.frame_node_name .. 
				", but it is the same material and shape as the portal '" .. existing_portaldef.name .. "' already registered by " .. existing_portaldef.mod_name ..
				". Edit the values one of those mods uses in its call to nether.register_portal() if you wish to resolve this clash.")
		else
			-- the new portaldef is good
			nether.registered_portals[portaldef.name] = portaldef
			create_book_of_portals()

			if not is_frame_node[portaldef.frame_node_name] then
				-- add portal functions to the nodedef being used for the portal frame
				register_frame_node(portaldef.frame_node_name)
				is_frame_node[portaldef.frame_node_name] = true
			end

			return true
		end
	end

	return false
end

function nether.unregister_portal(name)

	assert(name ~= nil, "Cannot unregister portal: Name is nil")

	local portaldef = nether.registered_portals[name]
	local result = portaldef ~= nil

	if portaldef ~= nil then
		nether.registered_portals[name] = nil

		local portals_still_using_frame_node = list_portal_definitions_for_frame_node(portaldef.frame_node_name)
		if next(portals_still_using_frame_node) == nil then
			-- no portals are using this frame node any more
			unregister_frame_node(portaldef.frame_node_name)
			is_frame_node[portaldef.frame_node_name] = nil
		end
	end

	return result
end

function nether.register_portal_ignition_item(item_name, ignition_failure_sound)

	minetest.override_item(item_name, {
		on_place = function(stack, _, pt)
			local done = false
			if pt.under and is_frame_node[minetest.get_node(pt.under).name] then
				done = ignite_portal(pt.under)
				if done and not minetest.settings:get_bool("creative_mode") then
					stack:take_item()
				end
			end
			if not done and ignition_failure_sound ~= nil then
				minetest.sound_play(ignition_failure_sound, {pos = pt.under, max_hear_distance = 10})
			end


			return stack
		end,
	})

	ignition_item_name = item_name
end

-- use this when determining where to spawn a portal, to avoid overwriting player builds
-- It checks the area for any nodes that aren't ground or trees. 
-- (Water also fails this test, unless it is unemerged)
function nether.volume_is_natural(minp, maxp)
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
			if DEBUG and id == nil then minetest.chat_send_all("nil block at index " .. vi) end
			if id ~= c_air and id ~= c_ignore and id ~= nil then -- checked for common natural or not emerged
				local name = minetest.get_name_from_content_id(id)
				local nodedef = minetest.registered_nodes[name]
				if not nodedef.is_ground_content then
					-- trees are natural but not "ground content"
					local node_groups = nodedef.groups
					if node_groups == nil or (node_groups.tree == nil and node_groups.leaves == nil and node_groups.leafdecay == nil) then
						if DEBUG then minetest.chat_send_all("volume_is_natural() found unnatural node " .. name) end
						return false
					end
				end
			end
			vi = vi + 1
		end
	end
	end

	if DEBUG then minetest.chat_send_all("Volume is natural") end
	return true
end

-- Can be used when implementing custom find_surface_anchorPos() functions
-- portal_name is optional, providing it allows existing portals on the surface to be reused.
function nether.find_surface_target_y(target_x, target_z, portal_name)

	-- default to starting the search at -16 (probably underground) if we don't know the 
	-- surface, like paramat's original code from before get_spawn_level() was available:
	-- https://github.com/minetest-mods/nether/issues/5#issuecomment-506983676
	local start_y = -16

	-- try to spawn on surface first
	if minetest.get_spawn_level ~= nil then -- older versions of Minetest don't have this
		surface_level = minetest.get_spawn_level(target_x, target_z)
		if surface_level ~= nil then -- test this since get_spawn_level() can return nil over water or steep/high terrain	

			-- get_spawn_level() tends to err on the side of caution and spawns the player a 
			-- block higher than the ground level. The implementation is mapgen specific  
			-- and -2 seems to be the right correction for v6, v5, carpathian, valleys, and flat,
			-- but v7 only needs -1.
			-- Perhaps this was not always the case, and -2 may be too much in older versions 
			-- of minetest, but half-buried portals are perferable to floating ones, and they 
			-- will clear a suitable hole around themselves.
			if minetest.get_mapgen_setting("mg_name") == "v7" then 
				surface_level = surface_level - 1
			else
				surface_level = surface_level - 2
			end
			start_y = surface_level
		end
	end

	for y = start_y, start_y - 256, -16 do
		-- Check volume for non-natural nodes
		local minp = {x = target_x - 1, y = y - 1, z = target_z - 2}
		local maxp = {x = target_x + 2, y = y + 3, z = target_z + 2}
		if nether.volume_is_natural(minp, maxp) then
			return y
		elseif portal_name ~= nil and nether.registered_portals[portal_name] ~= nil then
			-- players have built here - don't grief.
			-- but reigniting existing portals in portal rooms is fine - desirable even.
			local anchorPos, orientation, is_ignited = is_within_portal_frame(nether.registered_portals[portal_name], {x = target_x, y = y, z = target_z})
			if anchorPos ~= nil then
				if DEBUG then minetest.chat_send_all("Volume_is_natural check failed, but a portal frame is here " .. minetest.pos_to_string(anchorPos) .. ", so this is still a good target y level") end
				return y
			end
		end
	end

	return start_y - 256 -- Fallback
end


-- Returns the anchorPos, orientation of the nearest portal, or nil.
-- A y_factor of 0 means y does not affect the distance_limit, a y_factor of 1 means y is included,
-- and a y_factor of 2 would squash the search-sphere by a factor of 2 on the y-axis, etc.
-- Pass a negative distance_limit to indicate no distance limit
function nether.find_nearest_working_portal(portal_name, anchorPos, distance_limit, y_factor)

	local portal_definition = nether.registered_portals[portal_name]
	assert(portal_definition ~= nil, "find_nearest_working_portal() called with portal_name '" .. portal_name .. "', but no portal is registered with that name.")
	
	local contenders = list_closest_portals(portal_definition, anchorPos, distance_limit, y_factor) 

	-- sort by distance
	local dist_list = {}
	for dist, _ in pairs(contenders) do table.insert(dist_list, dist) end
	table.sort(dist_list)

	for _, dist in ipairs(dist_list) do 
		local portal_info = contenders[dist]
		if DEBUG then minetest.chat_send_all("checking portal from mod_storage at " .. minetest.pos_to_string(portal_info.anchorPos) .. " orientation " .. portal_info.orientation) end

		-- the mod_storage list of portals is unreliable - e.g. it won't know if inactive portals have been 
		-- destroyed, so check the portal is still there
		local portalFound, portalActive = is_portal_at_anchorPos(portal_definition, portal_info.anchorPos, portal_info.orientation, true)

		if portalFound then
			return portal_info.anchorPos, portal_info.orientation
		else
			if DEBUG then minetest.chat_send_all("Portal wasn't found, removing portal from mod_storage at " .. minetest.pos_to_string(portal_info.anchorPos) .. " orientation " .. portal_info.orientation) end
			-- The portal at that location must have been destroyed
			remove_portal_location_info(portal_name, portal_info.anchorPos)
		end
	end
	return nil
end
