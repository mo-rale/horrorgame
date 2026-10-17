extends CanvasLayer
## Keeps the 1920x1080 title frame centred and scaled to the window, so the
## titles look the same at any resolution.

@onready var _frame: Control = $Frame1080


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	var s := minf(view.x / 1920.0, view.y / 1080.0)
	_frame.scale = Vector2(s, s)
	_frame.position = (view - Vector2(1920, 1080) * s) * 0.5
