extends CanvasLayer
## In-match chat, bottom-left above the health bar. Online only.
## Closed: new messages show for a few seconds, then fade. Press / for SERVER chat (this
## server) or right Shift for GLOBAL chat (every server): the recent history appears on
## a dark panel with a text box; Enter sends, Esc closes. While it's open your ball,
## weapons and camera ignore the keyboard (Net.input_blocked).
## Messages come from the Chat service (scripts/net/chat.gd).

const UIStyle := preload("res://scripts/ui/ui_style.gd")

const WIDTH := 460.0
## Lines shown while closed, and how long each stays before fading.
const CLOSED_LINES := 6
const SHOW_TIME := 10.0
const FADE_TIME := 1.5
const OPEN_LINES := 12
const GLOBAL_COLOR := Color(1.0, 0.55, 0.85)

var _chat: Node
var _net: Node
var _panel: PanelContainer
var _lines: VBoxContainer
var _input: LineEdit
var _open := false
## Which channel the open text box sends to.
var _global := false
var _mode_label: Label
## [label, seconds since it arrived] for each shown message, oldest first.
var _shown: Array = []


func _ready() -> void:
	layer = 6
	_chat = get_tree().root.get_node_or_null("Chat")
	_net = get_tree().root.get_node_or_null("Net")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.make_theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	box.add_child(_lines)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	box.add_child(input_row)
	_mode_label = UIStyle.label("", 13, UIStyle.ACCENT, true)
	input_row.add_child(_mode_label)
	_input = LineEdit.new()
	_input.max_length = 120
	_input.placeholder_text = "Enter send, Esc close"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_gui)
	input_row.add_child(_input)
	_set_open(false)

	if _chat:
		_chat.connect("message_received", _on_message)
		# Anything said before this match started (e.g. the last round).
		for entry in _chat.get("history").slice(-CLOSED_LINES):
			_add_line(entry, SHOW_TIME)


func _unhandled_input(event: InputEvent) -> void:
	if _open:
		return
	# / = server chat, right Shift = global chat (both rebindable).
	var global := event.is_action_pressed("chat_global")
	if not global and not event.is_action_pressed("chat"):
		return
	if not _net or not _net.get("online") or _net.get("input_blocked"):
		return
	get_viewport().set_input_as_handled()
	_global = global
	_set_open(true)


func _on_input_gui(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_input.accept_event()
		_set_open(false)


func _on_submitted(text: String) -> void:
	if _chat and text.strip_edges() != "":
		_chat.call("send", text, _global)
	_set_open(false)


func _set_open(open: bool) -> void:
	_open = open
	_input.visible = open
	_mode_label.visible = open
	_mode_label.text = "GLOBAL:" if _global else "SERVER:"
	_mode_label.add_theme_color_override("font_color", GLOBAL_COLOR if _global else UIStyle.ACCENT)
	_input.text = ""
	var style := UIStyle.panel_box(UIStyle.ACCENT_DIM if open else Color(0, 0, 0, 0), Color(0.02, 0.05, 0.08, 0.72) if open else Color(0, 0, 0, 0))
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	if _net:
		_net.set("input_blocked", open)
	if open:
		# Show the recent history while typing.
		for child in _lines.get_children():
			child.queue_free()
		_shown.clear()
		if _chat:
			for entry in _chat.get("history").slice(-OPEN_LINES):
				_add_line(entry, 0.0)
		_input.grab_focus.call_deferred()
	else:
		_input.release_focus()
		# The history shown while typing fades out soon after closing.
		for s in _shown:
			s[1] = maxf(s[1], SHOW_TIME - 2.0)


func _on_message(entry: Dictionary) -> void:
	_add_line(entry, 0.0)


func _add_line(entry: Dictionary, age: float) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 14)
	label.add_theme_font_override("normal_font", UIStyle.font())
	label.add_theme_font_override("bold_font", UIStyle.font(true))
	var text := ""
	if entry.get("global", false):
		text += "[color=#%s][b][GLOBAL · %s][/b][/color] " % [GLOBAL_COLOR.to_html(false), _escape(String(entry.get("server", "?")))]
	if entry.get("title", "") != "":
		text += "[color=#%s][b][%s][/b][/color] " % [Color(entry["title_color"]).to_html(false), entry["title"]]
	text += "[color=#%s][b]%s[/b][/color]: " % [Color(entry["color"]).to_html(false), _escape(entry["name"])]
	text += "[color=#%s]%s[/color]" % [UIStyle.TEXT.to_html(false), _escape(entry["text"])]
	label.text = text
	_lines.add_child(label)
	_shown.append([label, age])
	var keep := OPEN_LINES if _open else CLOSED_LINES
	while _shown.size() > keep:
		_shown[0][0].queue_free()
		_shown.pop_front()


## Players' text is shown as-is: no BBCode tricks.
func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _process(delta: float) -> void:
	# Keep typing where you left off: a mouse click, or an impact frame hiding the HUD
	# (dying, a kill), takes the keyboard focus away from the text box.
	if _open and _input.is_visible_in_tree() and not _input.has_focus():
		_input.grab_focus()
		_input.caret_column = _input.text.length()
	# Sit just above the health bar, growing upward.
	var view := _panel.get_viewport_rect().size
	_panel.position = Vector2(28.0, view.y - 96.0 - _panel.size.y)
	for i in range(_shown.size() - 1, -1, -1):
		var label: RichTextLabel = _shown[i][0]
		_shown[i][1] += delta
		if _open:
			label.modulate.a = 1.0
			continue
		var age: float = _shown[i][1]
		label.modulate.a = clampf(1.0 - (age - SHOW_TIME) / FADE_TIME, 0.0, 1.0)
		if age > SHOW_TIME + FADE_TIME:
			label.queue_free()
			_shown.remove_at(i)
