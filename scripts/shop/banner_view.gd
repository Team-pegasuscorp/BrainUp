class_name BannerView
extends Panel

## Player banner drawn from a catalogue item: a horizontal gradient (2-3 colours)
## plus a light pattern, with rounded corners. Everything is done by one shader
## (shaders/banner.gdshader) so a banner costs one draw call: drawing the pattern
## shape by shape cost hundreds each and made the Classement drop to ~47 FPS.

const BannerShader := preload("res://shaders/banner.gdshader")
const PATTERN_ALPHA := 0.16
const PATTERN_IDS := {"stripes": 1, "dots": 2, "waves": 3, "chevrons": 4, "stars": 5}

var colors: Array[Color] = [Color(0.17, 0.14, 0.31), Color(0.29, 0.18, 0.48)]
var pattern: String = ""
var corner_radius: int = 18

var _material := ShaderMaterial.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_material.shader = BannerShader
	_material.set_shader_parameter("pattern_alpha", PATTERN_ALPHA)
	material = _material
	resized.connect(_on_resized)
	_apply_colors()
	_apply_radius()


## Unknown / empty id gives the default banner.
func set_banner(banner_id: String) -> void:
	var item := ShopCatalog.get_item(banner_id)
	if str(item.get("kind", "")) != ShopCatalog.KIND_BANNER:
		item = ShopCatalog.get_item(ShopCatalog.default_banner_id())
	var parsed: Array[Color] = []
	for raw in item.get("colors", []):
		parsed.append(Color.html(str(raw)))
	if parsed.size() >= 2:
		colors = parsed
	pattern = str(item.get("pattern", ""))
	_apply_colors()


func set_corner_radius(radius: int) -> void:
	corner_radius = radius
	_apply_radius()


func _apply_colors() -> void:
	_material.set_shader_parameter("color_a", colors[0])
	_material.set_shader_parameter("color_b", colors[1])
	_material.set_shader_parameter("color_c", colors[mini(2, colors.size() - 1)])
	_material.set_shader_parameter("stops", mini(colors.size(), 3))
	_material.set_shader_parameter("pattern", int(PATTERN_IDS.get(pattern, 0)))


func _apply_radius() -> void:
	_material.set_shader_parameter("radius", float(corner_radius))


func _on_resized() -> void:
	_material.set_shader_parameter("rect_size", size)
	queue_redraw()


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
