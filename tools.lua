--[[

  Copyright (C) 2020 lortas

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

minetest.register_tool("nether:pick_nether", {
	description = S("Nether Pickaxe\nWell suited for mining netherrack"),
	_doc_items_longdesc = S("Uniquely suited for mining netherrack, with minimal wear when doing so. Blunts quickly on other materials."),
	inventory_image = "nether_tool_netherpick.png",
	tool_capabilities = {
		full_punch_interval = 0.8,
		max_drop_level=3,
		groupcaps={
			cracky = {times={[1]=1.90, [2]=0.9, [3]=0.3}, uses=35, maxlevel=2},
		},
		damage_groups = {fleshy=4},
	},
	sound = {breaks = "default_tool_breaks"},
	groups = {pickaxe = 1},

	after_use = function(itemstack, user, node, digparams)
		local wearDivisor = 1
		local nodeDef = minetest.registered_nodes[node.name]
		if nodeDef ~= nil and nodeDef.groups ~= nil then
			-- The nether pick hardly wears out when mining netherrack
			local workable = nodeDef.groups.workable_with_nether_tools or 0
			wearDivisor =  1 + (3 * workable) -- 10 for netherrack, 1 otherwise. Making it able to mine 350 netherrack nodes, instead of 35.
		end

		local wear = math.floor(digparams.wear / wearDivisor)
		itemstack:add_wear(wear)  -- apply the adjusted wear as usual
		return itemstack
	end
})

minetest.register_tool("nether:shovel_nether", {
	description = S("Nether Shovel"),
	inventory_image = "nether_tool_nethershovel.png",
	wield_image = "nether_tool_nethershovel.png^[transformR90",
	tool_capabilities = {
		full_punch_interval = 1.0,
		max_drop_level=3,
		groupcaps={
			crumbly = {times={[1]=1.0, [2]=0.4, [3]=0.25}, uses=35, maxlevel=3},
		},
		damage_groups = {fleshy=4},
	},
	sound = {breaks = "default_tool_breaks"},
	groups = {shovel = 1}
})

minetest.register_tool("nether:axe_nether", {
	description = S("Nether Axe"),
	inventory_image = "nether_tool_netheraxe.png",
	tool_capabilities = {
		full_punch_interval = 0.8,
		max_drop_level=1,
		groupcaps={
			choppy={times={[1]=1.9, [2]=0.7, [3]=0.4}, uses=35, maxlevel=3},
		},
		damage_groups = {fleshy=7},
	},
	sound = {breaks = "default_tool_breaks"},
	groups = {axe = 1}
})

minetest.register_tool("nether:sword_nether", {
	description = S("Nether Sword"),
	inventory_image = "nether_tool_nethersword.png",
	tool_capabilities = {
		full_punch_interval = 0.7,
		max_drop_level=1,
		groupcaps={
			snappy={times={[1]=1.5, [2]=0.6, [3]=0.2}, uses=45, maxlevel=3},
		},
		damage_groups = {fleshy=10},
	},
	sound = {breaks = "default_tool_breaks"},
	groups = {sword = 1}
})

minetest.register_craftitem("nether:nether_ingot", {
	description = S("Nether Ingot"),
	inventory_image = "nether_nether_ingot.png"
})
minetest.register_craftitem("nether:nether_lump", {
	description = S("Nether Lump"),
	inventory_image = "nether_nether_lump.png",
})

minetest.register_craft({
	type = "cooking",
	output = "nether:nether_ingot",
	recipe = "nether:nether_lump",
	cooktime = 30,
})
minetest.register_craft({
	output = "nether:nether_lump",
	recipe = {
		{"nether:brick_compressed","nether:brick_compressed","nether:brick_compressed"},
		{"nether:brick_compressed","nether:brick_compressed","nether:brick_compressed"},
		{"nether:brick_compressed","nether:brick_compressed","nether:brick_compressed"},
	}
})

minetest.register_craft({
	output = "nether:pick_nether",
	recipe = {
		{"nether:nether_ingot","nether:nether_ingot","nether:nether_ingot"},
		{"", "group:stick", ""},
		{"", "group:stick", ""}
	}
})
minetest.register_craft({
	output = "nether:shovel_nether",
	recipe = {
		{"nether:nether_ingot"},
		{"group:stick"},
		{"group:stick"}
	}
})
minetest.register_craft({
	output = "nether:axe_nether",
	recipe = {
		{"nether:nether_ingot","nether:nether_ingot"},
		{"nether:nether_ingot","group:stick"},
		{"","group:stick"}
	}
})
minetest.register_craft({
	output = "nether:sword_nether",
	recipe = {
		{"nether:nether_ingot"},
		{"nether:nether_ingot"},
		{"group:stick"}
	}
})




--===========================--
--== Nether Staff of Light ==--
--===========================--

nether.lightstaff_recipes = {
	["nether:rack"]                 = "nether:glowstone",
	["nether:brick"]                = "nether:glowstone",
	["nether:brick_cracked"]        = "nether:glowstone",
	["nether:brick_compressed"]     = "nether:glowstone",
	["stairs:slab_netherrack"]      = "nether:glowstone",
	["nether:rack_deep"]            = "nether:glowstone_deep",
	["nether:brick_deep"]           = "nether:glowstone_deep",
	["stairs:slab_netherrack_deep"] = "nether:glowstone_deep"
}
nether.lightstaff_range    = 100
nether.lightstaff_velocity = 60
nether.lightstaff_gravity  = 0  -- using 0 instead of 10 because projectile arcs look less magical - magic isn't affected by gravity ;) (but set this to 10 if you're making a crossbow etc.)
nether.lightstaff_uses     = 60 -- number of times the Eternal Lightstaff can be used before wearing out
nether.lightstaff_duration = 40 -- lifespan of glowstone created by the termporay Lightstaff

-- 'serverLag' is a rough amount to reduce the projected impact-time the server must wait before initiating the
-- impact events (i.e. node changing to glowstone with explosion particle effect).
-- In tests using https://github.com/jagt/clumsy to simulate network lag I've found this value to not noticeably
-- matter. A large network lag is noticeable in the time between clicking fire and when the shooting-particleEffect
-- begins, as well as the time between when the impact sound/particleEffect start and when the netherrack turns
-- into glowstone. The synchronization that 'serverLag' adjusts seems to already tolerate network lag well enough (at
-- least when lag is consistent, as I have not simulated random lag)
local serverLag = 0.05 -- in seconds. Larger values makes impact events more premature/early.

-- returns a pointed_thing, or nil if no solid node intersected the ray
local function raycastForSolidNode(rayStartPos, rayEndPos)

	local raycast = minetest.raycast(
		rayStartPos,
		rayEndPos,
		false, -- objects - if false, only nodes will be returned. Default is `true`
		true   -- liquids - if false, liquid nodes won't be returned. Default is `false`
	)
	local next_pointed = raycast:next()
	while next_pointed do
		local under_node = minetest.get_node(next_pointed.under)
		local under_def = minetest.registered_nodes[under_node.name]

		if (under_def and not under_def.buildable_to) or not under_def then
			return next_pointed
		end

		next_pointed  = raycast:next(next_pointed)
	end
	return nil
end

-- Turns a node into a light source
-- `lightDuration` 0 is considered permanent, lightDuration is in seconds
-- returns true if a node is transmogrified into a glowstone
local function light_node(pos, playerName, lightDuration)

	local result = false
	if minetest.is_protected(pos, playerName) then
		minetest.record_protection_violation(pos, playerName)
		return false
	end

	local oldNode = minetest.get_node(pos)
	local litNodeName = nether.lightstaff_recipes[oldNode.name]

	if litNodeName ~= nil then
		result = nether.magicallyTransmogrify_node(
			pos,
			playerName,
			{name=litNodeName},
			{name = "nether_rack_destroy", gain = 0.8},
			lightDuration == 0 -- isPermanent
		)

		if lightDuration > 0 then
			minetest.after(lightDuration,
				function()
					-- Restore the node to its original type.
					--
					-- If the server crashes or shuts down before this is invoked, the node
					-- will remain in its transmogrified state. These could be cleaned up
					-- with an LBM, but I don't think that's necessary: if this functionality
					-- is only being used for the Nether Lightstaff then I don't think it
					-- matters if there's occasionally an extra glowstone left in the
					-- netherrack.
					nether.magicallyTransmogrify_node(pos, playerName)
				end
			)
		end
	end
	return result
end

-- a lightDuration of 0 is considered permanent, lightDuration is in seconds
-- returns true if a node is transmogrified into a glowstone
local function lightstaff_on_use(user, boltColorString, lightDuration)

	if not user then return false end
	local playerName    = user:get_player_name()
	local playerlookDir = user:get_look_dir()
	local playerPos     = user:get_pos()
	local playerEyePos  = vector.add(playerPos, {x = 0, y = 1.5, z = 0}) -- not always the cameraPos, e.g. 3rd person mode.
	local target        = vector.add(playerEyePos, vector.multiply(playerlookDir, nether.lightstaff_range))

	local targetHitPos  = nil
	local targetNodePos = nil
	local target_pointed = raycastForSolidNode(playerEyePos, target)
	if target_pointed then
		targetNodePos = target_pointed.under
		targetHitPos = vector.divide(vector.add(target_pointed.under, target_pointed.above), 2)
	end

	local wieldOffset = {x= 0.5, y = -0.2, z= 0.8}
	local lookRotation =  ({x = -user:get_look_vertical(), y = user:get_look_horizontal(), z = 0})
	local wieldPos = vector.add(playerEyePos, vector.rotate(wieldOffset, lookRotation))
	local aimPos = targetHitPos or target
	local distance = math.abs(vector.length(vector.subtract(aimPos, wieldPos)))
	local flightTime = distance / nether.lightstaff_velocity
	local dropDistance = nether.lightstaff_gravity * 0.5 * (flightTime * flightTime)
	aimPos.y = aimPos.y + dropDistance
	local boltDir = vector.normalize(vector.subtract(aimPos, wieldPos))

	minetest.sound_play("nether_lightstaff", {to_player = playerName, gain = 0.8}, true)

	-- animate a "magic bolt" from wieldPos to aimPos
	local particleSpawnDef = {
		amount = 20,
		time = 0.4,
		minpos = vector.add(wieldPos, -0.13),
		maxpos = vector.add(wieldPos,  0.13),
		minvel = vector.multiply(boltDir, nether.lightstaff_velocity - 0.3),
		maxvel = vector.multiply(boltDir, nether.lightstaff_velocity + 0.3),
		minacc = {x=0, y=-nether.lightstaff_gravity, z=0},
		maxacc = {x=0, y=-nether.lightstaff_gravity, z=0},
		minexptime = 1,
		maxexptime = 2,
		minsize = 4,
		maxsize = 5,
		collisiondetection = true,
		collision_removal = true,
		texture = "nether_particle_anim3.png",
		animation = { type = "vertical_frames", aspect_w = 7, aspect_h = 7, length = 0.8 },
		glow = 15
	}
	minetest.add_particlespawner(particleSpawnDef)
	particleSpawnDef.texture = "nether_particle_anim3.png^[colorize:" .. boltColorString .. ":alpha"
	particleSpawnDef.amount  = 12
	particleSpawnDef.time    = 0.2
	particleSpawnDef.minsize = 6
	particleSpawnDef.maxsize = 7
	particleSpawnDef.minpos  = vector.add(wieldPos, -0.35)
	particleSpawnDef.maxpos  = vector.add(wieldPos,  0.35)
	minetest.add_particlespawner(particleSpawnDef)

	local result = false
	if targetNodePos then
		-- delay the impact until roughly when the particle effects will have reached the target
		minetest.after(
			math.max(0, (distance / nether.lightstaff_velocity) - serverLag),
			function()
				light_node(targetNodePos, playerName, lightDuration)
			end
		)

		if lightDuration ~= 0 then
			-- we don't need to care whether the transmogrify will be successful
			result = true
		else
			-- check whether the transmogrify will be successful
			local targetNode = minetest.get_node(targetNodePos)
			result = nether.lightstaff_recipes[targetNode.name] ~= nil
		end
	end
	return result
end

-- Inspired by FaceDeer's torch crossbow and Xanthin's Staff of Light
minetest.register_tool("nether:lightstaff", {
	description = S("Nether staff of Light\nTemporarily transforms the netherrack into glowstone"),
	inventory_image = "nether_lightstaff.png",
	wield_image     = "nether_lightstaff.png",
	light_source = 11, -- used by wielded_light mod etc.
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		lightstaff_on_use(user, "#F70", nether.lightstaff_duration)
	end
})

minetest.register_tool("nether:lightstaff_eternal", {
	description = S("Nether staff of Eternal Light\nCreates glowstone from netherrack"),
	inventory_image = "nether_lightstaff.png^[colorize:#55F:90",
	wield_image     = "nether_lightstaff.png^[colorize:#55F:90",
	light_source = 11, -- used by wielded_light mod etc.
	sound = {breaks = "default_tool_breaks"},
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if lightstaff_on_use(user, "#23F", 0) then -- was "#8088FF" or "#13F"
			-- The staff of Eternal Light wears out, to limit how much
			-- a player can alter the nether with it.
			itemstack:add_wear(65535 / (nether.lightstaff_uses - 1))
		end
		return itemstack
	end
})
