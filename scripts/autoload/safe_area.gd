extends Node
## Screen insets (notch / camera cut-out, status bar, gesture or 3-button navigation
## bar) in the game's logical 720-wide pixels, so UI can stay clear of them.
## Desktop reports zero. Set BRAINUP_INSETS="top,bottom[,left,right]" to fake insets
## when testing layouts on a PC.

signal changed

const POLL_SECONDS := 1.0
## Sanity cap: never let a bogus value eat more than this share of the screen.
const MAX_SHARE := 0.25

var top: float = 0.0
var bottom: float = 0.0
var left: float = 0.0
var right: float = 0.0


func _ready() -> void:
	get_tree().root.size_changed.connect(refresh)
	## System bars can appear or hide without the window being resized.
	var poll := Timer.new()
	poll.wait_time = POLL_SECONDS
	poll.timeout.connect(refresh)
	add_child(poll)
	poll.start()
	refresh()


func refresh() -> void:
	var insets := _read_insets()
	if insets.is_equal_approx(Vector4(top, bottom, left, right)):
		return
	top = insets.x
	bottom = insets.y
	left = insets.z
	right = insets.w
	changed.emit()


## Adds the insets on top of a MarginContainer's own margins, and keeps them updated.
func fit_margins(container: MarginContainer) -> void:
	if not container.has_meta("safe_base"):
		container.set_meta("safe_base", Vector4(
			container.get_theme_constant("margin_top"),
			container.get_theme_constant("margin_bottom"),
			container.get_theme_constant("margin_left"),
			container.get_theme_constant("margin_right"),
		))
		var update := func() -> void: _apply_margins(container)
		changed.connect(update)
		container.tree_exiting.connect(func() -> void: changed.disconnect(update))
	_apply_margins(container)


func _apply_margins(container: MarginContainer) -> void:
	var base: Vector4 = container.get_meta("safe_base")
	container.add_theme_constant_override("margin_top", int(base.x + top))
	container.add_theme_constant_override("margin_bottom", int(base.y + bottom))
	container.add_theme_constant_override("margin_left", int(base.z + left))
	container.add_theme_constant_override("margin_right", int(base.w + right))


## (top, bottom, left, right) in logical pixels.
func _read_insets() -> Vector4:
	var forced := OS.get_environment("BRAINUP_INSETS")
	if not forced.is_empty():
		var values := forced.split_floats(",")
		if values.size() >= 2:
			return Vector4(values[0], values[1],
				values[2] if values.size() > 2 else 0.0,
				values[3] if values.size() > 3 else 0.0)

	## On desktop the "safe area" is the monitor, not the window: ignore it there.
	if not OS.get_name() in ["Android", "iOS"]:
		return Vector4.ZERO

	var window_size := Vector2(DisplayServer.window_get_size())
	var logical_size := get_tree().root.get_visible_rect().size
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if window_size.x <= 0.0 or logical_size.x <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO

	## keep_width stretch: one scale for both axes, from window pixels to logical.
	var scale := window_size.x / logical_size.x
	var max_y := logical_size.y * MAX_SHARE
	var max_x := logical_size.x * MAX_SHARE
	return Vector4(
		clampf(maxf(safe.position.y, 0.0) / scale, 0.0, max_y),
		clampf(maxf(window_size.y - safe.end.y, 0.0) / scale, 0.0, max_y),
		clampf(maxf(safe.position.x, 0.0) / scale, 0.0, max_x),
		clampf(maxf(window_size.x - safe.end.x, 0.0) / scale, 0.0, max_x),
	)
