class_name ScrollTouch

## A drag only scrolls a ScrollContainer when every control between the finger and
## the container lets the event through (MOUSE_FILTER_PASS). PanelContainer and
## Button default to STOP, so a page made of tiles could not be scrolled at all.
## PASS keeps taps working on buttons while the drag reaches the ScrollContainer.
static func let_drags_through(root: Node) -> void:
	if root is Control and (root as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
		(root as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for child in root.get_children():
		let_drags_through(child)
