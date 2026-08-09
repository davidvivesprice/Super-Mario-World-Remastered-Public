extends CharacterBody2D

@export var move_speed := 50
var direction := -1

func _physics_process(delta: float) -> void:
	if is_on_wall():
		direction *= -1
	velocity.y += 15
	velocity.x = move_speed * direction
	move_and_slide()

func _enter_tree() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
