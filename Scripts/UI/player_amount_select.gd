extends Control
## One-screen couch lobby. Replaces the old count-select AND the separate
## DeviceAssigner screen: every pad that presses a button claims the next
## seat (full bindings assigned on the spot), the keyboard can take P1 with
## ENTER, and START launches with everyone who joined. Character select
## still follows - that screen is the fun part.

@onready var pointer: CenterContainer = $Pointer
@onready var panels_box: HBoxContainer = $HBoxContainer
@onready var heading: Label = $Label

## QA-only marker for SHIFT+ENTER ghost seats (test 2P+ with no pads).
const GHOST_DEVICE := -3

var active := false
var claimed: Array[int] = []   # device id per seat (NO_DEVICE = keyboard/ghost)
var seat_labels: Array[Label] = []
var hint_label: Label = null
var cooldown := 0.0

signal selected
signal cancelled

func open() -> void:
	show()
	panels_box.hide()
	pointer.hide()
	build_labels()
	claimed = []
	cooldown = 0.35
	# Clean slate every visit: default keyboard back, no joypad bindings on
	# any seat until a pad claims one (the DeviceAssigner used to do this).
	InputMap.load_from_project_settings()
	for seat in 4:
		CoopManager.clear_seat_joypad_bindings(seat)
	refresh()
	await get_tree().create_timer(0.25).timeout
	active = true

func build_labels() -> void:
	if hint_label != null:
		return
	var template := $"HBoxContainer/1Player/Label" as Label
	for i in 4:
		var l := Label.new()
		if template:
			l.label_settings = template.label_settings
			l.theme = template.theme
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(0, 92 + i * 26)
		l.size = Vector2(size.x, 20)
		add_child(l)
		seat_labels.append(l)
	hint_label = Label.new()
	if template:
		hint_label.label_settings = template.label_settings
		hint_label.theme = template.theme
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(0, 214)
	hint_label.size = Vector2(size.x, 20)
	add_child(hint_label)

func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)

func refresh() -> void:
	heading.text = "Who's Playing?"
	for i in 4:
		if i < claimed.size():
			var dev := claimed[i]
			var who := "KEYBOARD" if dev == CoopManager.NO_DEVICE else "PAD %d" % (dev + 1)
			seat_labels[i].text = "P%d  %s  -  IN!" % [i + 1, who]
			seat_labels[i].modulate = CoopManager.player_colours[i]
		elif i == claimed.size():
			seat_labels[i].text = "P%d  press any button to join" % [i + 1]
			seat_labels[i].modulate = Color(1, 1, 1, 0.85)
		else:
			seat_labels[i].text = "-"
			seat_labels[i].modulate = Color(1, 1, 1, 0.25)
	if hint_label:
		if claimed.is_empty():
			hint_label.text = "grab a controller and press any button   (keyboard: ENTER)"
		else:
			hint_label.text = "START = play!    B = leave    friends can hop in any time mid-game"

func _input(event: InputEvent) -> void:
	if not visible or not active or cooldown > 0.0:
		return
	if event is InputEventJoypadButton and event.pressed:
		var dev: int = event.device
		var seat := claimed.find(dev)
		if event.button_index == JOY_BUTTON_START:
			if seat != -1:
				begin()
			elif claimed.is_empty() and dev >= 0:
				claim(dev)
			return
		if event.button_index == JOY_BUTTON_B:
			if seat != -1:
				unclaim(dev)
			elif claimed.is_empty():
				back_out()
			return
		if seat == -1 and claimed.size() < 4:
			claim(dev)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER:
				if event.shift_pressed:
					# QA hook: SHIFT+ENTER adds a ghost seat (no inputs) so
					# multi-player flows can be tested without physical pads
					if claimed.size() < 4:
						claim(GHOST_DEVICE)
				elif claimed.has(CoopManager.NO_DEVICE):
					begin()
				elif claimed.is_empty():
					claim(CoopManager.NO_DEVICE)   # keyboard is always P1
			KEY_ESCAPE:
				if claimed.has(CoopManager.NO_DEVICE):
					unclaim(CoopManager.NO_DEVICE)
				elif not claimed.is_empty():
					# pads claimed but keyboard wants out of the whole screen
					back_out()
				else:
					back_out()

func claim(dev: int) -> void:
	SoundManager.play_ui_sound(SoundManager.coin)
	var marker := CoopManager.NO_DEVICE if dev < 0 else dev
	claimed.append(marker)
	reassign_all()
	refresh()

func unclaim(dev: int) -> void:
	SoundManager.play_ui_sound(SoundManager.fireball)
	var idx := claimed.find(dev)
	if idx == -1:
		return
	claimed.remove_at(idx)
	reassign_all()
	refresh()

## Seats are always packed from P1 up; rebuild every seat's bindings so a
## mid-list leave shuffles everyone down correctly.
func reassign_all() -> void:
	for seat in 4:
		if seat < claimed.size() and claimed[seat] != CoopManager.NO_DEVICE:
			CoopManager.assign_device_to_player(seat, claimed[seat])
		else:
			CoopManager.clear_device_for_player(seat)

func begin() -> void:
	if claimed.is_empty():
		return
	SoundManager.play_ui_sound(SoundManager.coin)
	CoopManager.players_connected = claimed.size()
	active = false
	selected.emit()
	exit()

func back_out() -> void:
	SoundManager.play_ui_sound(SoundManager.fireball)
	exit()
	cancelled.emit()

func cancel() -> void:
	back_out()

func exit() -> void:
	hide()
	active = false

func _on_save_select_closed() -> void:
	pass # legacy scene-signal stub
