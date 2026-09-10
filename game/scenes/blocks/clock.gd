extends VBoxContainer
## The first instrument: the time, large, and the date under it. Alive
## enough to prove the block is not a picture.

@onready var time_label: Label = $Time
@onready var date_label: Label = $Date

const DAYS := ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]


func _ready() -> void:
	var light := Palette.color("light")
	time_label.add_theme_color_override("font_color", light)
	time_label.add_theme_font_override("font", Palette.DISPLAY)
	time_label.add_theme_font_size_override("font_size", 30)
	date_label.add_theme_color_override("font_color", Palette.dim(light, 0.6))
	date_label.add_theme_font_size_override("font_size", 9)
	_tick()


func _process(_dt: float) -> void:
	_tick()


func _tick() -> void:
	var d := Time.get_datetime_dict_from_system()
	time_label.text = "%02d:%02d" % [d.hour, d.minute]
	date_label.text = "%s  %s %02d" % [DAYS[d.weekday], MONTHS[d.month - 1], d.day]
