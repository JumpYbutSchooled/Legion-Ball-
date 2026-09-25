extends RefCounted
## Names, colours and briefings for the weapons, in slot order. The last ones are staff
## weapons ("access"): hidden and unusable unless a server accepted a staff code.
## The single source for weapon colours (the weapon manager applies them) and for
## the text shown in the main menu's Armory and the in-game weapon selector.

const WEAPONS := [
	{
		"name": "GATLING",
		"tag": "RAPID HITSCAN",
		"color": Color(0.3, 0.8, 1.0),
		"summary": "Six crystal blades fire in rotation. Steady damage, weaker at long range.",
		"usage": [
			"HOLD LMB  fire ~15 shots/sec, instant hit",
			"Low damage per shot, shoves cubes",
			"Small lock circle: a target inside it takes every shot (up to 70m)",
			"Full damage to 50m, dropping to 40% at 180m",
			"30-shot magazine, reloads itself in 1.6s (T to reload early)",
			"Crosshair: one line per blade, kicks as it fires",
		],
		"combo": "Shred SWARM-marked targets for double damage.",
	},
	{
		"name": "RAILGUN",
		"tag": "CHARGED PRECISION",
		"color": Color(1.0, 0.5, 0.1),
		"summary": "One huge blade. A slow, visible charge for one heavy shot.",
		"usage": [
			"HOLD LMB  charge for 2.5s, fires a laser bolt when full",
			"The bolt flies out (homes on the lock) and hits when it arrives",
			"Heavy hit, but never a one-shot on its own",
			"Locks the target nearest the circle's center (up to 150m)",
			"Tip flare swells as it charges: others see it coming",
			"Explodes on impact; dash-strength recoil (any direction)",
			"5s reload: breaks apart, reforms with a flash",
		],
		"combo": "NOVA-staggered targets can't dodge the lock.",
	},
	{
		"name": "SCATTER",
		"tag": "OVERHEAT SHOTGUN",
		"color": Color(1.0, 0.25, 0.75),
		"summary": "Pump-action crystal shotgun. One-shots up close, weak at range.",
		"usage": [
			"HOLD LMB  cone of 10 pellets, 1 shot every 0.7s, 3 shots per heat",
			"Every pellet landing point-blank is a ONE-SHOT",
			"Full damage within 8m, down to 15% by 45m",
			"Each shot adds heat; it cools once you stop",
			"100% = OVERHEAT: locked until fully vented (T vents early)",
			"Kicks you opposite to where you look:",
			"      look DOWN and fire to shotgun-jump",
		],
		"combo": "TETHER into a target, then fire point-blank.",
	},
	{
		"name": "TETHER",
		"tag": "GRAPPLE",
		"color": Color(0.55, 1.0, 0.2),
		"summary": "Hook anything within 120m and reel yourself in.",
		"usage": [
			"LMB  hook what's under the crosshair (hold: hooks as soon as it's in range)",
			"HOLD  reel in on a taut elastic rope",
			"Stretch it and it hauls harder; swing round the hook",
			"RELEASE  let go and keep momentum",
			"The rope snaps after 3s; it can't hold you up forever",
			"Sticks to moving targets; yanks cubes to you",
			"Hit the ground fast while hooked: SLAM explosion",
		],
		"combo": "Fling off the hook into a DASH or a SCATTER blast.",
	},
	{
		"name": "NOVA",
		"tag": "AREA BLAST",
		"color": Color(1.0, 0.82, 0.2),
		"summary": "Charged shockwave around you. Launches you sky-high, or slams you down.",
		"usage": [
			"HOLD LMB  charge (up to 1.2s), RELEASE  detonate",
			"Bigger charge: bigger radius (4-12m) and launch",
			"In the AIR: throws you down into a huge ground SLAM",
			"STAGGERS targets: frozen in place for 1.2s",
			"No cooldown; STAGGER needs at least 60% charge",
		],
		"combo": "Stagger, then RAILGUN; launch up, then Nova again to slam.",
	},
	{
		"name": "SWARM",
		"tag": "HOMING MISSILES",
		"color": Color(0.6, 0.35, 1.0),
		"summary": "Paint targets, then unleash homing crystal missiles.",
		"usage": [
			"HOLD LMB  paint up to 4 locks (can stack on one target, up to 90m)",
			"RELEASE  one homing missile per painted target",
			"Hits MARK targets: 1.5x damage from everything, 3s",
		],
		"combo": "Mark a group, then switch to GATLING or RAILGUN.",
	},
	# Staff weapons (unlocked by a staff code; scripts/net/moderation.gd). "access" is
	# the lowest role that gets it. Key 0 hides or shows them.
	{
		"name": "RAIN OF GOD",
		"tag": "STAFF // FIFTY GUNS",
		"color": Color(1.0, 0.9, 0.45),
		"access": "mod",
		"summary": "The Gatling with fifty blades. A wall of fire that goes through walls.",
		"usage": [
			"HOLD LMB  fire ~50 shots/sec from fifty blades in turn",
			"Locks like the RAILGUN, at any range, THROUGH WALLS",
			"Locked shots hit the target directly, wherever it is",
			"No lock: hitscan down the crosshair",
			"UNPARRYABLE: goes straight through shields",
			"Kills play the railgun's impact frames",
		],
		"combo": "Lock on and hold.",
	},
	{
		"name": "PILLARS OF GOD",
		"tag": "OWNER // ORBITAL STRIKE",
		"color": Color(1.0, 0.97, 0.85),
		"access": "owner",
		"summary": "Calls a pillar of light down from orbit onto whoever you're locked on to.",
		"usage": [
			"LMB  call the strike on the lock (or the crosshair point)",
			"Locks like the RAILGUN, at any range, THROUGH WALLS",
			"A targeting beam tracks them for 0.9s, then the pillar lands",
			"Kills everyone in a 16m blast; 4s cooldown",
			"UNPARRYABLE: goes straight through shields",
			"The biggest impact frames in the game",
		],
		"combo": "There is no combo. There is only the pillar.",
	},
]

## Which roles may use a weapon with each "access" level.
const ACCESS := {"mod": ["mod", "owner"], "owner": ["owner"]}


static func count() -> int:
	return WEAPONS.size()


static func get_entry(slot: int) -> Dictionary:
	return WEAPONS[slot]


## How many slots (from the first) this player may use right now. Staff weapons sit at
## the end, least exclusive first, so what a role gets is always a run of slots.
## Hidden entirely while the player has them toggled off (key 0).
static func unlocked_count(tree: SceneTree) -> int:
	var mod := tree.root.get_node_or_null("Mod") if tree else null
	var role: String = mod.call("staff_role") if mod else ""
	var settings := tree.root.get_node_or_null("Settings") if tree else null
	var shown: bool = settings.call("get_value", "show_staff_weapons") if settings else true
	var n := 0
	for w in WEAPONS:
		var access: String = w.get("access", "")
		if access != "" and (not shown or not ACCESS[access].has(role)):
			break
		n += 1
	return n


## True if this player has any staff weapons (whether or not they're toggled on).
static func has_staff_weapons(tree: SceneTree) -> bool:
	var mod := tree.root.get_node_or_null("Mod") if tree else null
	var role: String = mod.call("staff_role") if mod else ""
	return ACCESS["mod"].has(role)
