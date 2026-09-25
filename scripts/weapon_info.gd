extends RefCounted
## Names, colours and briefings for the six weapons, in slot order.
## The single source for weapon colours (the weapon manager applies them) and for
## the text shown in the main menu's Armory and the in-game weapon selector.

const WEAPONS := [
	{
		"name": "GATLING",
		"tag": "RAPID HITSCAN",
		"color": Color(0.3, 0.8, 1.0),
		"summary": "Six crystal blades fire in rotation. Hold to shred.",
		"usage": [
			"HOLD LMB  fire ~15 shots/sec, instant hit",
			"Low damage per shot, shoves cubes",
			"Small lock circle: a target inside it takes every shot",
			"Crosshair: one line per blade, kicks as it fires",
		],
		"combo": "Shred SWARM-marked targets for double damage.",
	},
	{
		"name": "RAILGUN",
		"tag": "CHARGED PRECISION",
		"color": Color(1.0, 0.5, 0.1),
		"summary": "One huge blade. 3s charge, one devastating shot.",
		"usage": [
			"HOLD LMB  charge for 3s, fires when full",
			"Locks the target nearest the circle's center",
			"Tip flare swells as it charges: others see it coming",
			"Explodes on impact; dash-strength recoil (any direction)",
			"6s reload: breaks apart, reforms with a flash",
		],
		"combo": "NOVA-staggered targets can't dodge the lock.",
	},
	{
		"name": "SCATTER",
		"tag": "OVERHEAT SHOTGUN",
		"color": Color(1.0, 0.25, 0.75),
		"summary": "Long-range crystal shotgun with a tight cone. Runs on heat.",
		"usage": [
			"HOLD LMB  tight cone of 10 pellets, ~4 shots/sec, 200m",
			"Each shot adds heat; it cools once you stop",
			"100% = OVERHEAT: locked until fully vented",
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
			"STAGGERS targets: frozen in place for 2s",
		],
		"combo": "Stagger, then RAILGUN; launch up, then Nova again to slam.",
	},
	{
		"name": "SWARM",
		"tag": "HOMING MISSILES",
		"color": Color(0.6, 0.35, 1.0),
		"summary": "Paint targets, then unleash homing crystal missiles.",
		"usage": [
			"HOLD LMB  paint up to 4 targets in the zone",
			"RELEASE  one homing missile per painted target",
			"Hits MARK targets: 2x damage from everything, 4s",
		],
		"combo": "Mark a group, then switch to GATLING or RAILGUN.",
	},
]


static func count() -> int:
	return WEAPONS.size()


static func get_entry(slot: int) -> Dictionary:
	return WEAPONS[slot]
