extends Node

@export var path: Path2D = null
@export var scroll_speed := 5.0

var can_die := false
@onready var walls: StaticBody2D = $Path/FollowJoint/Follow/Camera/Walls

@onready var path_node: Path2D = $Path
@onready var follow_joint: PathFollow2D = $Path/FollowJoint
@onready var camera: Camera2D = $Path/FollowJoint/Follow/Camera

func _exit_tree() -> void:
	GameManager.autoscrolling = false

func _ready() -> void:
	add_to_group("slowmo_autoscroll")   # slow-mo halves scroll_speed instead of freezing the camera
	if SettingsManager.settings_file.disable_auto_scroll == true:
		# Autoscroll disabled (couch-co-op mercy setting): never take over the
		# camera or mark the level as autoscrolling; leave the walls inert.
		camera.enabled = false   # order-independent: our camera must never win
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	GameManager.autoscrolling = true
	path_node.curve = path.curve.duplicate()
	follow_joint.progress_ratio = 0
	await get_tree().physics_frame
	walls.set_collision_layer_value(1, true)
	get_viewport().get_camera_2d().enabled = false
	
	camera.enabled = true
	await get_tree().create_timer(1).timeout
	can_die = true

func _physics_process(delta: float) -> void:
	CoopManager.coop_camera.enabled = false
	follow_joint.progress += (scroll_speed) * delta
	camera.make_current()

func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player and can_die:
		area.get_parent().die()
