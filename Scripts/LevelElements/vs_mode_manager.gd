extends Node

func _ready() -> void:
	CoopManager.players_connected = clamp(CoopManager.players_connected, 2, 4)
	CoopManager.splitscreen = true
	GameManager.vs_mode = true

func _exit_tree() -> void:
	# Without this, one VS match latched splitscreen/vs_mode true for the whole
	# session - killing the co-op camera, dynamic split, off-screen icons and
	# positional SFX in every later level (audit finding, 2026-08-09).
	CoopManager.splitscreen = false
	GameManager.vs_mode = false
