extends CanvasLayer
## Per-seat slow-mo charge meters, v3: charge-only bar (fire dumps it, flat
## 15 s effect - no drain weirdness), pinned INSIDE the screen with hard
## offsets (v2's anchor math could land off-screen), gold READY strobe,
## bumper-hold progress ring as a thin underline, optional speedometer.
## Layer 2: above split panes (1), below course-clear UI (5).

const FLASH_HZ := 10.0

var seats: Array = []
var _t := 0.0

func _make_bar_styles() -> Array:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.07, 0.12, 0.9)
	bg.border_color = Color(1, 1, 1, 0.45)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	fill.set_corner_radius_all(2)
	return [bg, fill]

func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	# hard-pinned strip: full width, sitting 24..4 px above the bottom edge -
	# the HBox centers its content, nothing can leave the screen
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 0.0
	row.offset_right = 0.0
	row.offset_top = -24.0
	row.offset_bottom = -4.0
	for seat in 4:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var ready := Label.new()
		ready.name = "Ready"
		ready.text = "HOLD BUMPER!"
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
		var styles := _make_bar_styles()
		bar.add_theme_stylebox_override("background", styles[0])
		bar.add_theme_stylebox_override("fill", styles[1])
		strip.add_child(bar)
		var speed := Label.new()
		speed.name = "Speed"
		speed.add_theme_font_size_override("font_size", 8)
		speed.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
		speed.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		speed.add_theme_constant_override("outline_size", 2)
		speed.visible = false
		strip.add_child(speed)
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
	var speedo: bool = SettingsManager.settings_file.get("speedometer", false)
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
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
		var col: Color = CoopManager.player_colours[seat]
		var armed: bool = CoopManager.slowmo_charge[seat] >= 100.0
		var holding: float = SlowMo.hold_time[seat]
		var active: bool = SlowMo.active_seat == seat
		if active:
			# effect running: bar becomes the countdown so the owner sees it
			bar.value = 100.0 * SlowMo.time_left / SlowMo.EFFECT_SECONDS
			fill.bg_color = Color(0.05, 0.78, 0.72).lerp(Color.WHITE, 0.2)
			ready_label.visible = false
		elif armed:
			bar.value = 100.0
			if holding > 0.0:
				# bumper hold progress: fill sweeps white as the hold completes
				fill.bg_color = col.lerp(Color.WHITE, holding / SlowMo.HOLD_SECONDS)
			else:
				fill.bg_color = Color(1.0, 0.85, 0.2).lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * FLASH_HZ))
			ready_label.visible = true
			ready_label.position.y = -absf(sin(_t * 6.0)) * 2.0
		else:
			bar.value = CoopManager.slowmo_charge[seat]
			fill.bg_color = col
			ready_label.visible = false
		var speed_label: Label = box.get_node("Strip/Speed")
		speed_label.visible = speedo
		if speedo:
			speed_label.text = str(absi(roundi(node.velocity.x)))
		box.modulate.a = 0.5 if CoopManager.dead_players.has(seat) else 1.0
