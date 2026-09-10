extends ColorRect
## The void layer: a full-frame quad running the void shader. Feeds it the
## frame size, the palette, and the shared breath every frame.

@export var time_offset := 0.0

var _mat: ShaderMaterial


func _ready() -> void:
	_mat = material as ShaderMaterial
	_mat.set_shader_parameter("ground", Palette.color("ground"))
	_mat.set_shader_parameter("line_color", Palette.color("frame"))
	_mat.set_shader_parameter("light_color", Palette.color("light"))
	_mat.set_shader_parameter("gold_color", Palette.color("core"))
	_mat.set_shader_parameter("time_offset", time_offset)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	_mat.set_shader_parameter("res", size)


## Opaque ground in windowed mode; over the desktop the void is only light.
func set_ground_alpha(a: float) -> void:
	_mat.set_shader_parameter("ground_alpha", a)


func _process(_dt: float) -> void:
	_mat.set_shader_parameter("breath", Palette.breath())
