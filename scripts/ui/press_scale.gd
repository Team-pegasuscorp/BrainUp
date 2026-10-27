extends RefCounted

const SCALE := 0.94
const BOUNCE := 1.04


static func wire(button: Button, host: Node) -> void:
	if button == null or host == null:
		return
	button.resized.connect(func() -> void:
		button.pivot_offset = button.size * 0.5
	)
	button.button_down.connect(func() -> void:
		if not is_instance_valid(button) or not is_instance_valid(host):
			return
		AudioManager.play("click")
		button.pivot_offset = button.size * 0.5
		var tween: Tween = host.create_tween()
		## Kill the tween if the button is freed mid-press (e.g. duel strip rebuild).
		tween.bind_node(button)
		tween.tween_property(button, "scale", Vector2.ONE * SCALE, 0.06)
	)
	button.button_up.connect(func() -> void:
		if not is_instance_valid(button) or not is_instance_valid(host):
			return
		var tween: Tween = host.create_tween()
		tween.bind_node(button)
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "scale", Vector2.ONE * BOUNCE, 0.08)
		tween.tween_property(button, "scale", Vector2.ONE, 0.1)
	)
