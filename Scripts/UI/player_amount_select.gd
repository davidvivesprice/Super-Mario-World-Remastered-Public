extends Control
@onready var pointer: CenterContainer = $Pointer

@onready var panels = [$"HBoxContainer/1Player", $"HBoxContainer/2Player", $"HBoxContainer/3Player", $"HBoxContainer/4Player"]

var selected_index := 0
var active := false

## Press-to-join state: after picking a count >1, each seat is claimed by an
## actual button press on the pad that will drive it (or Enter for keyboard).
var joining := false
var join_seat := 0
var join_cooldown := 0.0
var claimed_devices: Array[int] = []
var join_label: Label = null

signal selected
signal cancelled

func open() -> void:
	show()
	await get_tree().create_timer(0.25).timeout
	active = true

func _process(delta: float) -> void:
	if joining:
		join_cooldown = max(join_cooldown - delta, 0.0)
		return
	if not active:
		return
	if Input.is_action_just_pressed("ui_left"):
		selected_index -= 1
		SoundManager.play_ui_sound(SoundManager.select)
	if Input.is_action_just_pressed("ui_right"):
		selected_index += 1
		SoundManager.play_ui_sound(SoundManager.select)
	selected_index = clamp(selected_index, 0, 3)
	if Input.is_action_just_pressed("ui_accept"):
		selected_amount()
	if Input.is_action_just_pressed("ui_back"):
		cancel()
	pointer.global_position.x = panels[selected_index].global_position.x + 40.5
	var panel_index := 0
	for i in panels:
		i.global_position.y = 103
		if panel_index == selected_index:
			i.global_position.y = 85
		panel_index += 1

func selected_amount() -> void:
	SoundManager.play_ui_sound(SoundManager.coin)
	CoopManager.players_connected = selected_index + 1
	if CoopManager.players_connected == 1:
		# Solo: no ceremony - first connected pad already drives P1
		# (CoopManager._ready), just go.
		selected.emit()
		exit()
		return
	start_join_sequence()

func start_join_sequence() -> void:
	joining = true
	active = false
	join_seat = 0
	claimed_devices = []
	join_cooldown = 0.5   # swallow the button press that picked the count
	if join_label == null:
		join_label = Label.new()
		var template := $"HBoxContainer/1Player/Label" as Label
		if template:
			join_label.label_settings = template.label_settings
			join_label.theme = template.theme
		join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		join_label.anchors_preset = Control.PRESET_CENTER_TOP
		join_label.position = Vector2(0, 170)
		join_label.size = Vector2(size.x, 20)
		add_child(join_label)
	update_join_prompt()

func update_join_prompt() -> void:
	if join_label:
		join_label.text = "PLAYER %d - PRESS A ON YOUR CONTROLLER" % (join_seat + 1)
		join_label.show()

func finish_join_sequence() -> void:
	joining = false
	if join_label:
		join_label.hide()
	selected.emit()
	exit()

func _input(event: InputEvent) -> void:
	if not joining or join_cooldown > 0.0:
		return
	if event is InputEventJoypadButton and event.pressed:
		if claimed_devices.has(event.device):
			return   # this pad already has a seat
		SoundManager.play_ui_sound(SoundManager.coin)
		claimed_devices.append(event.device)
		CoopManager.assign_device_to_player(join_seat, event.device)
		join_seat += 1
		join_cooldown = 0.3
		if join_seat >= CoopManager.players_connected:
			finish_join_sequence()
		else:
			update_join_prompt()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			# Keyboard claims this seat; neutralize its joypad bindings so a
			# stray pad can't also drive it.
			SoundManager.play_ui_sound(SoundManager.coin)
			CoopManager.clear_device_for_player(join_seat)
			join_seat += 1
			join_cooldown = 0.3
			if join_seat >= CoopManager.players_connected:
				finish_join_sequence()
			else:
				update_join_prompt()
		elif event.keycode == KEY_ESCAPE:
			# back out of joining to the count select
			joining = false
			if join_label:
				join_label.hide()
			active = true

func cancel() -> void:
	exit()
	SoundManager.play_ui_sound(SoundManager.fireball)
	cancelled.emit()

func exit() -> void:
	hide()
	active = false


func _on_save_select_closed() -> void:
	pass # Replace with function body.
