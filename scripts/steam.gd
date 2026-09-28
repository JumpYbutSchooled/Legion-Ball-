extends Node
## Steam (/root/Steamworks, created by services.gd), through the GodotSteam add-on
## (addons/godotsteam). Does nothing unless the add-on loaded AND Steam is running with
## this game: GitHub builds, the dedicated servers and practice without Steam all carry
## on exactly as before.
## unlock(id) sets an achievement (each one also needs adding, with the same API name, in
## the Steamworks partner site: see ACHIEVEMENTS). Steam builds (the "steam" export
## feature) also skip the GitHub auto-updater (boot.gd): Steam updates the game itself.

## The game's Steam App ID. 480 is Valve's test app (Spacewar), for testing before the real
## one exists: change it here (and in steam_appid.txt next to the exe) when it does.
const APP_ID := 480

## Achievement API names, and what each is for (make them in Steamworks with these names).
const ACHIEVEMENTS := {
	"FIRST_BLOOD": "Get your first kill online.",
	"KILLSTREAK_5": "Get 5 kills in a row without dying.",
	"WIN_MATCH": "Win a match.",
	"KING_OF_THE_HILL": "Win a King of the Hill round.",
	"GUN_GAME": "Win a Gun Game.",
	"JUGGERNAUT": "Win a Juggernaut match.",
	"INFINITY": "Hit the top speed tier (the infinity dial).",
	"PARRY": "Parry a shot with your shield.",
	"RIFT_WALKER": "Travel through a rift.",
	"NO_CLIP": "Visit every level of the Backrooms.",
}

var active := false
var _steam: Object = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or not Engine.has_singleton("Steam"):
		return
	_steam = Engine.get_singleton("Steam")
	if not _steam.call("isSteamRunning"):
		_steam = null
		return
	var result = _steam.call("steamInitEx", APP_ID, false)
	var ok: bool = typeof(result) == TYPE_DICTIONARY and int(result.get("status", 1)) == 0
	if not ok:
		push_warning("Steam didn't start: %s" % str(result))
		_steam = null
		return
	active = true
	print("[steam] signed in as %s" % _steam.call("getPersonaName"))
	# First time on Steam with the default name: use the Steam name.
	var settings := get_tree().root.get_node_or_null("Settings")
	if settings and String(settings.call("get_value", "player_name")) == "PLAYER":
		settings.call("set_value", "player_name", persona_name().substr(0, 16))


func _process(_delta: float) -> void:
	if active:
		_steam.call("run_callbacks")


## The player's Steam name, or "" without Steam (the menu uses it as the default name).
func persona_name() -> String:
	return String(_steam.call("getPersonaName")) if active else ""


## Unlocks achievement `id` (ACHIEVEMENTS). Safe to call any number of times, with or
## without Steam.
func unlock(id: String) -> void:
	if not active or not ACHIEVEMENTS.has(id):
		return
	var have = _steam.call("getAchievement", id)
	if typeof(have) == TYPE_DICTIONARY and have.get("achieved", false):
		return
	_steam.call("setAchievement", id)
	_steam.call("storeStats")


## True on a Steam Deck (Steam sets this for every game it starts there).
static func on_steam_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1"


## Anywhere: unlock achievement `id` if Steam's there (no-op otherwise).
static func achieve(tree: SceneTree, id: String) -> void:
	var node := tree.root.get_node_or_null("Steamworks") if tree else null
	if node:
		node.call("unlock", id)
