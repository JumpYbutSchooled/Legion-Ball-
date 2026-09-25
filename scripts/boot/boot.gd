extends Control
## Boot + auto-updater. This is the one part of the game that can never be updated, so it
## is kept small, self-contained and preloads nothing (anything loaded before the update
## is mounted would stay the old version).
##
## 1. Mounts the newest downloaded update (user://patch/<name>.pck) over the base game.
## 2. Asks GitHub for the latest release; if its tag is newer than the running version,
##    downloads its game.pck asset and mounts that too.
## 3. Creates the game services (scripts/services.gd) and opens the main menu.
## Offline, rate-limited or broken downloads just fall through to step 3.

## "owner/repo" of the public GitHub repository that holds the releases.
const REPO := "JumpYbutSchooled/Legion-Ball-"
const ASSET_NAME := "game.pck"
const PATCH_DIR := "user://patch/"
const CURRENT_FILE := "user://patch/current.txt"
const MENU_SCENE := "res://scenes/menu.tscn"
const USER_AGENT := "LeigonBall-Updater"

var _status: Label
var _bar: ProgressBar
var _request: HTTPRequest


func _ready() -> void:
	_build_ui()
	_mount_current_patch()
	_run.call_deferred()


func _run() -> void:
	print("[boot] running v%s (patch: %s)" % [_local_version(), _read_text(CURRENT_FILE).strip_edges()])
	if REPO != "" and not OS.has_feature("editor"):
		await _check_for_update()
	print("[boot] starting v%s" % _local_version())
	_status.text = "STARTING  v" + _local_version()
	await get_tree().process_frame
	load("res://scripts/services.gd").ensure(get_tree())
	get_tree().change_scene_to_file(MENU_SCENE)


func _process(_delta: float) -> void:
	if _request and _request.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := _request.get_body_size()
		if total > 0:
			_bar.value = float(_request.get_downloaded_bytes()) / total * 100.0


# --- Local patch ----------------------------------------------------------------

func _mount_current_patch() -> void:
	DirAccess.make_dir_recursive_absolute(PATCH_DIR)
	var current := _read_text(CURRENT_FILE).strip_edges()
	# A patch no newer than this install is a leftover from before a reinstall with a
	# newer zip; mounting it would drag the game back to the old version.
	var base := _local_version()
	if current != "" and not _is_newer(_patch_version(current), base):
		print("[boot] ignoring old patch %s (installed game is v%s)" % [current, base])
		current = ""
		var marker := FileAccess.open(CURRENT_FILE, FileAccess.WRITE)
		if marker:
			marker.store_string("")
			marker.close()
	# Clear out old patches (none are mounted yet, so nothing is locked).
	for file in DirAccess.get_files_at(PATCH_DIR):
		if file.ends_with(".pck") and file != current:
			DirAccess.remove_absolute(PATCH_DIR + file)
	if current != "" and FileAccess.file_exists(PATCH_DIR + current):
		if not ProjectSettings.load_resource_pack(PATCH_DIR + current, true):
			push_warning("Updater: could not mount " + current)


## "game_0_7_13.pck" -> "0.7.13".
func _patch_version(file_name: String) -> String:
	return file_name.trim_prefix("game_").trim_suffix(".pck").replace("_", ".")


func _local_version() -> String:
	var v := _read_text("res://version.txt").strip_edges()
	return v if v != "" else "0.0.0"


# --- Remote update --------------------------------------------------------------

func _check_for_update() -> void:
	_status.text = "CHECKING FOR UPDATES"
	var api := "https://api.github.com/repos/%s/releases/latest" % REPO
	var result := await _http_get(api, 15.0)
	if result.is_empty() or result["code"] != 200:
		if not result.is_empty():
			# 403 here is usually GitHub's limit of 60 checks an hour per network.
			print("[boot] update check: HTTP %d from GitHub" % result["code"])
		_status.text = "UPDATE SERVER UNREACHABLE"
		return
	var release = JSON.parse_string((result["body"] as PackedByteArray).get_string_from_utf8())
	if typeof(release) != TYPE_DICTIONARY:
		return
	var remote := String(release.get("tag_name", "")).trim_prefix("v")
	if remote == "" or not _is_newer(remote, _local_version()):
		print("[boot] up to date (latest release v%s)" % remote)
		_status.text = "UP TO DATE"
		return
	var url := ""
	for asset in release.get("assets", []):
		if asset.get("name", "") == ASSET_NAME:
			url = asset.get("browser_download_url", "")
	if url == "":
		return

	_status.text = "DOWNLOADING UPDATE  v" + remote
	_bar.visible = true
	print("[boot] downloading v%s from %s" % [remote, url])
	var download := await _http_get(url, 120.0)
	if download.is_empty() or download["code"] != 200:
		if not download.is_empty():
			print("[boot] download: HTTP %d" % download["code"])
		_status.text = "UPDATE FAILED - CONTINUING"
		return
	var file_name := "game_%s.pck" % remote.replace(".", "_")
	var file := FileAccess.open(PATCH_DIR + file_name, FileAccess.WRITE)
	if not file:
		return
	file.store_buffer(download["body"])
	file.close()
	if ProjectSettings.load_resource_pack(PATCH_DIR + file_name, true):
		var marker := FileAccess.open(CURRENT_FILE, FileAccess.WRITE)
		marker.store_string(file_name)
		marker.close()
		_status.text = "UPDATED TO v" + remote


## GETs a URL (following redirects). Returns {code, body} or {} on failure.
func _http_get(url: String, timeout: float) -> Dictionary:
	_request = HTTPRequest.new()
	_request.timeout = timeout
	_request.max_redirects = 8
	add_child(_request)
	var err := _request.request(url, ["User-Agent: " + USER_AGENT, "Accept: application/vnd.github+json"])
	if err != OK:
		print("[boot] could not start request to %s (error %d)" % [url, err])
		_request.queue_free()
		_request = null
		return {}
	var response: Array = await _request.request_completed
	_request.queue_free()
	_request = null
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		# Logged so a player's godot.log says why updating failed. TLS errors usually
		# mean a wrong PC clock or a school/work network inspecting HTTPS.
		var reasons := {
			HTTPRequest.RESULT_CANT_CONNECT: "can't connect",
			HTTPRequest.RESULT_CANT_RESOLVE: "can't resolve host (no internet or DNS blocked)",
			HTTPRequest.RESULT_CONNECTION_ERROR: "connection error",
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS handshake failed (PC clock wrong, or network inspecting HTTPS)",
			HTTPRequest.RESULT_TIMEOUT: "timed out",
			HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "too many redirects",
		}
		print("[boot] request to %s failed: %s (result %d)" % [url, reasons.get(response[0], "error"), response[0]])
		return {}
	return {"code": response[1], "body": response[3]}


## True if version a is newer than b ("1.2.10" > "1.2.9").
func _is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


# --- Splash --------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.position = Vector2(-210, -40)
	add_child(box)
	var title := Label.new()
	title.text = "LEIGON BALL"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_status = Label.new()
	_status.text = "BOOTING"
	_status.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.visible = false
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(_bar)
