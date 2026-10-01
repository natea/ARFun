extends Node
## Picks which game to play. Hold your left hand up for the left game or your right hand up for
## the right game, click a card, or press 1 / 2. Esc comes back here from any game.
## Expects to be a child of the node running pose_driver_3d.gd, next to the game nodes.

const HOLD_TIME := 1.0
# [node name, title, how to play]
const GAMES := [
	["BallGame", "Ball Game", "Hit the flying balls\nwith your arms and legs"],
	["PingPong", "Ping Pong", "Rally against the CPU\nwith a paddle in your right hand"],
]

@onready var _driver: Node = get_parent()

var _layer := CanvasLayer.new()
var _menu := Control.new()
var _bars: Array[ProgressBar] = []
var _hold := [0.0, 0.0]
var _waiting_for_hands_down := false


func _ready() -> void:
	_layer.layer = 10
	add_child(_layer)
	_build_menu()
	var back_hint := Label.new()
	back_hint.text = "Esc: menu"
	back_hint.modulate = Color(1, 1, 1, 0.6)
	back_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	back_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layer.add_child(back_hint)
	show_menu()


func show_menu() -> void:
	for game in GAMES:
		_driver.get_node(game[0]).set_active(false)
	_menu.visible = true
	_hold = [0.0, 0.0]
	_waiting_for_hands_down = true


func pick(index: int) -> void:
	_menu.visible = false
	for i in GAMES.size():
		_driver.get_node(GAMES[i][0]).set_active(i == index)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		show_menu()
	elif _menu.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_KP_1]:
			pick(0)
		elif event.keycode in [KEY_2, KEY_KP_2]:
			pick(1)


func _process(delta: float) -> void:
	if not _menu.visible:
		return
	var left: bool = _driver.is_hand_raised("left")
	var right: bool = _driver.is_hand_raised("right")
	# After coming back to the menu, wait until both hands are down so a raised hand
	# left over from the last game doesn't pick instantly.
	if _waiting_for_hands_down:
		_waiting_for_hands_down = left or right
		return
	var raised := [left and not right, right and not left]
	for i in 2:
		_hold[i] = _hold[i] + delta if raised[i] else maxf(_hold[i] - delta * 2.0, 0.0)
		_bars[i].value = _hold[i] / HOLD_TIME
		if _hold[i] >= HOLD_TIME:
			pick(i)
			return


func _build_menu() -> void:
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_menu)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 28)
	_menu.add_child(column)

	var title := Label.new()
	title.text = "ARFun"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Hold up a hand to choose a game"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.modulate = Color(1, 1, 1, 0.75)
	column.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var hands := ["Raise your LEFT hand  (or press 1)", "Raise your RIGHT hand  (or press 2)"]
	for i in GAMES.size():
		var card := Button.new()
		card.custom_minimum_size = Vector2(360, 230)
		card.focus_mode = Control.FOCUS_NONE
		card.pressed.connect(pick.bind(i))
		row.add_child(card)
		var inner := VBoxContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
		inner.add_theme_constant_override("separation", 10)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(inner)
		for text_and_size in [[GAMES[i][1], 38], [GAMES[i][2], 20], [hands[i], 18]]:
			var label := Label.new()
			label.text = text_and_size[0]
			label.add_theme_font_size_override("font_size", text_and_size[1])
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(bar)
		_bars.append(bar)
