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

local S = nether.get_translator

-- Portal/wormhole nodes

nether.register_wormhole_node("nether:portal", {
	description = S("Nether Portal"),
	post_effect_color = {
		-- post_effect_color can't be changed dynamically in Minetest like the portal colour is.
		-- If you need a different post_effect_color then use register_wormhole_node to create
		-- another wormhole node and set it as the wormhole_node_name in your portaldef.
		-- Hopefully this colour is close enough to magenta to work with the traditional magenta
		-- portals, close enough to red to work for a red portal, and also close enough to red to
		-- work with blue & cyan portals - since blue portals are sometimes portrayed as being red
		-- from the opposite side / from the inside.
		a = 160, r = 128, g = 0, b = 80
	}
})

local portal_animation2 = {
	name = "nether_portal_alt.png",
	animation = {
		type = "vertical_frames",
		aspect_w = 16,
		aspect_h = 16,
		length = 0.5,
	},
}

nether.register_wormhole_node("nether:portal_alt", {
	description = S("Portal"),
	tiles = {
		"nether_transparent.png",
		"nether_transparent.png",
		"nether_transparent.png",
		"nether_transparent.png",
		portal_animation2,
		portal_animation2
	},
	post_effect_color = {
		-- hopefully blue enough to work with blue portals, and green enough to
		-- work with cyan portals.
		a = 120, r = 0, g = 128, b = 188
	}
})


-- Nether nodes

minetest.register_node("nether:rack", {
	description = S("Netherrack"),
	tiles = {"nether_rack.png"},
	is_ground_content = true,
	groups = {cracky = 3, level = 2},
	sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("nether:sand", {
	description = S("Nethersand"),
	tiles = {"nether_sand.png"},
	is_ground_content = true,
	groups = {crumbly = 3, level = 2, falling_node = 1},
	sounds = default.node_sound_gravel_defaults({
		footstep = {name = "default_gravel_footstep", gain = 0.45},
	}),
})

minetest.register_node("nether:glowstone", {
	description = S("Glowstone"),
	tiles = {"nether_glowstone.png"},
	is_ground_content = true,
	light_source = 14,
	paramtype = "light",
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	sounds = default.node_sound_glass_defaults(),
})

minetest.register_node("nether:brick", {
	description = S("Nether Brick"),
	tiles = {"nether_brick.png"},
	is_ground_content = false,
	groups = {cracky = 2, level = 2},
	sounds = default.node_sound_stone_defaults(),
})

local fence_texture =
	"default_fence_overlay.png^nether_brick.png^default_fence_overlay.png^[makealpha:255,126,126"

minetest.register_node("nether:fence_nether_brick", {
	description = S("Nether Brick Fence"),
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
	S("Nether Stair"),
	S("Nether Slab"),
	default.node_sound_stone_defaults()
)

stairs.register_stair(
	"netherrack",
	"nether:rack",
	{cracky = 2, level = 2},
	{"nether_rack.png"},
	S("Netherrack stair"),
	default.node_sound_stone_defaults()
)

-- StairsPlus

if minetest.get_modpath("moreblocks") then
	stairsplus:register_all(
		"nether", "brick", "nether:brick", {
			description = S("Nether Brick"),
			groups = {cracky = 2, level = 2},
			tiles = {"nether_brick.png"},
			sounds = default.node_sound_stone_defaults(),
	})
end


-- Fumaroles (Chimney's)

local function fumarole_startTimer(pos, timeout_factor)

	if timeout_factor == nil then timeout_factor = 1 end
	local next_timeout = (math.random(50, 900) / 10) * timeout_factor

	minetest.get_meta(pos):set_float("expected_timeout", next_timeout)
	minetest.get_node_timer(pos):start(next_timeout)
end

-- Create an LBM to start fumarole node timers
minetest.register_lbm({
	label = "Start fumarole smoke",
	name  = "nether:start_fumarole",
	nodenames = {"nether:fumarole"},
	run_at_every_load = true,
	action = function(pos, node)
		local node_above = minetest.get_node({x = pos.x, y = pos.y + 1, z = pos.z})
		if node_above.name == "air" then --and node.param2 % 4 == 0 then
			fumarole_startTimer(pos)
		end
	end
})

local function set_fire(pos, extinguish)
	local posBelow  = {x = pos.x, y = pos.y - 1, z = pos.z}

	if extinguish then
		if minetest.get_node(pos).name      == "fire:permanent_flame" then minetest.set_node(pos,      {name="air"}) end
		if minetest.get_node(posBelow).name == "fire:permanent_flame" then minetest.set_node(posBelow, {name="air"}) end

	elseif minetest.get_node(posBelow).name == "air" then
		minetest.set_node(posBelow, {name="fire:permanent_flame"})
	elseif minetest.get_node(pos).name == "air" then
		minetest.set_node(pos, {name="fire:permanent_flame"})
	end
end

local function fumarole_onTimer(pos, elapsed)

	local expected_timeout = minetest.get_meta(pos):get_float("expected_timeout")
	if elapsed > expected_timeout + 10 then
		-- The timer didn't fire when it was supposed to, so the chunk was probably inactive and has
		-- just been approached again, meaning *every* fumarole's on_timer is about to go off.
		-- Skip this event and restart the clock for a future random interval.
		fumarole_startTimer(pos, 1)
		return false
	end

	-- Fumaroles in the Nether can catch fire.
	-- (if taken to the surface and used as cottage chimneys, they don't catch fire)
	local inNether = pos.y <= nether.DEPTH and pos.y >= nether.DEPTH_FLOOR
	local canCatchFire = inNether and minetest.registered_nodes["fire:permanent_flame"] ~= nil
	local smoke_offset   = 0
	local timeout_factor = 1
	local smoke_time_adj = 1

	local posAbove = {x = pos.x, y = pos.y + 1, z = pos.z}
	local extinguish = minetest.get_node(posAbove).name ~= "air"

	if extinguish or (canCatchFire and math.floor(elapsed) % 7 == 0) then

		if not extinguish then
			-- fumarole gasses are igniting
			smoke_offset   = 1
			timeout_factor = 0.22 -- reduce burning time
		end

		set_fire(posAbove, extinguish)
		set_fire({x = pos.x + 1, y = pos.y + 1, z = pos.z},     extinguish)
		set_fire({x = pos.x - 1, y = pos.y + 1, z = pos.z},     extinguish)
		set_fire({x = pos.x,     y = pos.y + 1, z = pos.z + 1}, extinguish)
		set_fire({x = pos.x,     y = pos.y + 1, z = pos.z - 1}, extinguish)

	elseif inNether then

		if math.floor(elapsed) % 3 == 1 then
			-- throw up some embers / lava splash
			local embers_particlespawn_def = {
				amount = 6,
				time = 0.1,
				minpos = {x=pos.x - 0.1, y=pos.y + 0.0, z=pos.z - 0.1},
				maxpos = {x=pos.x + 0.1, y=pos.y + 0.2, z=pos.z + 0.1},
				minvel = {x = -.5, y = 4.5, z = -.5},
				maxvel = {x =  .5, y = 7,   z =  .5},
				minacc = {x = 0, y = -10, z = 0},
				maxacc = {x = 0, y = -10, z = 0},
				minexptime = 1.4,
				maxexptime = 1.4,
				minsize = .2,
				maxsize = .8,
				texture = "^[colorize:#A00:255",
				glow = 8
			}
			minetest.add_particlespawner(embers_particlespawn_def)
			embers_particlespawn_def.texture = "^[colorize:#A50:255"
			embers_particlespawn_def.maxvel.y = 3
			embers_particlespawn_def.glow = 12
			minetest.add_particlespawner(embers_particlespawn_def)

		else
			-- gas noises
			minetest.sound_play("nether_fumarole", {
				pos = pos,
				max_hear_distance = 60,
				gain = 0.24,
				pitch = math.random(35, 95) / 100
			})
		end

	else
		-- we're not in the Nether, so can afford to be a bit more smokey
		timeout_factor = 0.4
		smoke_time_adj = 1.3
	end

	-- let out some smoke
	minetest.add_particlespawner({
		amount = 12 * smoke_time_adj,
		time = math.random(40, 60) / 10 * smoke_time_adj,
		minpos = {x=pos.x - 0.2, y=pos.y + smoke_offset, z=pos.z - 0.2},
		maxpos = {x=pos.x + 0.2, y=pos.y + smoke_offset, z=pos.z + 0.2},
		minvel = {x=0, y=0.7, z=-0},
		maxvel = {x=0, y=0.8, z=-0},
		minacc = {x=0.0,y=0.0,z=-0},
		maxacc = {x=0.0,y=0.1,z=-0},
		minexptime = 5,
		maxexptime = 5.5,
		minsize = 1.5,
		maxsize = 7,
		texture = "nether_smoke_puff.png",
	})

	fumarole_startTimer(pos, timeout_factor)
	return false
end


minetest.register_node("nether:fumarole", {
	description="Fumarolic Chimney",
	tiles = {"nether_rack.png"},
	on_timer = fumarole_onTimer,
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		fumarole_onTimer(pos, 1)
		return false
	end,
	is_ground_content = true,
	groups = {cracky = 3, level = 2, fumarole=1},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5000, -0.5000, -0.5000, -0.2500, 0.5000, 0.5000},
			{-0.5000, -0.5000, -0.5000, 0.5000, 0.5000, -0.2500},
			{-0.5000, -0.5000, 0.2500, 0.5000, 0.5000, 0.5000},
			{0.2500, -0.5000, -0.5000, 0.5000, 0.5000, 0.5000}
		}
	},
	selection_box = {type = 'fixed', fixed = {-.5, -.5, -.5, .5, .5, .5}}
})

minetest.register_node("nether:fumarole_slab", {
	description="Fumarolic Chimney Slab",
	tiles = {"nether_rack.png"},
	is_ground_content = true,
	on_timer = fumarole_onTimer,
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		fumarole_onTimer(pos, 1)
		return false
	end,
	groups = {cracky = 3, level = 2, fumarole=1},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5000, -0.5000, -0.5000, -0.2500, 0.000, 0.5000},
			{-0.5000, -0.5000, -0.5000, 0.5000, 0.000, -0.2500},
			{-0.5000, -0.5000, 0.2500, 0.5000, 0.000, 0.5000},
			{0.2500, -0.5000, -0.5000, 0.5000, 0.000, 0.5000}
		}
	},
	selection_box = {type = 'fixed', fixed = {-.5, -.5, -.5, .5, 0, .5}},
	collision_box = {type = 'fixed', fixed = {-.5, -.5, -.5, .5, 0, .5}}
})

minetest.register_node("nether:fumarole_corner", {
	description="Fumarolic Chimney Corner",
	tiles = {"nether_rack.png"},
	is_ground_content = true,
	groups = {cracky = 3, level = 2, fumarole=1},
	paramtype = "light",
	paramtype2 = "facedir",
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.2500, -0.5000, 0.5000, 0.000, 0.5000, 0.000},
			{-0.5000, -0.5000, 0.2500, 0.000, 0.5000, 0.000},
			{-0.5000, -0.5000, 0.2500, 0.000, 0.000, -0.5000},
			{0.000, -0.5000, -0.5000, 0.5000, 0.000, 0.5000}
		}
	},
	selection_box = {
		type = 'fixed',
		fixed = {
			{-.5, -.5, -.5, .5, 0, .5},
			{0, 0, .5, -.5, .5, 0},
		}
	}

})

-- nether:airlike_darkness is an air node through which light does not propagate.
-- Use of it should be avoided when possible as it has the appearance of a lighting bug.
-- Fumarole decorations use it to stop the propagation of light from the lava below,
-- since engine limitations mean any mesh or nodebox node will light up if it has lava
-- below it.
local airlike_darkness = {}
for k,v in pairs(minetest.registered_nodes["air"]) do airlike_darkness[k] = v end
airlike_darkness.paramtype = "none"
minetest.register_node("nether:airlike_darkness", airlike_darkness)


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


