@tool
class_name AuroreTile
extends ColorRect

## Rounded aurora background for home “near achievement” tiles.
## Property is `aurore_theme` (not Control.theme) — see palette keys below.

const SHADER_PATH := "res://shaders/aurore.gdshader"
const CORNER_RADIUS := 14.0

## Palette keys for inspector + code (see PALETTES).
@export_enum(
	"violet", "sunset", "ocean", "foret", "fruits", "or", "indigo", "menthe",
	"lavande", "lagon", "crepuscule", "bonbon", "citron", "minuit", "sakura", "lave"
)
var aurore_theme: String = "violet":
	set(value):
		aurore_theme = value if PALETTES.has(value) else "violet"
		_apply_palette()

## c1, c2, base as HTML hex (no #).
const PALETTES := {
	"violet": ["7c5cff", "00c2b8", "2a2275"],
	"sunset": ["ff6a88", "ff9a3c", "4a1d3d"],
	"ocean": ["2f80ff", "22d3ee", "0f2a5c"],
	"foret": ["22c55e", "e6e33a", "10372a"],
	"fruits": ["ff3d6e", "8b5cf6", "3a1346"],
	"or": ["ffb020", "ff5c7a", "4a2410"],
	"indigo": ["4f46e5", "ec4899", "1b1a4d"],
	"menthe": ["34e0b8", "4aa8ff", "0e3a4a"],
	"lavande": ["a78bfa", "f0abfc", "2e1f5e"],
	"lagon": ["06b6d4", "34d399", "073b4c"],
	"crepuscule": ["6366f1", "f97316", "1e1b4b"],
	"bonbon": ["f472b6", "60a5fa", "3b1d5a"],
	"citron": ["84cc16", "22d3ee", "14352a"],
	"minuit": ["3b82f6", "a855f7", "0b1437"],
	"sakura": ["f9a8d4", "c4b5fd", "4a1d4d"],
	"lave": ["ef4444", "f59e0b", "2b0a0a"],
}


## Pick the palette whose blob/base colours sit closest to `accent`.
static func theme_closest_to(accent: Color, exclude: Dictionary = {}) -> String:
	var best := "violet"
	var best_dist := INF
	var found := false
	for key in PALETTES.keys():
		var theme_key := str(key)
		if exclude.has(theme_key):
			continue
		var colors: Array = PALETTES[key]
		for hex in colors:
			var sample := Color.html("#%s" % str(hex))
			var dr := accent.r - sample.r
			var dg := accent.g - sample.g
			var db := accent.b - sample.b
			var dist := dr * dr + dg * dg + db * db
			if dist < best_dist:
				best_dist = dist
				best = theme_key
				found = true
	if found:
		return best
	## All palettes excluded — fall back to unrestricted closest.
	return theme_closest_to(accent, {})


## Closest theme per accent, without reusing a palette in the same row.
static func themes_closest_unique(accents: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	var used := {}
	for accent_variant in accents:
		var accent: Color = accent_variant
		var theme := theme_closest_to(accent, used)
		used[theme] = true
		out.append(theme)
	return out


static func primary_color(theme_key: String) -> Color:
	var key := theme_key if PALETTES.has(theme_key) else "violet"
	var colors: Array = PALETTES[key]
	return Color.html("#%s" % str(colors[0]))


## Vibrant aurore c1 colours for charts — one unique palette per accent when possible.
static func colors_closest_unique(accents: Array) -> Array:
	var themes := themes_closest_unique(accents)
	var out: Array = []
	for theme in themes:
		out.append(primary_color(str(theme)))
	return out


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_ensure_material()
	_apply_palette()
	if not resized.is_connected(_sync_rect_uniforms):
		resized.connect(_sync_rect_uniforms)
	_sync_rect_uniforms()


func _ensure_material() -> void:
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	material = mat


func _apply_palette() -> void:
	_ensure_material()
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var key := aurore_theme if PALETTES.has(aurore_theme) else "violet"
	var colors: Array = PALETTES[key]
	mat.set_shader_parameter("c1", Color.html("#%s" % colors[0]))
	mat.set_shader_parameter("c2", Color.html("#%s" % colors[1]))
	mat.set_shader_parameter("base", Color.html("#%s" % colors[2]))
	mat.set_shader_parameter("radius", CORNER_RADIUS)
	_sync_rect_uniforms()


func _sync_rect_uniforms() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var side := size
	if side.x < 1.0 or side.y < 1.0:
		side = custom_minimum_size
	mat.set_shader_parameter("rect_size", side)
	mat.set_shader_parameter("radius", CORNER_RADIUS)
