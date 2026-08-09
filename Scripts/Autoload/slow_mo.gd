extends Node
## Slow-mo powerups (David's design, 2026-08-09).
## Charge your meter with coins (+4) and enemy defeats (+10); a full bar arms.
## L3 (click left stick) = ENEMY slow-mo: every enemy runs at half speed.
## R3 (click right stick) = WORLD slow-mo: everything drops into syrup.
## An effect drains the owner's bar over ~15 s - but charge earned during the
## effect refills the bar, directly extending it. Keyboard seat: V / B.
##
## Enemy mode mechanism: every Enemy-derived node (group "enemies", enrolled
## by EnemyClass._enter_tree) is process-frozen on alternate physics frames -
## exact half speed for motion, AI, child timers and animation, zero
## per-enemy edits. Hardened per audit: child collision objects switch to
## DISABLE_MODE_KEEP_ACTIVE while active (no area_entered churn), only nodes
## we froze get unfrozen (meta tag - never fights VisibleOnScreenEnabler2D or
## the ice block), ice-frozen / yoshi-tongued enemies are skipped.
## World mode: Engine.time_scale (the credits are the only other user), plus
## a pitch-shift on the Music bus for the syrup feel.

const DRAIN_PER_SEC := 100.0 / 15.0    # full bar = 15 s (David's number)
const WORLD_TIME_SCALE := 0.5
const MUSIC_PITCH := 0.85

const SFX_IN := preload("res://Assets/Audio/SFX/slowmo_in.wav")
const SFX_OUT := preload("res://Assets/Audio/SFX/slowmo_out.wav")

var enemy_seat := -1     # seat that owns the active enemy slow-mo (-1 = off)
var world_seat := -1
var _area_cache := {}    # CollisionObject2D -> original disable_mode
var _pitch_fx: AudioEffectPitchShift = null

func _physics_process(delta: float) -> void:
	# world mode scales delta; drain and countdown in real time
	var real_delta := delta / maxf(Engine.time_scale, 0.05)
	if _gameplay_ok():
		_poll_activation()
	_run_drain(real_delta)
	if enemy_seat >= 0:
		_freeze_tick()

func _gameplay_ok() -> bool:
	if not SettingsManager.settings_file.get("slowmo_powerups", true):
		return false
	if not is_instance_valid(GameManager.current_level):
		return false
	if GameManager.vs_mode or TransitionManager.changing_scene:
		return false
	return true

func _poll_activation() -> void:
	for seat in range(CoopManager.players_connected):
		var node = CoopManager.alive_players.get(seat)
		if not is_instance_valid(node):
			continue
		if CoopManager.slowmo_charge[seat] < 100.0:
			continue
		if enemy_seat == -1 and Input.is_action_just_pressed(CoopManager.get_player_input_str("slowmo_enemy", seat)):
			_start_enemy(seat)
		elif world_seat == -1 and Input.is_action_just_pressed(CoopManager.get_player_input_str("slowmo_world", seat)):
			_start_world(seat)

func _run_drain(real_delta: float) -> void:
	if enemy_seat >= 0:
		CoopManager.slowmo_charge[enemy_seat] = maxf(CoopManager.slowmo_charge[enemy_seat] - DRAIN_PER_SEC * real_delta, 0.0)
		if CoopManager.slowmo_charge[enemy_seat] <= 0.0 or not _gameplay_ok():
			_end_enemy()
	if world_seat >= 0:
		CoopManager.slowmo_charge[world_seat] = maxf(CoopManager.slowmo_charge[world_seat] - DRAIN_PER_SEC * real_delta, 0.0)
		if CoopManager.slowmo_charge[world_seat] <= 0.0 or not _gameplay_ok():
			_end_world()

func _start_enemy(seat: int) -> void:
	enemy_seat = seat
	SoundManager.play_ui_sound(SFX_IN)

func _end_enemy() -> void:
	enemy_seat = -1
	SoundManager.play_ui_sound(SFX_OUT)
	_thaw_all()

func _start_world(seat: int) -> void:
	world_seat = seat
	Engine.time_scale = WORLD_TIME_SCALE
	SoundManager.play_ui_sound(SFX_IN)
	_music_pitch(MUSIC_PITCH)

func _end_world() -> void:
	world_seat = -1
	Engine.time_scale = 1.0
	SoundManager.play_ui_sound(SFX_OUT)
	_music_pitch(1.0)

## ---- enemy-mode freeze loop ------------------------------------------------

func _freeze_tick() -> void:
	var off_frame := (Engine.get_physics_frames() & 1) == 1
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# never fight the ice block, yoshi's tongue, or held/item forms
		if e.get("frozen") == true or e.get("is_yoshi_item") == true:
			continue
		var y = e.get("yoshi")
		if y != null and is_instance_valid(y):
			continue
		if off_frame:
			if e.process_mode != Node.PROCESS_MODE_DISABLED:
				_keep_areas_active(e)
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.set_meta("slowmo_off", true)
		else:
			if e.has_meta("slowmo_off"):
				e.process_mode = Node.PROCESS_MODE_INHERIT
				e.remove_meta("slowmo_off")

## While frozen on off-frames, hit/hurt areas must stay in the physics space
## or area_entered re-fires every re-add (double damage/stomps). Cache the
## original disable modes and restore on thaw.
func _keep_areas_active(e: Node) -> void:
	if e.has_meta("slowmo_areas_prepped"):
		return
	e.set_meta("slowmo_areas_prepped", true)
	for child in e.find_children("*", "CollisionObject2D", true, false):
		if not _area_cache.has(child):
			_area_cache[child] = child.disable_mode
			child.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE

func _thaw_all() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_meta("slowmo_off"):
			e.process_mode = Node.PROCESS_MODE_INHERIT
			e.remove_meta("slowmo_off")
		if e.has_meta("slowmo_areas_prepped"):
			e.remove_meta("slowmo_areas_prepped")
	for child in _area_cache.keys():
		if is_instance_valid(child):
			child.disable_mode = _area_cache[child]
	_area_cache.clear()

## ---- music pitch (world mode) ----------------------------------------------

func _music_pitch(pitch: float) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus == -1:
		return
	if pitch == 1.0:
		if _pitch_fx != null:
			for i in AudioServer.get_bus_effect_count(bus):
				if AudioServer.get_bus_effect(bus, i) == _pitch_fx:
					AudioServer.remove_bus_effect(bus, i)
					break
			_pitch_fx = null
	else:
		if _pitch_fx == null:
			_pitch_fx = AudioEffectPitchShift.new()
			AudioServer.add_bus_effect(bus, _pitch_fx)
		_pitch_fx.pitch_scale = pitch
