extends RefCounted
## Static content DB: raw resources + craftable recipes.
## Reached via preload(...) + static funcs ONLY — headless --script self-tests
## never instantiate autoloads, so this must not be an autoload global.

const RESOURCES: Array = ["shell", "driftwood", "seaglass", "pearl"]

const RESOURCE_NAMES: Dictionary = {
	"shell": "Shell",
	"driftwood": "Driftwood",
	"seaglass": "Sea Glass",
	"pearl": "Pearl",
}

const RECIPES: Dictionary = {
	"shell_charm": {"name": "Shell Charm", "cost": {"shell": 2}, "price": 8, "tier": 1},
	"driftwood_frame": {"name": "Driftwood Frame", "cost": {"driftwood": 2, "shell": 1}, "price": 14, "tier": 1},
	"seaglass_pendant": {"name": "Sea-glass Pendant", "cost": {"seaglass": 2}, "price": 18, "tier": 2},
	"wind_chime": {"name": "Wind Chime", "cost": {"driftwood": 1, "shell": 2, "seaglass": 1}, "price": 26, "tier": 2},
	"pearl_ring": {"name": "Pearl Ring", "cost": {"pearl": 1, "seaglass": 1}, "price": 40, "tier": 3},
	"tide_lantern": {"name": "Tide Lantern", "cost": {"pearl": 1, "driftwood": 2}, "price": 48, "tier": 3},
}

## Stable display/order list so seeded RNG draws are deterministic.
const RECIPE_ORDER: Array = ["shell_charm", "driftwood_frame", "seaglass_pendant", "wind_chime", "pearl_ring", "tide_lantern"]

## Demand-bonus multiplier applied to a sale of an in-demand item.
const DEMAND_BONUS: float = 1.5


static func recipe(id: String) -> Dictionary:
	return RECIPES[id]


static func recipe_name(id: String) -> String:
	var r: Dictionary = RECIPES[id]
	return r["name"]


static func base_price(id: String) -> int:
	var r: Dictionary = RECIPES[id]
	return r["price"]


static func recipes_up_to_tier(t: int) -> Array:
	var out: Array = []
	for id in RECIPE_ORDER:
		var r: Dictionary = RECIPES[id]
		var tier: int = r["tier"]
		if tier <= t:
			out.append(id)
	return out
