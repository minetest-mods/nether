
local S = minetest.get_translator("nether")


minetest.register_node("nether:rack_with_gold", {
	description = S("Nether Gold"),
	tiles = {"nether_rack.png^default_mineral_gold.png"},
	is_ground_content = true,
	groups = {cracky = 3, level = 2, workable_with_nether_tools = 3},
	drop = "default:gold_lump",
	sounds = default.node_sound_stone_defaults()
})

minetest.register_node("nether:rack_deep_with_mese", {
	description = S("Nether Mese"),
	tiles = {"nether_rack_deep.png^default_mineral_mese.png"},
	is_ground_content = true,
	groups = {cracky = 3, level = 2, workable_with_nether_tools = 3},
	drop = "default:mese_crystal_fragment 4",
	sounds = default.node_sound_stone_defaults(),
})


local ore_ceiling = nether.DEPTH_CEILING - 128
local ore_floor   = nether.DEPTH_FLOOR   + 128


minetest.register_ore({
	ore_type       = "scatter",
	ore            = "nether:rack_with_gold",
	wherein        = "nether:rack",
	clust_scarcity = 15 * 15 * 15,
	clust_num_ores = 7,
	clust_size     = 5,
	y_max          = ore_ceiling,
	y_min          = ore_floor
})

minetest.register_ore({
	ore_type       = "scatter",
	ore            = "nether:rack_deep_with_mese",
	wherein        = "nether:rack_deep",
	clust_scarcity = 15 * 15 * 15,
	clust_num_ores = 7,
	clust_size     = 5,
	y_max          = ore_ceiling,
	y_min          = ore_floor,
})
