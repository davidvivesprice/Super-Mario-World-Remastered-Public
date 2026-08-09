extends CanvasLayer
## Per-seat slow-mo charge meters, v2 after playtest: bigger, juicier, and
## unmistakable about when the powerup is READY. Bottom-center band (clear of
## SpeedrunTimer bottom-right and MusicNotif bottom-left). Layer 2: survives
## 2P split-screen (panes are layer 1), yields to course clear (layer 5).

const FLASH_HZ := 10.0

var seats: Array = []
var _t := 0.0

func _make_bar_styles(fill_col: Color) -> Array:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.07, 0.12, 0.9)
	bg.border_color = Color(1, 1, 1, 0.45)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.set_corner_radius_all(2)
	return [bg, fill]

func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -22.0
	row.offset_bottom = -2.0
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for seat in 4:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		# READY! label rides above the bar, hidden until armed
		var ready := Label.new()
		ready.name = "Ready"
		ready.text = "READY!"
		ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ready.add_theme_font_size_override("font_size", 8)
		ready.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		ready.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
		ready.add_theme_constant_override("outline_size", 2)
		ready.visible = false
		box.add_child(ready)
		var strip := HBoxContainer.new()
		strip.name = "Strip"
		strip.add_theme_constant_override("separation", 3)
		var head := TextureRect.new()
		head.name = "Head"
		head.custom_minimum_size = Vector2(12, 12)
		head.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		strip.add_child(head)
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(48, 9)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var styles := _make_bar_styles(Color.WHITE)
		bar.add_theme_stylebox_override("background", styles[0])
		bar.add_theme_stylebox_override("fill", styles[1])
		strip.add_child(bar)
		box.add_child(strip)
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
		box.get_node("Strip/Head").texture = CoopManager.character_for_seat(seat).HUDLetter
		var bar: ProgressBar = box.get_node("Strip/Bar")
		var ready_label: Label = box.get_node("Ready")
		bar.value = CoopManager.slowmo_charge[seat]
		var col: Color = CoopManager.player_colours[seat]
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
		var armed: bool = CoopManager.slowmo_charge[seat] >= 100.0
		var active: bool = (SlowMo.enemy_seat == seat) or (SlowMo.world_seat == seat)
		if active:
			# draining: show the mode colour so the owner reads at a glance
			var mode_col: Color = SlowMo.TEAL if SlowMo.enemy_seat == seat else SlowMo.INDIGO
			fill.bg_color = mode_col.lerp(Color.WHITE, 0.15)
			ready_label.visible = false
		elif armed:
			# unmissable: gold-white strobe + bouncing READY!
			fill.bg_color = Color(1.0, 0.85, 0.2).lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * FLASH_HZ))
			ready_label.visible = true
			ready_label.position.y = -absf(sin(_t * 6.0)) * 2.0
		else:
			fill.bg_color = col
			ready_label.visible = false
		box.modulate.a = 0.5 if CoopManager.dead_players.has(seat) else 1.0
