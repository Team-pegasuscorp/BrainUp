## Trophy-based league badge (icon + title).
## Thresholds are PROVISIONAL — design has not locked the ladders yet.
class_name TrophyLeagues
extends RefCounted

## Ordered low → high. Edit `min_trophies` when paliers are defined.
const TIERS: Array[Dictionary] = [
	{
		"id": "bronze",
		"min_trophies": 0,
		"icon": "🥉",
		"title_key": "UI_LEAGUE_BRONZE",
	},
	{
		"id": "silver",
		"min_trophies": 500,
		"icon": "🥈",
		"title_key": "UI_LEAGUE_SILVER",
	},
	{
		"id": "gold",
		"min_trophies": 1200,
		"icon": "🥇",
		"title_key": "UI_LEAGUE_GOLD",
	},
	{
		"id": "platinum",
		"min_trophies": 2000,
		"icon": "💠",
		"title_key": "UI_LEAGUE_PLATINUM",
	},
	{
		"id": "diamond",
		"min_trophies": 2800,
		"icon": "💎",
		"title_key": "UI_LEAGUE_DIAMOND",
	},
]


static func for_trophies(trophies: int) -> Dictionary:
	var points := maxi(trophies, 0)
	var current: Dictionary = TIERS[0]
	for tier in TIERS:
		if points >= int(tier.get("min_trophies", 0)):
			current = tier
		else:
			break
	return {
		"id": str(current.get("id", "bronze")),
		"icon": str(current.get("icon", "🥉")),
		"title_key": str(current.get("title_key", "UI_LEAGUE_BRONZE")),
		"min_trophies": int(current.get("min_trophies", 0)),
		## True until design finalizes the ladder numbers.
		"thresholds_provisional": true,
	}
