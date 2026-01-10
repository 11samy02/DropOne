extends Node

func _ready() -> void:
	print("✅ Starting server...")
	NetworkManager.start_server(NetworkManager.DEFAULT_PORT)
	print("✅ Server started!")
