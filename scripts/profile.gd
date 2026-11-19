extends Node
## The player's career (/root/Profile, created by scripts/services.gd): experience and
## level, lifetime stats, medals earned, daily challenges, best time-trial runs, and the
## cosmetics picked in the Locker. Kept in user://profile.cfg on this computer (written to
## a temporary file and swapped in, the last good copy kept as .bak, like the settings).
##
## Everything that happens in a match reaches it through three calls:
##   award(xp, reason)        experience (levels up, and says so with `leveled_up`)
##   add_stat(key, amount)    a lifetime counter (also moves any challenge counting it)
##   best_stat(key, value)    a lifetime record (kept if higher)
## scripts/match_tracker.gd turns what happens in the arena into those. Nothing here
## changes how the game plays: levels unlock looks (ball skins and trails), never power.

signal xp_gained(amount: int, reason: String)
signal leveled_up(level: int)
signal medal_earned(id: String)
signal challenge_done(challenge: Dictionary)
signal changed

const PATH := "user://profile.cfg"
const MAX_LEVEL := 100
## Experience from level n to n + 1: NEED_BASE + NEED_STEP * (n - 1).
const NEED_BASE := 600
const NEED_STEP := 200
## Seconds between saves while things are changing (and always on leaving a match).
const SAVE_EVERY := 20.0

## Ranks: the level each starts at, its name and colour.
const RANKS := [
	[1, "RECRUIT", Color(0.62, 0.7, 0.76)],
	[5, "PILOT", Color(0.45, 0.85, 1.0)],
	[10, "STRIKER", Color(0.45, 1.0, 0.6)],
	[20, "ACE", Color(1.0, 0.85, 0.3)],
	[30, "VETERAN", Color(1.0, 0.6, 0.2)],
	[40, "ELITE", Color(1.0, 0.35, 0.35)],
	[50, "MASTER", Color(1.0, 0.4, 0.85)],
	[65, "CHAMPION", Color(0.75, 0.55, 1.0)],
	[80, "LEGEND", Color(0.5, 0.95, 0.95)],
	[100, "BALLISTIC", Color(1.0, 1.0, 1.0)],
]

## Medals: what they're called, what they're worth and how they're earned (the tracker
## decides when). `tier` orders them when several land at once (biggest first).
const MEDALS := {
	"first_blood": {"name": "FIRST BLOOD", "xp": 100, "color": Color(1.0, 0.3, 0.3), "tier": 3, "how": "The first kill of the match."},
	"double": {"name": "DOUBLE KILL", "xp": 75, "color": Color(0.45, 0.85, 1.0), "tier": 2, "how": "Two kills within four seconds."},
	"triple": {"name": "TRIPLE KILL", "xp": 150, "color": Color(0.45, 1.0, 0.6), "tier": 3, "how": "Three kills, each within four seconds of the last."},
	"quad": {"name": "QUAD KILL", "xp": 250, "color": Color(1.0, 0.85, 0.3), "tier": 4, "how": "Four kills, each within four seconds of the last."},
	"rampage": {"name": "RAMPAGE", "xp": 400, "color": Color(1.0, 0.4, 0.85), "tier": 5, "how": "Five or more kills, each within four seconds of the last."},
	"spree": {"name": "KILLING SPREE", "xp": 150, "color": Color(1.0, 0.6, 0.2), "tier": 3, "how": "Five kills without dying."},
	"unstoppable": {"name": "UNSTOPPABLE", "xp": 300, "color": Color(1.0, 0.35, 0.35), "tier": 4, "how": "Ten kills without dying."},
	"godlike": {"name": "GODLIKE", "xp": 600, "color": Color(1.0, 1.0, 1.0), "tier": 5, "how": "Fifteen kills without dying."},
	"long_shot": {"name": "LONG SHOT", "xp": 75, "color": Color(1.0, 0.6, 0.15), "tier": 1, "how": "A kill from more than 150 m away."},
	"point_blank": {"name": "POINT BLANK", "xp": 50, "color": Color(1.0, 0.25, 0.75), "tier": 1, "how": "A kill from less than 6 m away."},
	"airborne": {"name": "DEATH FROM ABOVE", "xp": 75, "color": Color(0.3, 0.95, 0.5), "tier": 1, "how": "A kill while you're in the air."},
	"speed_demon": {"name": "SPEED DEMON", "xp": 100, "color": Color(0.2, 0.9, 0.95), "tier": 2, "how": "A kill while going faster than 300."},
	"revenge": {"name": "REVENGE", "xp": 75, "color": Color(0.95, 0.2, 0.25), "tier": 1, "how": "Kill whoever killed you last."},
	"shutdown": {"name": "SHUTDOWN", "xp": 125, "color": Color(0.75, 0.55, 1.0), "tier": 2, "how": "End someone's streak of five or more."},
	"comeback": {"name": "COMEBACK", "xp": 100, "color": Color(0.5, 0.9, 1.0), "tier": 2, "how": "A kill after dying three times in a row."},
	"last_gasp": {"name": "LAST GASP", "xp": 100, "color": Color(1.0, 0.45, 0.3), "tier": 2, "how": "A kill with less than 15 health left."},
	"parry": {"name": "PARRY", "xp": 60, "color": Color(0.6, 0.45, 1.0), "tier": 1, "how": "Turn a shot back with your shield."},
	"giant_slayer": {"name": "GIANT SLAYER", "xp": 300, "color": Color(1.0, 0.78, 0.25), "tier": 4, "how": "Kill the Juggernaut."},
	"victory": {"name": "VICTORY", "xp": 500, "color": Color(1.0, 0.85, 0.3), "tier": 5, "how": "Win a match."},
	"flawless": {"name": "FLAWLESS", "xp": 400, "color": Color(1.0, 1.0, 1.0), "tier": 5, "how": "Win a match without dying."},
}
## Experience for the things that aren't medals.
const XP_KILL := 100
const XP_MATCH := 150
const XP_TUTORIAL := 300
const XP_TRIAL := {"bronze": 200, "silver": 400, "gold": 800}

## Ball skins (shaders/ball.gdshader takes the numbers): the level each unlocks at (or a
## stat it needs instead: `needs` = [stat, amount, what to show]). "seam" 0 means the
## seams glow in the player's own colour.
const SKINS := {
	"core": {"name": "OBSIDIAN", "level": 1, "base": Color(0.07, 0.08, 0.1), "accent": Color(0.13, 0.14, 0.18),
		"rough": 0.22, "metal": 0.5, "glow": 2.6, "pattern": 0},
	"chrome": {"name": "CHROME", "level": 3, "base": Color(0.82, 0.85, 0.9), "accent": Color(0.62, 0.66, 0.72),
		"rough": 0.06, "metal": 1.0, "glow": 1.2, "pattern": 0},
	"ember": {"name": "EMBER", "level": 5, "base": Color(0.09, 0.05, 0.04), "accent": Color(0.2, 0.07, 0.03),
		"seam": Color(1.0, 0.42, 0.08), "rough": 0.5, "metal": 0.2, "glow": 4.0, "pattern": 2},
	"glacier": {"name": "GLACIER", "level": 8, "base": Color(0.62, 0.82, 0.95), "accent": Color(0.85, 0.94, 1.0),
		"seam": Color(0.85, 0.97, 1.0), "rough": 0.1, "metal": 0.15, "glow": 1.6, "pattern": 0},
	"toxic": {"name": "TOXIC", "level": 12, "base": Color(0.04, 0.07, 0.04), "accent": Color(0.1, 0.24, 0.05),
		"seam": Color(0.45, 1.0, 0.15), "rough": 0.35, "metal": 0.3, "glow": 3.6, "pattern": 1},
	"royal": {"name": "ROYAL", "level": 16, "base": Color(0.2, 0.07, 0.36), "accent": Color(0.95, 0.72, 0.2),
		"seam": Color(1.0, 0.8, 0.3), "rough": 0.25, "metal": 0.7, "glow": 2.0, "pattern": 0},
	"gold": {"name": "SOLID GOLD", "level": 20, "base": Color(1.0, 0.74, 0.22), "accent": Color(1.0, 0.86, 0.45),
		"seam": Color(1.0, 0.9, 0.55), "rough": 0.14, "metal": 1.0, "glow": 1.0, "pattern": 0},
	"prism": {"name": "PRISM", "level": 25, "base": Color(0.5, 0.5, 0.5), "accent": Color(0.8, 0.8, 0.8),
		"seam": Color(1.0, 1.0, 1.0), "rough": 0.12, "metal": 0.6, "glow": 1.8, "pattern": 3},
	"galaxy": {"name": "GALAXY", "level": 30, "base": Color(0.03, 0.02, 0.09), "accent": Color(0.1, 0.04, 0.22),
		"seam": Color(0.6, 0.45, 1.0), "rough": 0.2, "metal": 0.4, "glow": 2.4, "pattern": 4},
	"void": {"name": "VOID", "level": 40, "base": Color(0.0, 0.0, 0.0), "accent": Color(0.0, 0.0, 0.0),
		"seam": Color(1.0, 1.0, 1.0), "rough": 0.9, "metal": 0.0, "glow": 5.0, "pattern": 0},
	"magma": {"name": "MAGMA", "level": 50, "base": Color(0.05, 0.02, 0.02), "accent": Color(0.12, 0.03, 0.02),
		"seam": Color(1.0, 0.25, 0.05), "rough": 0.7, "metal": 0.1, "glow": 6.0, "pattern": 2},
	"ballistic": {"name": "BALLISTIC", "level": 75, "base": Color(0.9, 0.95, 1.0), "accent": Color(1.0, 1.0, 1.0),
		"seam": Color(0.6, 0.9, 1.0), "rough": 0.05, "metal": 0.9, "glow": 5.0, "pattern": 1},
	"champion": {"name": "CHAMPION", "level": 0, "needs": ["wins", 25, "WIN 25 MATCHES"], "base": Color(0.85, 0.08, 0.1),
		"accent": Color(1.0, 0.82, 0.3), "seam": Color(1.0, 0.9, 0.5), "rough": 0.18, "metal": 0.8, "glow": 2.4, "pattern": 1},
	"decorated": {"name": "DECORATED", "level": 0, "needs": ["medals", 250, "EARN 250 MEDALS"], "base": Color(0.1, 0.16, 0.3),
		"accent": Color(0.8, 0.82, 0.9), "seam": Color(0.5, 0.75, 1.0), "rough": 0.2, "metal": 0.9, "glow": 2.2, "pattern": 3},
	"comet": {"name": "COMET", "level": 0, "needs": ["trial_golds", 5, "GOLD ON 5 TIME TRIALS"], "base": Color(0.02, 0.1, 0.14),
		"accent": Color(0.1, 0.5, 0.6), "seam": Color(0.3, 1.0, 0.95), "rough": 0.15, "metal": 0.5, "glow": 4.5, "pattern": 4},
}
## Speed trails: the level each unlocks at and its colours, tail to head ("player" = your
## own colour).
const TRAILS := {
	"player": {"name": "YOUR COLOUR", "level": 1, "colors": []},
	"frost": {"name": "FROST", "level": 4, "colors": [Color(0.3, 0.6, 1.0), Color(0.85, 0.97, 1.0)]},
	"inferno": {"name": "INFERNO", "level": 7, "colors": [Color(1.0, 0.15, 0.0), Color(1.0, 0.8, 0.2)]},
	"toxic": {"name": "TOXIC", "level": 11, "colors": [Color(0.1, 0.6, 0.1), Color(0.7, 1.0, 0.2)]},
	"royal": {"name": "ROYAL", "level": 15, "colors": [Color(0.45, 0.1, 0.9), Color(1.0, 0.75, 0.3)]},
	"sunset": {"name": "SUNSET", "level": 22, "colors": [Color(0.5, 0.1, 0.7), Color(1.0, 0.45, 0.3)]},
	"ghost": {"name": "GHOST", "level": 28, "colors": [Color(0.5, 0.55, 0.6), Color(1.0, 1.0, 1.0)]},
	"gold": {"name": "GOLD", "level": 35, "colors": [Color(0.9, 0.55, 0.1), Color(1.0, 0.95, 0.6)]},
	"rainbow": {"name": "RAINBOW", "level": 45, "colors": [], "rainbow": true},
}

## Daily challenge templates: [id, text (%d = the target), the stat it counts, targets to
## pick from, experience for each target].
const CHALLENGE_POOL := [
	["kills", "GET %d KILLS", "kills", [15, 25, 40], [500, 750, 1100]],
	["wins", "WIN %d MATCHES", "wins", [1, 2, 3], [600, 1000, 1500]],
	["matches", "PLAY %d MATCHES", "matches", [2, 3, 5], [400, 600, 900]],
	["medals", "EARN %d MEDALS", "medals", [6, 12, 20], [500, 800, 1200]],
	["parries", "PARRY %d SHOTS", "parries", [2, 4], [500, 900]],
	["multi", "GET %d MULTI-KILLS", "multi_kills", [1, 3], [500, 900]],
	["long", "GET %d LONG SHOTS", "long_shots", [2, 4], [500, 800]],
	["air", "GET %d KILLS FROM THE AIR", "air_kills", [3, 6], [500, 800]],
	["infinity", "HIT TOP SPEED %d TIMES", "infinity", [2, 5], [400, 700]],

	["trials", "FINISH %d TIME TRIALS", "trials_run", [1, 3], [400, 800]],
	["streak", "REACH A %d KILLSTREAK", "day_best_streak", [4, 6], [600, 1000]],
]
const CHALLENGES_A_DAY := 3

var xp := 0
## Lifetime counters and records, by name.
var stats := {}
## How many of each medal: {id: count}.
var medals := {}
## Today's challenges: each {id, text, stat, target, xp, start, done}.
var challenges: Array = []
var challenge_day := ""
## Best time-trial run per map (scene path): {"time": seconds, "medal": "" / bronze...}.
var trials := {}
## What's worn.
var skin := "core"
var trail := "player"
## Skins and trails seen in the Locker since they unlocked (new ones are flagged until then).
var seen := {}

var _dirty := false
var _save_in := 0.0
## Off on a dedicated server (it has no player of its own).
var _on := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_on = DisplayServer.get_name() != "headless" or OS.get_environment("PROFILE_TEST") == "1"
	if not _on:
		set_process(false)
		return
	_load()
	roll_challenges()


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_in -= delta
	if _save_in <= 0.0:
		save()


func _exit_tree() -> void:
	if _on and _dirty:
		save()


# --- Levels ------------------------------------------------------------------------------

## Experience needed to go from `at_level` to the next.
static func need(at_level: int) -> int:
	return NEED_BASE + NEED_STEP * (at_level - 1)


## Total experience at which `at_level` starts.
static func level_start(at_level: int) -> int:
	var n := at_level - 1
	return NEED_BASE * n + NEED_STEP * n * (n - 1) / 2


static func level_of(total: int) -> int:
	var at := 1
	while at < MAX_LEVEL and total >= level_start(at + 1):
		at += 1
	return at


func level() -> int:
	return level_of(xp)


## How far through the current level, 0..1 (1 at the top level).
func level_progress() -> float:
	var at := level()
	if at >= MAX_LEVEL:
		return 1.0
	return clampf(float(xp - level_start(at)) / float(need(at)), 0.0, 1.0)


## [name, colour] of the rank a level sits in.
static func rank_of(at_level: int) -> Array:
	var found: Array = RANKS[0]
	for r in RANKS:
		if at_level >= int(r[0]):
			found = r
	return [found[1], found[2]]


# --- Earning -----------------------------------------------------------------------------

## Gives experience. Emits xp_gained, and leveled_up for each level it carries past.
func award(amount: int, reason := "") -> void:
	if not _on or amount <= 0:
		return
	var before := level()
	xp += amount
	_touch()
	xp_gained.emit(amount, reason)
	var after := level()
	for at in range(before + 1, after + 1):
		leveled_up.emit(at)


func add_stat(key: String, amount := 1.0) -> void:
	if not _on:
		return
	stats[key] = float(stats.get(key, 0.0)) + amount
	_touch()
	_check_challenges()


## A record: kept if it beats what's there. Returns true if it did.
func best_stat(key: String, value: float) -> bool:
	if not _on or value <= float(stats.get(key, 0.0)):
		return false
	stats[key] = value
	_touch()
	_check_challenges()
	return true


func stat(key: String) -> float:
	return float(stats.get(key, 0.0))


## A medal: counted, paid, announced.
func earn_medal(id: String) -> void:
	if not _on or not MEDALS.has(id):
		return
	medals[id] = int(medals.get(id, 0)) + 1
	add_stat("medals")
	medal_earned.emit(id)
	award(int(MEDALS[id]["xp"]), String(MEDALS[id]["name"]))


## A finished time-trial run on `map`. Returns {"best": it beat the old time, "medal": the
## medal this run earned ("" for none), "new_medal": it's better than any medal before}.
func record_trial(map: String, time: float, medal: String) -> Dictionary:
	var out := {"best": false, "medal": medal, "new_medal": false}
	if not _on:
		return out
	add_stat("trials_run")
	var old: Dictionary = trials.get(map, {})
	var order := ["", "bronze", "silver", "gold"]
	var had := String(old.get("medal", ""))
	if order.find(medal) > order.find(had):
		out["new_medal"] = true
		# Paid for the step up only (a gold after a silver pays the difference).
		award(int(XP_TRIAL.get(medal, 0)) - int(XP_TRIAL.get(had, 0)), "TIME TRIAL " + medal.to_upper())
		if medal == "gold":
			add_stat("trial_golds")
	if old.is_empty() or time < float(old.get("time", INF)):
		out["best"] = true
		trials[map] = {"time": time, "medal": order[maxi(order.find(medal), order.find(had))]}
	elif out["new_medal"]:
		trials[map] = {"time": float(old.get("time", time)), "medal": medal}
	_touch()
	return out


# --- Cosmetics ---------------------------------------------------------------------------

## True if skin / trail `id` (in `table`: SKINS or TRAILS) is unlocked.
func unlocked(table: Dictionary, id: String) -> bool:
	if not table.has(id):
		return false
	var item: Dictionary = table[id]
	if item.has("needs"):
		return stat(String(item["needs"][0])) >= float(item["needs"][1])
	return level() >= int(item["level"])


## What it takes to unlock it, for the Locker ("LEVEL 12", "WIN 25 MATCHES").
static func unlock_text(item: Dictionary) -> String:
	if item.has("needs"):
		return String(item["needs"][2])
	return "LEVEL %d" % int(item["level"])


func wear(kind: String, id: String) -> void:
	if kind == "skin" and unlocked(SKINS, id):
		skin = id
	elif kind == "trail" and unlocked(TRAILS, id):
		trail = id
	else:
		return
	_touch()
	save()
	changed.emit()


## What other players need to draw this player: sent to the server with the loadout.
func public_card() -> Dictionary:
	return {"skin": skin if unlocked(SKINS, skin) else "core", "trail": trail if unlocked(TRAILS, trail) else "player", "level": level()}


## A card from anyone (the network, a bot) made safe to use: known ids, a sane level.
static func clean_card(card) -> Dictionary:
	var out := {"skin": "core", "trail": "player", "level": 1}
	if typeof(card) != TYPE_DICTIONARY:
		return out
	if SKINS.has(String(card.get("skin", ""))):
		out["skin"] = String(card["skin"])
	if TRAILS.has(String(card.get("trail", ""))):
		out["trail"] = String(card["trail"])
	out["level"] = clampi(int(card.get("level", 1)), 1, MAX_LEVEL)
	return out


## Everything that unlocks exactly at `at_level`: [[kind, id, name], ...].
static func unlocks_at(at_level: int) -> Array:
	var out: Array = []
	for id in SKINS:
		if int(SKINS[id]["level"]) == at_level and at_level > 1:
			out.append(["BALL SKIN", id, SKINS[id]["name"]])
	for id in TRAILS:
		if int(TRAILS[id]["level"]) == at_level and at_level > 1:
			out.append(["TRAIL", id, TRAILS[id]["name"]])
	return out


# --- Daily challenges --------------------------------------------------------------------

## Today's three challenges: the same three for everyone on the same date, each counting
## from where the stat stood when the day's set was first made on this computer.
func roll_challenges() -> void:
	var today := Time.get_date_string_from_system()
	if today == challenge_day and challenges.size() == CHALLENGES_A_DAY:
		return
	challenge_day = today
	challenges = []
	stats["day_best_streak"] = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ballistic-" + today)
	var pool := CHALLENGE_POOL.duplicate()
	for i in CHALLENGES_A_DAY:
		var pick: Array = pool.pop_at(rng.randi() % pool.size())
		var tier := rng.randi() % (pick[3] as Array).size()
		challenges.append({"id": pick[0], "text": String(pick[1]) % int(pick[3][tier]), "stat": pick[2],
			"target": int(pick[3][tier]), "xp": int(pick[4][tier]), "start": stat(String(pick[2])), "done": false})
	_touch()
	changed.emit()


## How far along challenge `c` is, 0..its target.
func challenge_progress(c: Dictionary) -> int:
	return clampi(int(stat(String(c["stat"])) - float(c["start"])), 0, int(c["target"]))


func _check_challenges() -> void:
	for c in challenges:
		if not c["done"] and challenge_progress(c) >= int(c["target"]):
			c["done"] = true
			add_stat("challenges_done")
			challenge_done.emit(c)
			award(int(c["xp"]), "CHALLENGE COMPLETE")


# --- Saving ------------------------------------------------------------------------------

func _touch() -> void:
	if not _dirty:
		_save_in = SAVE_EVERY
	_dirty = true


func save() -> void:
	if not _on:
		return
	_dirty = false
	var file := ConfigFile.new()
	file.set_value("career", "xp", xp)
	file.set_value("career", "stats", stats)
	file.set_value("career", "medals", medals)
	file.set_value("career", "trials", trials)
	file.set_value("daily", "day", challenge_day)
	file.set_value("daily", "challenges", challenges)
	file.set_value("locker", "skin", skin)
	file.set_value("locker", "trail", trail)
	file.set_value("locker", "seen", seen)
	if file.save(PATH + ".tmp") != OK:
		return
	var dir := DirAccess.open("user://")
	if not dir:
		return
	if dir.file_exists(PATH.get_file()):
		dir.copy(PATH, PATH + ".bak")
	dir.rename(PATH + ".tmp", PATH)


func _load() -> void:
	var file := ConfigFile.new()
	var loaded := file.load(PATH)
	# A damaged file (a crash mid-save): the last good copy.
	if loaded != OK and FileAccess.file_exists(PATH + ".bak"):
		loaded = file.load(PATH + ".bak")
	if loaded != OK:
		return
	xp = maxi(int(file.get_value("career", "xp", 0)), 0)
	stats = _dict(file.get_value("career", "stats", {}))
	medals = _dict(file.get_value("career", "medals", {}))
	trials = _dict(file.get_value("career", "trials", {}))
	challenge_day = String(file.get_value("daily", "day", ""))
	var saved = file.get_value("daily", "challenges", [])
	challenges = saved if typeof(saved) == TYPE_ARRAY else []
	# Only sets that still make sense (a newer version may have changed the pool).
	for c in challenges:
		if typeof(c) != TYPE_DICTIONARY or not (c as Dictionary).has_all(["id", "text", "stat", "target", "xp", "start", "done"]):
			challenges = []
			challenge_day = ""
			break
	skin = String(file.get_value("locker", "skin", "core"))
	trail = String(file.get_value("locker", "trail", "player"))
	seen = _dict(file.get_value("locker", "seen", {}))
	if not SKINS.has(skin):
		skin = "core"
	if not TRAILS.has(trail):
		trail = "player"


static func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Safe lookup from anywhere (null on a dedicated server or before the services exist).
static func of(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("Profile") if tree else null
