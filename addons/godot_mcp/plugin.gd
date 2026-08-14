@tool
extends EditorPlugin

const AUTOLOADS: Array[Array] = [
	["autoload/MCPRuntimeBridge", "res://addons/godot_mcp/services/mcp_runtime_bridge.gd"],
	["autoload/MCPInputBridge", "res://addons/godot_mcp/services/mcp_input_bridge.gd"],
	["autoload/MCPScreenshotBridge", "res://addons/godot_mcp/services/mcp_screenshot_bridge.gd"],
]

var _websocket_client: Node
var _command_router: Node
var _injected: Array[String] = []
var auto_dismiss_dialogs: bool = false


func _enter_tree() -> void:
	_inject_autoloads()
	_command_router = preload("res://addons/godot_mcp/command_router.gd").new()
	_command_router.name = "MCPCommandRouter"
	_command_router.editor_plugin = self
	add_child(_command_router)

	_websocket_client = preload("res://addons/godot_mcp/websocket_client.gd").new()
	_websocket_client.name = "MCPWebSocketClient"
	_websocket_client.command_router = _command_router
	add_child(_websocket_client)
	_websocket_client.start()
	print("[Godot MCP] Plugin started")


func _exit_tree() -> void:
	_remove_autoloads()
	if _websocket_client:
		_websocket_client.stop()
		_websocket_client.queue_free()
	if _command_router:
		_command_router.queue_free()
	print("[Godot MCP] Plugin stopped")


func _process(_delta: float) -> void:
	if not auto_dismiss_dialogs:
		return
	var base_control := get_editor_interface().get_base_control()
	if base_control:
		_dismiss_dialogs(base_control)


func _dismiss_dialogs(node: Node) -> void:
	if node is AcceptDialog and node.visible:
		node.hide()
	for child in node.get_children():
		_dismiss_dialogs(child)


func _inject_autoloads() -> void:
	_injected.clear()
	var changed := false
	for entry in AUTOLOADS:
		var key: String = entry[0]
		var script: String = entry[1]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, "*" + script)
			_injected.append(key)
			changed = true
	if changed:
		ProjectSettings.save()


## Removes our autoloads, whether or not this editor session is the one that put
## them there.
##
## This used to iterate _injected, which only records a key _inject_autoloads
## actually had to create. Reopen the editor with the plugin already enabled and
## the settings are already present, so nothing is recorded — and disabling the
## plugin then left all three autoloads sitting in project.godot. From there they
## ride into commits, and into exported builds: an editor-only remote-control
## channel shipped to players.
##
## Matched on the script path rather than the setting name, so a project with its
## own autoload that happens to share a name keeps it.
func _remove_autoloads() -> void:
	var changed := false
	for entry in AUTOLOADS:
		var key: String = entry[0]
		var script: String = entry[1]
		if not ProjectSettings.has_setting(key):
			continue
		if str(ProjectSettings.get_setting(key)).trim_prefix("*") != script:
			continue # someone else's autoload under the same name — leave it alone
		ProjectSettings.set_setting(key, null)
		changed = true
	_injected.clear()
	if changed:
		ProjectSettings.save()
