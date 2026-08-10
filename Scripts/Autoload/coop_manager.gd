extends Node

var players := {}

var splitscreen := false

var player_1: Player = null
var player_2: Player = null
var player_3: Player = null
var player_4: Player = null

var player_amount := 0

@onready var splitscreen_ratios = [Vector2(0.5, 1), Vector2(0.5, 0.5), Vector2(0.5, 0.5)]

var coop_enabled := true
var waiting := false
signal wait_finished
@onready var splitscreen_canvas: CanvasLayer = $Splitscreen

signal player_spawned
signal players_exited_pipe

@onready var off_screen_icons = [$Player1OffScreenIcon, $Player2OffScreenIcon, $Player3OffScreenIcon, $Player4OffScreenIcon]

var player_colours = [Color.LIGHT_SKY_BLUE, Color.RED, Color.GREEN, Color.YELLOW]
const SMALL = ("res://Resources/PlayerPowerUpState/Small.tres")
const BIG = ("res://Resources/PlayerPowerUpState/Big.tres")

@onready var character_head_icons = [load("res://Assets/Sprites/Characters/Mario/HeadIcon.png"), load("res://Assets/Sprites/Characters/Luigi/HeadIcon.png"), load("res://Assets/Sprites/Characters/Toad/HeadIcon.png"), load("res://Assets/Sprites/Characters/Toadette/HeadIcon.png")]

var bubble_fly_away := false
const PLAYER = preload("res://Instances/Prefabs/Player.tscn")
@onready var player_characters = {0: load("res://Resources/Characters/Mario.tres"), 1: load("res://Resources/Characters/Luigi.tres"), 2: load("res://Resources/Characters/Toad.tres"), 3: load("res://Resources/Characters/Toadette.tres")}
var player_power_states = [SMALL, SMALL, SMALL, SMALL]
var player_power_overrides := [null, null, null, null]
var player_yoshis = [false, false, false, false]
var yoshi_colours = [Yoshi.colours.GREEN, Yoshi.colours.GREEN, Yoshi.colours.GREEN, Yoshi.colours.GREEN]
var player_device_ids := [0, 1, 2, 3]
var pipe_exiting := false
var players_connected := 1
var crown_player := -1

var camera_distance_zoom_enabled := false

@onready var coop_camera: Camera2D = $CoopCamera

var wait_finished_players = []
var active_players = {}
var alive_players = {}
var dead_players := {}
var game_overed_players := {}


@onready var PLAYER_SCENE = load("res://Instances/Prefabs/Player.tscn")

## Actions that exist once per player as "<action>_<player_id>" in the InputMap.
const PER_PLAYER_ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down", "jump", "spin_jump", "run", "dive", "slowmo_enemy", "slowmo_world"]

## Marker in player_device_ids for a seat with no pad (keyboard or empty).
const NO_DEVICE := 63

## The same binding resources the base game's DeviceAssigner used - a full
## stick + d-pad + alt-button set per seat, duplicated onto a chosen device.
const SEAT_PRIMARY_ACTIONS := [preload("res://Resources/Inputs/dive.tres"), preload("res://Resources/Inputs/jump.tres"), preload("res://Resources/Inputs/move_down_stick.tres"), preload("res://Resources/Inputs/move_left_stick.tres"), preload("res://Resources/Inputs/move_right_stick.tres"), preload("res://Resources/Inputs/move_up_stick.tres"), preload("res://Resources/Inputs/run.tres"), preload("res://Resources/Inputs/spin_jump.tres"), preload("res://Resources/Inputs/slowmo_enemy.tres"), preload("res://Resources/Inputs/slowmo_world.tres")]
const SEAT_PRIMARY_STRINGS := ["dive", "jump", "move_down", "move_left", "move_right", "move_up", "run", "spin_jump", "slowmo_enemy", "slowmo_world"]
const SEAT_SECONDARY_ACTIONS := [preload("res://Resources/Inputs/move_down_pad.tres"), preload("res://Resources/Inputs/move_left_pad.tres"), preload("res://Resources/Inputs/move_right_pad.tres"), preload("res://Resources/Inputs/move_up_pad.tres"), preload("res://Resources/Inputs/jump_2.tres")]
const SEAT_SECONDARY_STRINGS := ["move_down", "move_left", "move_right", "move_up", "jump"]

## Fallbacks for seats the character-select screen left null (it overwrites
## player_characters wholesale with nulls for unclaimed seats - a mid-game
## joiner would crash on null.base_character_scene without this).
const DEFAULT_CHARACTERS := [preload("res://Resources/Characters/Mario.tres"), preload("res://Resources/Characters/Luigi.tres"), preload("res://Resources/Characters/Toad.tres"), preload("res://Resources/Characters/Toadette.tres")]

func character_for_seat(seat: int) -> CharacterResource:
	var c = player_characters.get(seat)
	if c == null:
		c = DEFAULT_CHARACTERS[clampi(seat, 0, DEFAULT_CHARACTERS.size() - 1)]
		player_characters[seat] = c   # cutscenes and next-level spawns read this
	return c

func _ready() -> void:
	# Default P1 to whichever pad is actually connected first, so a lone pad
	# on any device id (pad slot 1, hot-replug, etc.) always drives player 1.
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		assign_device_to_player(0, pads[0])
	call_deferred("_enter_view_root")

## The game world lives inside ViewRoot's GameView now: the shared camera
## must drive THAT viewport, and the world-space off-screen icons must live
## in its world to be visible.
func _enter_view_root() -> void:
	coop_camera.custom_viewport = ViewRoot.view
	for icon in off_screen_icons:
		if icon.get_parent() != ViewRoot.view:
			icon.get_parent().remove_child(icon)
			ViewRoot.view.add_child(icon)

## Strip every joypad event from a seat's actions; keyboard events survive.
func clear_seat_joypad_bindings(player_id: int) -> void:
	for base in PER_PLAYER_ACTIONS:
		var action := base + "_" + str(player_id)
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if not ev is InputEventKey:
				InputMap.action_erase_event(action, ev)

## Give player_id's seat a complete fresh binding set on the given device
## (the DeviceAssigner recipe: erase old joypad events, add stick + pad +
## alt-button events duplicated onto that device).
func assign_device_to_player(player_id: int, device: int) -> void:
	player_device_ids[player_id] = device
	clear_seat_joypad_bindings(player_id)
	if device < 0 or device == NO_DEVICE:
		return
	for idx in SEAT_PRIMARY_ACTIONS.size():
		var ev: InputEvent = SEAT_PRIMARY_ACTIONS[idx].duplicate(true)
		ev.device = device
		InputMap.action_add_event(get_player_input_str(SEAT_PRIMARY_STRINGS[idx], player_id), ev)
	for idx in SEAT_SECONDARY_ACTIONS.size():
		var ev: InputEvent = SEAT_SECONDARY_ACTIONS[idx].duplicate(true)
		ev.device = device
		InputMap.action_add_event(get_player_input_str(SEAT_SECONDARY_STRINGS[idx], player_id), ev)

## Keyboard-or-empty seat: no joypad events at all (P1 keeps default keys).
func clear_device_for_player(player_id: int) -> void:
	player_device_ids[player_id] = NO_DEVICE
	clear_seat_joypad_bindings(player_id)

func spawn_players() -> void:
	player_amount = 0
	# fresh level: everyone who sat out is back in
	parked_seats.clear()
	seat_leave_hold.clear()
	player_1 = get_first_any_player()
	await get_tree().physics_frame
	for i in players_connected - 1:
		var node = character_for_seat(i + 1).base_character_scene.instantiate()
		var id = i + 1
		node.player_id = id
		node.starting_direction = player_1.starting_direction
		node.character = character_for_seat(id)
		if is_instance_valid(player_1):
			if CoopManager.pipe_exiting:
				node.global_position = GameManager.current_level.pipes[TransitionManager.pipe_id].global_position
			else:
				node.global_position = player_1.global_position + Vector2((16 * id) * player_1.starting_direction, 0)
		GameManager.current_level.add_child(node)
		active_players[id] = node
		alive_players[id] = node
		node.camera.enabled = false
		coop_camera.enabled = true
		player_amount += 1
		if game_overed_players.has(node.player_id):
			game_overed_players[node.player_id] = node
			node.remove_from_game()
			alive_players.erase(node.player_id)
			player_amount -= 1
		elif dead_players.has(node.player_id):
			node.bubble_respawn()

func handle_pipe_exits(pipe_id := 0, direction := "") -> void:
	await get_tree().process_frame
	var pipe_players = alive_players.duplicate()
	var id := 0
	print(pipe_players)
	pipe_exiting = true
	GameManager.can_pause = false
	if is_instance_valid(GameManager.current_level.pipes.get(pipe_id)) == false:
		for i in pipe_players.values():
			i.can_crush = true
		pipe_exiting = false
		return
	var pipe: Pipe = GameManager.current_level.pipes[pipe_id]
	for i in pipe_players.values():
		if is_instance_valid(i):
			i.global_position = pipe.global_position
			i.hide()
			i.remove_from_game()
	await get_tree().create_timer(0.5).timeout
	for i in pipe_players.values():
		if is_instance_valid(i) == false:
			return
		if dead_players.has(i.player_id) == false:
			i.exit_pipe(pipe, direction)
		await get_tree().create_timer(0.5).timeout
	GameManager.can_pause = true
	players_exited_pipe.emit()
	pipe_exiting = false

func get_splitscreen_camera_offset() -> Vector2:
	match players_connected:
		2:
			return Vector2(152, 0)
		3:
			return Vector2(152, 180)
		4:
			return Vector2(152, 180)
		_:
			return Vector2.ZERO

func _process(delta: float) -> void:
	player_amount = 0
	coop_enabled = players_connected > 1
	for i in alive_players.values():
		if is_instance_valid(i):
			player_amount += 1
	camera_distance_zoom_enabled = SettingsManager.settings_file.get("coop_camera_zoom", true)
	rejoin_cooldown = maxf(rejoin_cooldown - delta, 0.0)
	handle_dropout(delta)
	# Pane cameras copy the CoopCamera recipe EXACTLY - interpolation ON,
	# physics callback, positions written from idle - because that is the one
	# camera empirically smooth in this engine build. (Streak history: idle
	# cams w/o interpolation smeared; physics-tick writes still smeared.)
	handle_splitscreen(delta)
	handle_camera(delta)
	handle_offscreen_icons()

## --- Pop-in / pop-out (drop-in co-op) --------------------------------------
## Mid-level: a pad nobody is using joins on any button press (floats in as a
## bubble next to the group). Holding SELECT ~1.2s parks your seat (character
## freezes out of the game, seat and pad stay yours); any button pops you back
## in. Parked seats reset on the next level load.

var parked_seats := {}          # seat -> Player node sitting out
var seat_leave_hold := {}       # seat -> seconds SELECT has been held
var rejoin_cooldown := 0.0

func seat_for_device(device: int) -> int:
	for seat in range(players_connected):
		if player_device_ids[seat] == device:
			return seat
	return -1

func has_keyboard_seat() -> bool:
	for seat in range(players_connected):
		if player_device_ids[seat] == NO_DEVICE:
			return true
	return false

func keyboard_seat() -> int:
	for seat in range(players_connected):
		if player_device_ids[seat] == NO_DEVICE:
			return seat
	return -1

func gameplay_input_ok() -> bool:
	if not is_instance_valid(GameManager.current_level):
		return false
	if get_tree().paused:
		return false
	if TransitionManager.changing_scene:
		return false
	if pipe_exiting:
		return false
	return true

func _input(event: InputEvent) -> void:
	if not gameplay_input_ok():
		return
	if event is InputEventJoypadButton and event.pressed:
		var seat := seat_for_device(event.device)
		# START is excluded: pressing it on an unseated pad should just pause,
		# not also spawn a surprise player in the same frame
		if seat == -1:
			if players_connected < 4 and not event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_START]:
				runtime_join(event.device)
		elif parked_seats.has(seat) and not event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_START]:
			runtime_rejoin(seat)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Keyboard can only ever be P1 (only seat 0 has key bindings), so
		# mid-level keyboard input can rejoin a parked seat but never add one.
		if event.keycode == KEY_ENTER and has_keyboard_seat():
			var seat := keyboard_seat()
			if parked_seats.has(seat):
				runtime_rejoin(seat)

func runtime_join(device: int) -> void:
	var seat := players_connected
	players_connected += 1
	if device == NO_DEVICE:
		clear_device_for_player(seat)
	else:
		assign_device_to_player(seat, device)
	player_power_states[seat] = SMALL
	spawn_one(seat)
	rejoin_cooldown = 0.6

## One mid-level spawn, mirroring spawn_players() for a single late seat.
func spawn_one(seat: int) -> void:
	if not is_instance_valid(GameManager.current_level):
		return
	var node = character_for_seat(seat).base_character_scene.instantiate()
	node.player_id = seat
	node.character = character_for_seat(seat)
	var anchor := get_first_alive_player()
	if is_instance_valid(anchor):
		node.starting_direction = anchor.starting_direction
		node.global_position = anchor.global_position
	GameManager.current_level.add_child(node)
	active_players[seat] = node
	alive_players[seat] = node
	node.camera.enabled = false
	if is_instance_valid(anchor):
		# float in as a revive bubble: no spawn-kill, lands by the group
		node.bubble_respawn()

func handle_dropout(delta: float) -> void:
	if not gameplay_input_ok():
		seat_leave_hold.clear()
		return
	if players_connected <= 1:
		return
	for seat in range(players_connected):
		var node = active_players.get(seat)
		if not is_instance_valid(node) or parked_seats.has(seat):
			continue
		var dev: int = player_device_ids[seat]
		var held := false
		if dev == NO_DEVICE:
			held = Input.is_key_pressed(KEY_TAB)
		else:
			# SELECT alone - never while START is down (that's the quit combo)
			held = Input.is_joy_button_pressed(dev, JOY_BUTTON_BACK) \
				and not Input.is_joy_button_pressed(dev, JOY_BUTTON_START)
		if held:
			seat_leave_hold[seat] = float(seat_leave_hold.get(seat, 0.0)) + delta
			if seat_leave_hold[seat] >= 1.2:
				seat_leave_hold.erase(seat)
				park_seat(seat)
		else:
			seat_leave_hold.erase(seat)

func park_seat(seat: int) -> void:
	var node = active_players.get(seat)
	if not is_instance_valid(node) or node.out_of_game:
		return
	parked_seats[seat] = node
	node.remove_from_game()
	rejoin_cooldown = 0.6

func runtime_rejoin(seat: int) -> void:
	if rejoin_cooldown > 0.0:
		return
	var node = parked_seats.get(seat)
	parked_seats.erase(seat)
	if is_instance_valid(node) and node.out_of_game:
		active_players[seat] = node
		node.bubble_respawn()

func boss_defeated(cutscene := "", secret := false) -> void:
	GameManager.star_points_goal = 0
	GameManager.course_clear.level_finish()
	MusicPlayer.play_boss_defeated_theme()
	for i in alive_players.values():
		i.state_machine.transition_to("LevelFinish", {"Boss" = true})
	await GameManager.course_clear.finished
	if cutscene != "":
		TransitionManager.transition_to_level(cutscene, GameManager.current_level)
	else:
		TransitionManager.transition_to_map(GameManager.current_map_path, GameManager.current_level, true, "", false, secret)

func handle_camera(delta: float) -> void:
	if coop_enabled == false:
		coop_camera.enabled = false
		return
	if GameManager.autoscrolling:
		return
	if splitscreen and not split_built:
		# VS mode's one-screen arenas: camera stays parked
		coop_camera.enabled = false
		return
	# NOTE: during OUR split the shared camera stays enabled on purpose - the
	# grid covers it, but get_camera_2d() consumers (bubble spawns, off-screen
	# math) still need a live main-viewport camera to anchor to.
	if is_instance_valid(GameManager.current_level):
		if is_instance_valid(GameManager.current_level.player) == false:
			return
		if is_instance_valid(coop_camera) == false:
			return
		if is_instance_valid(GameManager.current_level):
			coop_camera.limit_right = GameManager.current_level.camera_left_end_position
			coop_camera.limit_top = GameManager.current_level.camera_top_end_position + 16
			if GameManager.current_level.lock_camera:
				return
		var center_pos := Vector2.ZERO
		for i in alive_players.values():
			if is_instance_valid(i):
				i.camera.enabled = false
				center_pos += i.global_position
		coop_camera.enabled = true
		coop_camera.make_current()
		center_pos /= player_amount
		var target_position = center_pos
		if player_amount <= 1:
			var target = get_first_alive_player()
			if is_instance_valid(target) == false:
				target = get_first_active_player()
			if target == null:
				target = get_first_any_player()
			if target == null:
				return
			target_position = target.global_position
		if coop_camera.global_position.distance_to(target_position) < 16 or pipe_exiting:
			coop_camera.global_position = target_position
		else:
			coop_camera.global_position = lerp(coop_camera.global_position, target_position, delta * 20)
		# In 2P with split-screen available the split IS the spread handler
		# (SMBX-style); zoom only earns its keep in 3-4P or Single Screen mode.
		var split_handles_spread := players_connected == 2 and get_split_mode() != 2
		if camera_distance_zoom_enabled and not split_handles_spread:
			handle_distance_zoom(delta)
		else:
			coop_camera.zoom = Vector2.ONE
	else:
		coop_camera.global_position = Vector2.ZERO
		coop_camera.enabled = false

func reset_values() -> void:
	slowmo_charge = [0.0, 0.0, 0.0, 0.0]
	player_power_states = [SMALL, SMALL, SMALL, SMALL]
	game_overed_players = {}
	dead_players = {}
	player_yoshis = [false, false, false, false]

## --- SMBX-style dynamic couch split-screen (setting: coop_split_mode) ---
## Faithful port of TheXTech's DynamicScreen rules (src/graphics/gfx_screen
## .cpp): shared midpoint camera while the two players are close; the moment
## their separation along an axis reaches HALF the screen, an instant cut
## splits that axis (left player gets the left half, top gets the top, L/R
## wins ties); sides and axis re-evaluate every frame; merge is instant with
## no hysteresis; each half is rigidly locked to its player on the split axis
## and pinned to the shared average on the other axis. 2 players only:
## 3-4P stays shared screen + zoom + off-screen icons, same as TheXTech.

var split_built := false
var split_fresh := false             # just built: needs a teleport-reset
var split_vertical := false          # true = side-by-side, false = stacked
var split_cameras: Array[Camera2D] = []
var split_seats: Array[int] = []     # seat id per cell, locked at split time
var split_grid: GridContainer = null
var split_backdrop: ColorRect = null
var split_divider: ColorRect = null
var split_containers := []          # the two pane SubViewportContainers
var _parallax_cache := {}           # Parallax2D -> original repeat_times

## Screen modes, TheXTech-style: 0 = Dynamic (split only when apart),
## 1 = Always Split (stacked halves full-time), 2 = Single Screen (never).
func get_split_mode() -> int:
	return int(SettingsManager.settings_file.get("coop_split_mode", 0))

func handle_splitscreen(delta: float) -> void:
	var desired = compute_split_layout()   # null, or {vertical, seats}
	if desired == null:
		if split_built:
			teardown_splitscreen()
			SoundManager.play_ui_sound(SoundManager.select)
	elif not split_built:
		build_split_2p(desired)
		SoundManager.play_ui_sound(SoundManager.select)
	elif desired.vertical != split_vertical or desired.seats != split_seats:
		# SMBX rules: orientation/sides re-evaluate every frame and flip as an
		# instant cut (players swapping sides re-picks who owns which half)
		teardown_splitscreen()
		build_split_2p(desired)
		SoundManager.play_ui_sound(SoundManager.select)
	if split_built:
		update_split_cameras(delta)

## The two co-op bodies to frame, as [{seat, node}, ...] - alive seats first.
func get_split_pair() -> Array:
	var pair := []
	for seat in alive_players.keys():
		if is_instance_valid(alive_players[seat]):
			pair.append({"seat": seat, "node": alive_players[seat]})
	if pair.size() < 2:
		for seat in active_players.keys():
			if is_instance_valid(active_players[seat]) and not alive_players.has(seat):
				pair.append({"seat": seat, "node": active_players[seat]})
	return pair.slice(0, 2)

## The SMBX decision, run every frame. Returns null (merged / not applicable)
## or {vertical: bool, seats: [first_cell_seat, second_cell_seat]}.
## Thresholds are TheXTech's, as ratios: split when separation along an axis
## reaches half the screen; L/R beats T/B; sides are spatial; no hysteresis.
func compute_split_layout():
	var mode := get_split_mode()
	if mode == 2:
		return null
	if not coop_enabled or players_connected != 2:
		return null
	if not is_instance_valid(GameManager.current_level):
		return null
	if GameManager.autoscrolling:
		return null
	if splitscreen and not split_built:
		return null   # VS mode owns the splitscreen flag; stay out
	if GameManager.current_level.lock_camera:
		return null   # one-screen arenas never split
	var pair := get_split_pair()
	if pair.size() < 2:
		return null
	if mode == 1:
		# Always Split: fixed stacked halves, P1 on top - predictable
		var seats := [pair[0].seat, pair[1].seat] if pair[0].seat <= pair[1].seat else [pair[1].seat, pair[0].seat]
		return {"vertical": false, "seats": seats}
	var view: Vector2 = ViewRoot.view.get_visible_rect().size
	var level = GameManager.current_level
	var sec_left := -64.0
	var sec_right := float(level.camera_left_end_position)
	var sec_top := float(level.camera_top_end_position + 16)
	var sec_bottom := 64.0
	var p0: Vector2 = pair[0].node.global_position
	var p1: Vector2 = pair[1].node.global_position
	# never split along an axis the level isn't bigger than the screen on
	var can_lr := (sec_right - sec_left) > view.x
	var can_tb := (sec_bottom - sec_top) > view.y
	# SMBX's actual rule, in SCREEN space of the real (clamped) shared camera:
	# split when a player crosses the 75%/25% line while the other player is
	# far enough from that side's level edge that an edge-clamped camera could
	# not show both. Because the 75% line IS the new pane's center, the cut is
	# seamless - nobody teleports across the screen (David's death report).
	var cam_c: Vector2 = coop_camera.get_screen_center_position()
	var sx0 := (p0.x - (cam_c.x - view.x * 0.5)) / view.x
	var sx1 := (p1.x - (cam_c.x - view.x * 0.5)) / view.x
	var sy0 := (p0.y - (cam_c.y - view.y * 0.5)) / view.y
	var sy1 := (p1.y - (cam_c.y - view.y * 0.5)) / view.y
	if can_lr:
		if sx1 >= 0.75 and p0.x < sec_right - view.x * 0.75:
			return {"vertical": true, "seats": [pair[0].seat, pair[1].seat]}
		if sx0 >= 0.75 and p1.x < sec_right - view.x * 0.75:
			return {"vertical": true, "seats": [pair[1].seat, pair[0].seat]}
		if sx1 <= 0.25 and p0.x > sec_left + view.x * 0.75:
			return {"vertical": true, "seats": [pair[1].seat, pair[0].seat]}
		if sx0 <= 0.25 and p1.x > sec_left + view.x * 0.75:
			return {"vertical": true, "seats": [pair[0].seat, pair[1].seat]}
	if can_tb:
		if sy1 >= 0.75 and p0.y < sec_bottom - view.y * 0.75:
			return {"vertical": false, "seats": [pair[0].seat, pair[1].seat]}
		if sy0 >= 0.75 and p1.y < sec_bottom - view.y * 0.75:
			return {"vertical": false, "seats": [pair[1].seat, pair[0].seat]}
		if sy1 <= 0.25 and p0.y > sec_top + view.y * 0.75:
			return {"vertical": false, "seats": [pair[1].seat, pair[0].seat]}
		if sy0 <= 0.25 and p1.y > sec_top + view.y * 0.75:
			return {"vertical": false, "seats": [pair[0].seat, pair[1].seat]}
	return null

func build_split_2p(layout: Dictionary) -> void:
	var view: Vector2 = ViewRoot.view.get_visible_rect().size
	split_vertical = layout.vertical
	split_seats.assign(layout.seats)

	split_backdrop = ColorRect.new()
	split_backdrop.color = Color.BLACK
	splitscreen_canvas.add_child(split_backdrop)
	split_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)

	split_grid = GridContainer.new()
	split_grid.columns = 2 if split_vertical else 1
	split_grid.add_theme_constant_override("h_separation", 0)
	split_grid.add_theme_constant_override("v_separation", 0)
	splitscreen_canvas.add_child(split_grid)
	split_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cell := Vector2(view.x / 2.0, view.y) if split_vertical else Vector2(view.x, view.y / 2.0)
	split_cameras.clear()
	for i in 2:
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.custom_minimum_size = cell
		# panes must match the main view's look: Screen Style normally, the
		# slow-mo film grade while an effect is running
		svc.material = SlowMo.pane_look_material()
		svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		split_containers.append(svc)
		var sv := SubViewport.new()
		sv.size = Vector2i(cell)
		sv.world_2d = ViewRoot.view.world_2d
		sv.snap_2d_transforms_to_pixel = true   # same as GameView - keeps 1px lines 1px
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera2D.new()
		# SMBX rule: rigid center-lock, no smoothing, no deadzone.
		# Same interpolation recipe as the project's CoopCamera / player cams
		# (physics callback + interpolation ON) - without it the pane view
		# smears against the interpolated sprites while moving.
		cam.offset = Vector2(0, -16)
		cam.position_smoothing_enabled = false
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		cam.limit_left = -64
		cam.limit_bottom = 64
		sv.add_child(cam)
		svc.add_child(sv)
		split_grid.add_child(svc)
		cam.make_current()
		split_cameras.append(cam)

	# thin SMBX-style divider on the seam
	split_divider = ColorRect.new()
	split_divider.color = Color(0.06, 0.05, 0.08)
	splitscreen_canvas.add_child(split_divider)
	if split_vertical:
		split_divider.set_anchors_preset(Control.PRESET_CENTER)
		split_divider.anchor_top = 0.0
		split_divider.anchor_bottom = 1.0
		split_divider.offset_left = -1
		split_divider.offset_right = 1
		split_divider.offset_top = 0
		split_divider.offset_bottom = 0
	else:
		split_divider.set_anchors_preset(Control.PRESET_CENTER)
		split_divider.anchor_left = 0.0
		split_divider.anchor_right = 1.0
		split_divider.offset_top = -1
		split_divider.offset_bottom = 1
		split_divider.offset_left = 0
		split_divider.offset_right = 0

	for i in off_screen_icons:
		i.visible = false
	# widen Parallax2D repeat coverage so pane views far from the shared
	# camera still have background tiles (single-transform limitation)
	for par in GameManager.current_level.find_children("*", "Parallax2D", true, false):
		if not _parallax_cache.has(par):
			_parallax_cache[par] = par.repeat_times
			par.repeat_times = maxi(par.repeat_times, 3)
	splitscreen = true
	split_built = true
	split_fresh = true

func teardown_splitscreen() -> void:
	split_built = false
	splitscreen = false
	# disable pane cameras before freeing their viewports, or the engine
	# complains about freeing a viewport whose camera is still current
	for cam in split_cameras:
		if is_instance_valid(cam):
			cam.enabled = false
	split_cameras.clear()
	split_seats = []
	split_containers.clear()
	for par in _parallax_cache.keys():
		if is_instance_valid(par):
			par.repeat_times = _parallax_cache[par]
	_parallax_cache.clear()
	for n in [split_grid, split_backdrop, split_divider]:
		if is_instance_valid(n):
			n.queue_free()
	split_grid = null
	split_backdrop = null
	split_divider = null
	# snap the shared camera straight to the pair so the merge doesn't lerp
	# across half a level
	if is_instance_valid(coop_camera):
		var pair := get_split_pair()
		if pair.size() == 2:
			coop_camera.global_position = (pair[0].node.global_position + pair[1].node.global_position) / 2.0
			coop_camera.reset_smoothing()

func update_split_cameras(delta: float) -> void:
	if not is_instance_valid(GameManager.current_level):
		return
	var limit_right: int = GameManager.current_level.camera_left_end_position
	var limit_top: int = GameManager.current_level.camera_top_end_position + 16
	for i in split_cameras.size():
		var cam := split_cameras[i]
		if not is_instance_valid(cam):
			continue
		cam.limit_right = limit_right
		cam.limit_top = limit_top
		var target: Node2D = null
		var seat: int = split_seats[i] if i < split_seats.size() else -1
		if seat >= 0 and alive_players.has(seat) and is_instance_valid(alive_players[seat]):
			target = alive_players[seat]
		elif seat >= 0 and active_players.has(seat) and is_instance_valid(active_players[seat]):
			target = active_players[seat]
		if target == null:
			target = get_first_alive_player()
		if target == null:
			continue
		# Each pane tracks its OWN player on both axes (the SMBX shared-average
		# pinning made both halves bob with either player's jumps - nauseating,
		# per David). Rigid on the split axis, smoothed on the perpendicular
		# one so jumps don't bounce the whole view.
		var desired := target.global_position
		var pos := cam.global_position
		if split_fresh:
			pos = desired
		elif split_vertical:
			pos.x = desired.x
			pos.y = lerpf(pos.y, desired.y, minf(delta * 8.0, 1.0))
		else:
			pos.y = desired.y
			pos.x = lerpf(pos.x, desired.x, minf(delta * 8.0, 1.0))
		cam.global_position = pos
		if split_fresh:
			# first placement is a teleport, not motion - don't let the
			# interpolator smear the pane from its spawn transform
			cam.reset_physics_interpolation()
	if split_fresh:
		split_fresh = false

func handle_distance_zoom(delta: float) -> void:
	var player_dists = []
	for i in active_players.values():
		if is_instance_valid(i):
			player_dists.append(coop_camera.to_local(i.global_position))
	if player_dists.size() < 2:
		coop_camera.zoom = lerp(coop_camera.zoom, Vector2.ONE, delta * 20)
		return
	var max_dist: Vector2 = player_dists.max()
	var min_dist: Vector2 = player_dists.min()
	var distance := min_dist.distance_to(max_dist)
	var target_zoom := 350.0 / maxf(distance, 1.0)
	# Floor at 0.6: past ~1.6x view the sprites are unreadable from a couch;
	# beyond that spread the off-screen icons take over anyway.
	target_zoom = clamp(target_zoom, 0.6, 1.0)
	coop_camera.zoom = lerp(coop_camera.zoom, Vector2(target_zoom, target_zoom), delta * 20)

## --- Slow-mo charge (per seat, 0-100) --------------------------------
## Coins and enemy defeats feed each player's meter; the SlowMo autoload
## consumes it. Persists across levels; resets with the run.
const SLOWMO_COIN_CHARGE := 4.0
const SLOWMO_KILL_CHARGE := 10.0
var slowmo_charge := [0.0, 0.0, 0.0, 0.0]

func add_slowmo_charge(player_id: int, amount: float) -> void:
	if player_id < 0 or player_id > 3:
		return
	slowmo_charge[player_id] = clampf(slowmo_charge[player_id] + amount, 0.0, 100.0)

## Credit whoever `who` resolves to: a Player, something with a .player,
## else the closest player to pos. GameManager.player is always null in
## this codebase - never consult it.
func slowmo_credit(who, pos := Vector2.ZERO, amount := SLOWMO_COIN_CHARGE) -> void:
	var p = null
	if who is Player:
		p = who
	elif who != null and is_instance_valid(who) and "player" in who and who.player is Player:
		p = who.player
	if p == null or not is_instance_valid(p):
		p = get_closest_player(pos)
	if p == null or not is_instance_valid(p):
		p = get_first_alive_player()
	if p != null and is_instance_valid(p):
		add_slowmo_charge(p.player_id, amount)

func get_player_input_str(action, player_id) -> String:
	return action + "_" + str(player_id)

func get_first_any_player() -> Player:
	for i in players.values():
		if is_instance_valid(i):
			return i
	return null

func get_first_active_player() -> Player:
	for i in active_players.values():
		if is_instance_valid(i):
			return i
	return null

func get_first_alive_player() -> Player:
	for i in alive_players.values():
		if is_instance_valid(i):
			return i
	return null

func get_closest_player(point := Vector2.ZERO) -> Player:
	var player: Player = null
	var distances := []
	for i in alive_players.values():
		if is_instance_valid(i):
			distances.append(point.distance_to(i.global_position))
	if distances.is_empty() == false:
		return alive_players.values()[distances.find(distances.min())]
	if is_instance_valid(player) == false:
		player = get_first_any_player()
	return player

func handle_offscreen_icons() -> void:
	if splitscreen:
		return
	if players_connected == 1:
		return
	if GameManager.secret_clear:
		return
	if is_instance_valid(GameManager.current_level) == false or players_connected > 1:
		for i in off_screen_icons:
			i.visible = false
	var player_index := 0
	for player in players.values():
		if is_instance_valid(player) == false:
			break
		var icon = off_screen_icons[player_index]
		icon.visible = not player.on_screen_notifier.is_on_screen() and not player.dead and not pipe_exiting and not player.out_of_game and player.state_machine.state.name.contains("Pipe") == false
		var player_sprite = icon.get_node("Sprite")
		player_sprite.sprite_frames = load("res://Resources/PlayerSpriteFrames/" + player.character.character_name + "/" + player.power_state.sprite_frame_name+ ".tres")
		if player_sprite.sprite_frames.has_animation(player.sprite.animation):
			player_sprite.play(player.sprite.animation)
		player_sprite.speed_scale = player.sprite.speed_scale
		player_sprite.scale.x = 0.75 * player.sprite.scale.x
		icon.global_position = player.global_position
		var cam_pos = coop_camera.get_screen_center_position()
		var extents = cam_pos
		icon.global_position.x = clamp(icon.global_position.x, cam_pos.x - 224, cam_pos.x + 224)
		icon.global_position.y = clamp(icon.global_position.y, cam_pos.y - 119, cam_pos.y + 119)
		player_index += 1

func setup_players() -> void:
	spawn_players()
	for i in players.values():
		pass

func call_to_players(player_list := {}, call := _ready) -> void:
	for i in player_list.values():
		i.call(call)

func wait_for_players(wait_time := 5) -> void:
	wait_finished_players.clear()
	waiting = true
	await get_tree().create_timer(wait_time, false).timeout
	if waiting == false:
		return
	waiting = false
	wait_finished.emit()

func add_wait_player(player: Player) -> void:
	wait_finished_players.append(player)
	if wait_finished_players.size() >= alive_players.size():
		await get_tree().physics_frame
		waiting = false
		wait_finished.emit()
