local S = minetest.get_translator("nether")

technic.register_recipe_type("compressing", { description = S("Compressing") })

function register_compressor_recipe(data)
	data.time = data.time or 4
	technic.register_recipe("compressing", data)
end

local recipes = {
	{"nether:rack",                    "nether:brick",},
	{"nether:rack_deep",               "nether:brick_deep"},
	{"nether:brick 9",                 "nether:brick_compressed", 12},
	{"nether:brick_compressed 9",      "nether:nether_lump", 12}

}
-- clear craft recipe
-- But allow brick blocks to be crafted like the other bricks from Minetest Game

minetest.clear_craft({
	recipe = {
		{"nether:brick","nether:brick","nether:brick"},
		{"nether:brick","nether:brick","nether:brick"},
		{"nether:brick","nether:brick","nether:brick"},
	}
})

minetest.clear_craft({
	recipe = {
		{"nether:brick_compressed","nether:brick_compressed","nether:brick_compressed"},
		{"nether:brick_compressed","nether:brick_compressed","nether:brick_compressed"},
		{"nether:brick_compressed","nether:brick_compressed","nether:brick_compressed"},
	}
})

for _, data in pairs(recipes) do
	register_compressor_recipe({input = {data[1]}, output = data[2], time = data[3]})
end


