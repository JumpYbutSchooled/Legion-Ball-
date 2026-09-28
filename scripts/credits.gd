extends Node
## The credits (menu CREDITS page). Owners can change them from inside the game, without
## an update:
## - Every game ships res://credits.json as a fallback, and keeps the newest copy it has
##   seen in user://credits_cache.json.
## - fetch() downloads the live copy from the repo's "credits" branch (a separate branch,
##   so changing credits never redeploys the servers or clashes with releases).
## - An owner's edit goes to the hub (scripts/net/menu_chat.gd -> global_relay.gd), which
##   checks their code against OWNER_CODE and commits the new file to that branch using
##   the server's GITHUB_TOKEN. Players never hold a token.
## Stored as {"sections": [{"title": "OWNER", "names": ["JumpY"]}, ...]}.

signal updated

const REPO := "JumpYbutSchooled/Legion-Ball-"
const BRANCH := "credits"
const FILE := "credits.json"
const BUNDLED := "res://credits.json"
const CACHE := "user://credits_cache.json"
const MAX_SECTIONS := 30
const MAX_NAMES := 40
const MAX_TEXT := 4000

var _request: HTTPRequest


## The newest credits this game has: the cached live copy, else the shipped one.
static func current() -> Array:
	for path in [CACHE, BUNDLED]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var sections := from_json(f.get_as_text())
			if not sections.is_empty():
				return sections
	return []


## Sections from the stored JSON, cleaned. [] if it isn't valid.
static func from_json(text: String) -> Array:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("sections")) != TYPE_ARRAY:
		return []
	var out: Array = []
	for s in data["sections"]:
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("names")) != TYPE_ARRAY:
			continue
		var names: Array = []
		for n in s["names"]:
			var who := _clean(String(n), 48)
			if who != "" and names.size() < MAX_NAMES:
				names.append(who)
		var title := _clean(String(s.get("title", "")), 40).to_upper()
		if title != "" and out.size() < MAX_SECTIONS:
			out.append({"title": title, "names": names})
	return out


static func to_json(sections: Array) -> String:
	return JSON.stringify({"sections": sections}, "\t") + "\n"


## Editor text, one section a line: "TITLE: name, name, name".
static func to_text(sections: Array) -> String:
	var lines := PackedStringArray()
	for s in sections:
		lines.append("%s: %s" % [s["title"], ", ".join(PackedStringArray(s["names"]))])
	return "\n".join(lines)


## Sections from editor text. Lines without a ":" are skipped.
static func from_text(text: String) -> Array:
	var sections: Array = []
	for line in text.substr(0, MAX_TEXT).split("\n"):
		var colon := line.find(":")
		if colon < 0:
			continue
		var names: Array = []
		for n in line.substr(colon + 1).split(","):
			names.append(n)
		sections.append({"title": line.substr(0, colon), "names": names})
	return from_json(to_json(sections))


static func _clean(text: String, cap: int) -> String:
	return text.replace("\n", " ").replace("\r", " ").replace("[", "(").replace("]", ")").strip_edges().substr(0, cap)


## Saves a newer copy (from the repo, or the hub after an owner's edit) and says so.
func store(sections: Array) -> void:
	if sections.is_empty():
		return
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(to_json(sections))
		f.close()
	updated.emit()


## Downloads the live credits in the background; emits updated if they arrive.
func fetch() -> void:
	if _request:
		return
	_request = HTTPRequest.new()
	_request.timeout = 10.0
	add_child(_request)
	_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		_request.queue_free()
		_request = null
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var sections := from_json(body.get_string_from_utf8())
		if not sections.is_empty() and to_json(sections) != to_json(current()):
			store(sections))
	var url := "https://api.github.com/repos/%s/contents/%s?ref=%s" % [REPO, FILE, BRANCH]
	if _request.request(url, ["User-Agent: Ballistic", "Accept: application/vnd.github.raw+json"]) != OK:
		_request.queue_free()
		_request = null
