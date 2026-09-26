extends Button
## A weapon card in the Armory (menu_ui.gd _build_armory): in the pool, or in one of the
## six loadout slots. Drag a pool card onto a slot to equip it, or drag slots onto each
## other to reorder. Clicking shows the weapon's briefing; with a controller (or the
## mouse, if you'd rather not drag), press a card to pick it up and a slot to place it.
## Concept weapons ("built": false) can be looked at but not picked up.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")

## Weapon id shown ("" = empty slot).
var weapon_id := ""
## Loadout slot this card is (0-5), or -1 for a pool card.
var slot := -1
## The Armory page (menu_ui.gd), which owns the loadout and handles drops.
var armory: Node

var _stripe: ColorRect


func _ready() -> void:
	var info := WeaponInfo.by_id(weapon_id)
	var built: bool = info.get("built", false)
	var color: Color = info.get("color", UIStyle.TEXT_DIM)
	custom_minimum_size = Vector2(150 if slot < 0 else 90, 58 if slot < 0 else 52)
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_size_override("font_size", 13)
	var label: String = info.get("name", "EMPTY")
	if slot >= 0:
		text = "%d  %s" % [slot + 1, label]
	elif built:
		text = label
	else:
		text = "%s\nNOT BUILT YET" % label
	add_theme_color_override("font_color", color if built else Color(color, 0.45))
	add_theme_color_override("font_hover_color", Color.WHITE if built else Color(color, 0.7))
	tooltip_text = String(info.get("summary", ""))
	# A stripe in the weapon's own colour down the left edge.
	_stripe = ColorRect.new()
	_stripe.color = color if built else Color(color, 0.3)
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stripe.position = Vector2(0, 0)
	_stripe.size = Vector2(4, custom_minimum_size.y)
	add_child(_stripe)
	pressed.connect(func() -> void: armory.call("_card_pressed", self))


func _get_drag_data(_at: Vector2) -> Variant:
	if weapon_id == "" or not WeaponInfo.is_built(weapon_id):
		return null
	var preview := Label.new()
	preview.text = "  " + String(WeaponInfo.by_id(weapon_id)["name"]) + "  "
	preview.add_theme_color_override("font_color", WeaponInfo.by_id(weapon_id)["color"])
	preview.add_theme_font_override("font", UIStyle.font(true))
	preview.add_theme_font_size_override("font_size", 16)
	set_drag_preview(preview)
	return {"weapon": weapon_id, "from_slot": slot}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return slot >= 0 and typeof(data) == TYPE_DICTIONARY and data.has("weapon")


func _drop_data(_at: Vector2, data: Variant) -> void:
	armory.call("_loadout_drop", slot, data)
