extends CanvasLayer
## Per-seat slow-mo charge meters, bottom-center band (the one persistent-free
## zone: clears the top HUD, SpeedrunTimer bottom-right, MusicNotif bottom-left).
## Layer 2: survives 2P split-screen (panes are layer 1), yields to course
## clear / messages (layer 5). Reads CoopManager.slowmo_charge; builds its own
## nodes so the scene diff stays one line.

const FLASH_HZ := 8.0
const BAR_EMPTY := preload("res://Assets/Sprites/UI/PMeterEmpty.png")
const BAR_FULL := preload("res://Assets/Sprites/UI/PMeterFull.png")

var seats: Array = []
var _t := 0.0

func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -12.0
	row.offset_bottom = -3.0
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for seat in 4:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var head := TextureRect.new()
		head.name = "Head"
		head.custom_minimum_size = Vector2(12, 12)
		head.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		box.add_child(head)
		var bar := TextureProgressBar.new()
		bar.name = "Bar"
		bar.max_value = 100.0
		bar.texture_under = BAR_EMPTY
		bar.texture_progress = BAR_FULL
		bar.custom_minimum_size = Vector2(32, 5)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(bar)
		row.add_child(box)
		seats.append(box)

func _process(delta: float) -> void:
	_t += delta
	visible = SettingsManager.settings_file.get("slowmo_powerups", true) \
		and is_instance_valid(GameManager.current_level) \
		and is_instance_valid(CoopManager.get_first_any_player()) \
		and not GameManager.secret_clear \
		and not get_tree().paused
	if not visible:
		return
	for seat in 4:
		var box: Control = seats[seat]
		var node = CoopManager.active_players.get(seat)
		var seated: bool = seat < CoopManager.players_connected \
			and is_instance_valid(node) and not node.out_of_game
		box.visible = seated
		if not seated:
			continue
		box.get_node("Head").texture = CoopManager.character_for_seat(seat).HUDLetter
		var bar: TextureProgressBar = box.get_node("Bar")
		bar.value = CoopManager.slowmo_charge[seat]
		var col: Color = CoopManager.player_colours[seat]
		if CoopManager.slowmo_charge[seat] >= 100.0:
			bar.tint_progress = col.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * FLASH_HZ))
		else:
			bar.tint_progress = col
		box.modulate.a = 0.5 if CoopManager.dead_players.has(seat) else 1.0
