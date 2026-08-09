
extends Node2D

@export_enum("Left", "Right") var direction := "Right"
@onready var animation: AnimationPlayer = $Animation

func _ready() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
	for i in 10:
		print(direction)
		await get_tree().physics_frame
		animation.play(direction)
