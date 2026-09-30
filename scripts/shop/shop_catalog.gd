class_name ShopCatalog
extends RefCounted

## Shop items (avatars, frames) read from data/shop/catalog.json.
## Frames are drawn by CircularAvatar's gradient ring (3 colour stops + width),
## so they need no art. Avatars point to a round PNG.

const CATALOG_PATH := "res://data/shop/catalog.json"
## Items marked "demo" reuse existing art to show the layout; hide them once real
## shop avatars exist (same idea as FORCE_DEMO_BOARD).
const SHOW_DEMO_ITEMS := true
## Coin balance given to saves that predate coins, while the economy is not wired.
const DEMO_START_COINS := 2000

const KIND_AVATAR := "avatar"
const KIND_FRAME := "frame"
const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]
const RARITY_COLORS := {
	"common": Color(0.36, 0.55, 0.78, 1),
	"rare": Color(0.18, 0.56, 0.88, 1),
	"epic": Color(0.55, 0.32, 0.95, 1),
	"legendary": Color(0.94, 0.62, 0.12, 1),
}

static var _items: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func items() -> Array[Dictionary]:
	_ensure_loaded()
	return _items


static func get_item(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(item_id, {})


static func has_item(item_id: String) -> bool:
	return not get_item(item_id).is_empty()


static func items_of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in items():
		if str(item.get("kind", "")) == kind:
			out.append(item)
	return out


## Items sold in the store (free defaults are owned from the start).
static func store_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in items():
		if int(item.get("price", 0)) > 0:
			out.append(item)
	return out


static func default_frame_id() -> String:
	for item in items_of_kind(KIND_FRAME):
		if bool(item.get("default", false)):
			return str(item["id"])
	return ""


static func display_name(item: Dictionary) -> String:
	var names: Variant = item.get("name", {})
	if typeof(names) != TYPE_DICTIONARY:
		return str(item.get("id", ""))
	var locale := str(LocaleManager.current_locale).substr(0, 2)
	return str(names.get(locale, names.get("en", item.get("id", ""))))


static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS.get(str(item.get("rarity", "common")), RARITY_COLORS["common"])


static func rarity_key(item: Dictionary) -> String:
	return "UI_RARITY_" + str(item.get("rarity", "common")).to_upper()


static func avatar_texture(item: Dictionary) -> Texture2D:
	var path := str(item.get("art", ""))
	if path.is_empty():
		return null
	return GameAssets.load_texture(path)


## Paints a CircularAvatar's ring with a frame item (unknown id = default frame).
static func apply_frame(avatar: Control, frame_id: String) -> void:
	var item := get_item(frame_id)
	if item.is_empty() or str(item.get("kind", "")) != KIND_FRAME:
		item = get_item(default_frame_id())
	if item.is_empty():
		return
	var colors: Array = item.get("colors", [])
	if colors.size() >= 3:
		avatar.set("ring_color", Color.html(str(colors[0])))
		avatar.set("ring_color_mid", Color.html(str(colors[1])))
		avatar.set("ring_color_secondary", Color.html(str(colors[2])))
	avatar.set("ring_width", float(item.get("width", 3.5)))
	(avatar as CanvasItem).queue_redraw()


static func _ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_warning("ShopCatalog: missing %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ShopCatalog: invalid catalog JSON")
		return
	for raw in parsed.get("items", []):
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("id"):
			continue
		if bool(raw.get("demo", false)) and not SHOW_DEMO_ITEMS:
			continue
		var item: Dictionary = raw
		_items.append(item)
		_by_id[str(item["id"])] = item
