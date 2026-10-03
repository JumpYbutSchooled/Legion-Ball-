extends RichTextEffect
## [owner]text[/owner]: the owner tag's pink -> white -> light blue gradient, sweeping
## across the letters (scripts/ui/rainbow.gd has the colours; loaded, not preloaded,
## since it preloads this).

var bbcode := "owner"
var _colors: GDScript


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	if not _colors:
		_colors = load("res://scripts/ui/rainbow.gd")
	var a := char_fx.color.a
	char_fx.color = _colors.color_at(char_fx.relative_index * 0.07 - char_fx.elapsed_time * 0.35)
	char_fx.color.a = a
	return true
