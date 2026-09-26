extends RefCounted
## Every weapon, by id: names, colours, combo groups, blade layouts and the briefings shown
## in the Armory and the weapon wheel. The single source for weapon colours.
##
## Players pick LOADOUT_SIZE weapons from the POOL (keys 1-6; Settings "loadout", synced
## in the roster as players[id]["loadout"]). Staff ("god") weapons are never in the pool:
## they always sit after the loadout (keys 7-9), unlocked by role, and they're the only
## white weapons. Pool weapons marked "built": false would be concepts shown in the Armory
## but not playable (none right now).
## Every weapon has its own colour and its own blade layout ("layout").

const LOADOUT_SIZE := 6
const DEFAULT_LOADOUT := ["gatling", "railgun", "scatter", "tether", "nova", "swarm"]
## Staff weapons, least exclusive first (what a role gets is always a run of these).
const STAFF := ["rain_of_god", "tears_of_an_angel", "pillars_of_god"]
## Which roles may use a staff weapon with each "access" level.
const ACCESS := {"mod": ["mod", "owner"], "owner": ["owner"]}
const GOD_WHITE := Color(1.0, 1.0, 1.0)
## Equip this many from one group to get its set bonus.
const SET_SIZE := 3

## Combo groups: weapons that work well together. Equip SET_SIZE from one for its perk.
const GROUPS := {
	"frost": {"name": "FROST / CONTROL", "color": Color(0.45, 0.75, 1.0),
		"theme": "Slow them, hold them, trap them.",
		"bonus": "Your slows, freezes and staggers last 30% longer."},
	"hunter": {"name": "HUNTER / MARK", "color": Color(0.95, 0.2, 0.25),
		"theme": "Tag a target, then finish it.",
		"bonus": "Your marks last 50% longer, and marked targets take 10% more from you."},
	"skyborne": {"name": "SKYBORNE / MOBILITY", "color": Color(0.3, 0.95, 0.5),
		"theme": "Own the air and the angles.",
		"bonus": "+20% air control."},
	"fortress": {"name": "FORTRESS / AREA DENIAL", "color": Color(0.8, 0.62, 0.35),
		"theme": "Zones, traps and cover.",
		"bonus": "Your deployables last 30% longer."},
	"brawler": {"name": "BRAWLER / CLOSE QUARTERS", "color": Color(0.9, 0.3, 0.75),
		"theme": "Get in their face.",
		"bonus": "+15% damage within 10 m."},
	"marksman": {"name": "MARKSMAN / LONG RANGE", "color": Color(1.0, 0.6, 0.15),
		"theme": "Pick them off from far away.",
		"bonus": "+15% damage beyond 60 m."},
	"momentum": {"name": "MOMENTUM / SPEED", "color": Color(0.2, 0.9, 0.95),
		"theme": "Speed is damage.",
		"bonus": "+10% top speed."},
}

const WEAPONS := {
	# --- Built -------------------------------------------------------------------------
	"gatling": {
		"name": "GATLING", "tag": "RAPID HITSCAN", "group": "hunter", "built": true,
		"color": Color(0.3, 0.8, 1.0), "script": "res://scripts/weapons/gatling.gd",
		"layout": "Six crescents in three rows, right and left, like a barrel cluster.",
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
	"railgun": {
		"name": "RAILGUN", "tag": "CHARGED PRECISION", "group": "marksman", "built": true,
		"color": Color(1.0, 0.5, 0.1), "script": "res://scripts/weapons/railgun.gd",
		"layout": "One huge blade on the right.",
		"summary": "One huge blade. A slow, visible charge for one heavy shot.",
		"usage": [
			"HOLD LMB  charge for 2.5s, fires a laser bolt when full",
			"The bolt flies out (homes on the lock) and hits when it arrives",
			"Heavy hit, but never a one-shot on its own",
			"Locks the target nearest the circle's center",
			"Tip flare swells as it charges: others see it coming",
			"Explodes on impact; dash-strength recoil (any direction)",
			"5s reload: breaks apart, reforms with a flash",
		],
		"combo": "NOVA-staggered targets can't dodge the lock.",
	},
	"scatter": {
		"name": "SCATTER", "tag": "OVERHEAT SHOTGUN", "group": "brawler", "built": true,
		"color": Color(1.0, 0.25, 0.75), "script": "res://scripts/weapons/scatter.gd",
		"layout": "Four short blades splayed low.",
		"summary": "Pump-action crystal shotgun. One-shots up close, weak at range.",
		"usage": [
			"HOLD LMB  cone of 10 pellets, 1 shot every 0.7s, 3 shots per heat",
			"Every pellet landing point-blank is a ONE-SHOT",
			"Full damage within 15m, down to 25% by 70m",
			"Each shot adds heat; it cools once you stop",
			"100% = OVERHEAT: locked until fully vented (T vents early)",
			"Kicks you opposite to where you look:",
			"      look DOWN and fire to shotgun-jump",
		],
		"combo": "TETHER into a target, then fire point-blank.",
	},
	"tether": {
		"name": "TETHER", "tag": "GRAPPLE", "group": "skyborne", "built": true,
		"color": Color(0.55, 1.0, 0.2), "script": "res://scripts/weapons/tether.gd",
		"layout": "One long thin blade arched over the top.",
		"summary": "Hook anything within 200m and reel yourself in.",
		"usage": [
			"LMB  hook what's under the crosshair (hold: hooks as soon as it's in range)",
			"Locks onto airborne players near the crosshair",
			"HOLD  reel in on a taut elastic rope",
			"RELEASE  let go and keep momentum",
			"The rope snaps after 3s; it can't hold you up forever",
			"Hooking a wall sets off a small blast there",
			"Hit the ground fast while hooked: SLAM explosion",
		],
		"combo": "Fling off the hook into a DASH or a SCATTER blast.",
	},
	"nova": {
		"name": "NOVA", "tag": "AREA BLAST", "group": "frost", "built": true,
		"color": Color(1.0, 0.82, 0.2), "script": "res://scripts/weapons/nova.gd",
		"layout": "Four blades: a high pair and a low pair, wide apart.",
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
	"swarm": {
		"name": "SWARM", "tag": "HOMING MISSILES", "group": "hunter", "built": true,
		"color": Color(0.6, 0.35, 1.0), "script": "res://scripts/weapons/swarm.gd",
		"layout": "Two small blades raised behind the ball.",
		"summary": "Paint targets, then unleash homing crystal missiles.",
		"usage": [
			"HOLD LMB  paint up to 4 locks (can stack on one target, up to 250m)",
			"RELEASE  one homing missile per painted target",
			"Hits MARK targets: 1.5x damage from everything, 3s",
		],
		"combo": "Mark a group, then switch to GATLING or RAILGUN.",
	},

	# --- Concepts (not built yet) ----------------------------------------------------
	# FROST / CONTROL
	"frost_lance": {"built": true, "script": "res://scripts/weapons/frost_lance.gd",
		"usage": ["HOLD LMB  charge (1s), RELEASE  fire the beam", "Every hit CHILLS: 40% slower for 3s", "Full charge also FREEZES for 1s", "0.8s cooldown"],
		"name": "FROST LANCE", "tag": "CHILLING BEAM", "group": "frost",
		"color": Color(0.65, 0.9, 1.0), "layout": "One long needle pointing straight ahead, under the ball.",
		"summary": "Charged beam that CHILLS (-40% speed for 3s); a full charge freezes for 1s.",
		"combo": "Chill them, then land a RAILGUN or ARBALEST shot."},
	"gravity_well": {"built": true, "script": "res://scripts/weapons/gravity_well.gd",
		"usage": ["LMB  throw a singularity (lands, or pops open after 1s)", "Drags everyone within 28m into it for 2.5s", "Then it bursts", "6s cooldown"],
		"name": "GRAVITY WELL", "tag": "SINGULARITY", "group": "frost",
		"color": Color(0.35, 0.2, 0.9), "layout": "Three blades curled into a ring on the left side.",
		"summary": "Throw a singularity that drags players into it for 2.5s, then pops.",
		"combo": "Pull a crowd together, then NOVA or SHARD MORTAR it."},
	"prism_cage": {"built": true, "script": "res://scripts/weapons/prism_cage.gd",
		"usage": ["LMB  fire a slow crystal orb", "The first player or target it hits is CAGED for 2s", "Caged: held in place (can still shoot)", "5s cooldown"],
		"name": "PRISM CAGE", "tag": "CRYSTAL TRAP", "group": "frost",
		"color": Color(0.3, 1.0, 0.85), "layout": "Four blades meeting in a box frame in front.",
		"summary": "A slow orb that locks the first player it hits in a crystal cage for 2s.",
		"combo": "Cage them, then EXECUTIONER."},
	"stasis_mine": {"built": true, "script": "res://scripts/weapons/stasis_mine.gd",
		"usage": ["LMB  lob a mine; it sticks where it lands", "Arms after a moment; anyone near sets it off", "The blast STAGGERS everyone in it", "Two out at once; a third replaces the oldest"],
		"name": "STASIS MINE", "tag": "PROXIMITY TRAP", "group": "frost",
		"color": Color(0.2, 0.45, 1.0), "layout": "Two stubby blades pointing down at the floor.",
		"summary": "Up to two sticky mines that STAGGER whoever rolls near them.",
		"combo": "Mine a doorway, then wait with PIERCER."},
	"time_dilator": {"built": true, "script": "res://scripts/weapons/time_dilator.gd",
		"usage": ["LMB  spread a 25m bubble round you for 4s", "Enemies inside are slowed", "Their shots crawl through it at half speed", "10s cooldown"],
		"name": "TIME DILATOR", "tag": "SLOW FIELD", "group": "frost",
		"color": Color(0.55, 0.6, 1.0), "layout": "Six tiny blades orbiting in a halo above the ball.",
		"summary": "A bubble round you where enemies and their shots move at half speed.",
		"combo": "Slow them inside, then BRAWLER weapons do the rest."},
	# HUNTER / MARK
	"hunters_sigil": {"built": true, "script": "res://scripts/weapons/hunters_sigil.gd",
		"usage": ["LMB  tag the target nearest the crosshair: any range, through walls", "You see them through walls for 6s", "Tagged targets are MARKED for 3s (1.5x damage)", "4s cooldown"],
		"name": "HUNTER'S SIGIL", "tag": "TRACKER", "group": "hunter",
		"color": Color(1.0, 0.12, 0.18), "layout": "A single blade standing straight up like an antenna.",
		"summary": "Tag a target at any range: you see them through walls for 6s.",
		"combo": "Tag, then chase them down with TETHER or BLINK EDGE."},
	"executioner": {"built": true, "script": "res://scripts/weapons/executioner.gd",
		"usage": ["LMB  lunge and chop everything in front (9m)", "Heavy hit, TRIPLE damage below 30% health", "1.2s cooldown"],
		"name": "EXECUTIONER", "tag": "FINISHER", "group": "hunter",
		"color": Color(0.55, 0.05, 0.08), "layout": "One broad cleaver held high behind, blade forward.",
		"summary": "Lunging heavy blade: triple damage on anyone below 30% health.",
		"combo": "Soften them with GATLING, then finish."},
	"echo_rifle": {"built": true, "script": "res://scripts/weapons/echo_rifle.gd",
		"usage": ["HOLD LMB  semi-auto hitscan", "Every hit repeats itself 1s later", "Echoes follow the target wherever it went"],
		"name": "ECHO RIFLE", "tag": "DOUBLE TAP", "group": "hunter",
		"color": Color(0.95, 0.45, 0.55), "layout": "Two parallel blades stacked on the right, one above the other.",
		"summary": "Every hit repeats itself one second later.",
		"combo": "Echoes on SWARM-marked targets hit twice as hard."},
	"splinter_bomb": {"built": true, "script": "res://scripts/weapons/splinter_bomb.gd",
		"usage": ["LMB  throw a shard that sticks to what it hits", "Bursts 2s later", "Mark the target first for 1.5x", "2.5s cooldown"],
		"name": "SPLINTER BOMB", "tag": "STICKY CHARGE", "group": "hunter",
		"color": Color(1.0, 0.4, 0.3), "layout": "Three short spikes fanned out on the left.",
		"summary": "Sticks a shard to a target that bursts after 2s; extra damage if they're marked.",
		"combo": "Stick, mark with SWARM, watch it pop."},
	# SKYBORNE / MOBILITY
	"blink_edge": {"built": true, "script": "res://scripts/weapons/blink_edge.gd",
		"usage": ["LMB  teleport 35m where you look (stops at walls)", "Keeps your speed, in the new direction", "Cuts everyone on the line", "2s cooldown"],
		"name": "BLINK EDGE", "tag": "TELEPORT SLASH", "group": "skyborne",
		"color": Color(0.2, 1.0, 0.6), "layout": "Two thin swept blades along the sides, pointing back.",
		"summary": "Teleport 35m where you look, leaving a slash that cuts anyone on the line.",
		"combo": "Blink in, SCATTER, blink out."},
	"jet_crystals": {"built": true, "script": "res://scripts/weapons/jet_crystals.gd",
		"usage": ["HOLD LMB  thrust wherever you look", "Fuel lasts about 2.5s", "Refills on the ground"],
		"name": "JET CRYSTALS", "tag": "THRUSTERS", "group": "skyborne",
		"color": Color(0.0, 0.75, 0.35), "layout": "Four short fins pointing backwards in a ring.",
		"summary": "Hold to thrust where you look; fuel refills on the ground.",
		"combo": "Fly high, then METEOR DROP."},
	"winglets": {"built": true, "script": "res://scripts/weapons/winglets.gd",
		"usage": ["LMB in the air  flap: an extra jump (2 per trip)", "HOLD in the air  glide: your fall becomes a drift", "Flaps come back when you land"],
		"name": "WINGLETS", "tag": "GLIDER", "group": "skyborne",
		"color": Color(0.8, 1.0, 0.6), "layout": "Two long flat wings straight out to the sides.",
		"summary": "Flap for extra jumps in the air, and hold to glide.",
		"combo": "Glide over them with RAILGUN or ARBALEST."},
	"meteor_drop": {"built": true, "script": "res://scripts/weapons/meteor_drop.gd",
		"usage": ["LMB in the air  slam straight down", "Crater grows with how far you fell", "LMB on the ground  leap up first", "2.5s cooldown"],
		"name": "METEOR DROP", "tag": "AIR SLAM", "group": "skyborne",
		"color": Color(0.8, 0.22, 0.0), "layout": "Three heavy blades pointing down under the ball.",
		"summary": "In the air, slam straight down: damage grows with how far you fall.",
		"combo": "Get height with TETHER or JET CRYSTALS first."},
	"skylance": {"built": true, "script": "res://scripts/weapons/skylance.gd",
		"usage": ["HOLD LMB  throw the spear and ride it", "Runs through everyone in its way", "RELEASE  drop off, keeping the speed", "Snaps after 1.6s or at a wall"],
		"name": "SKYLANCE", "tag": "RIDEABLE SPEAR", "group": "skyborne",
		"color": Color(0.25, 0.7, 0.7), "layout": "One spear on top pointing straight forward.",
		"summary": "Throw a spear and ride it: it carries you until you let go.",
		"combo": "Ride it in, drop off into a NOVA slam."},
	# FORTRESS / AREA DENIAL
	"shard_mortar": {"built": true, "script": "res://scripts/weapons/shard_mortar.gd",
		"usage": ["LMB  lob a shell at the crosshair in a high arc", "Bursts, then five bomblets go off around it", "1.6s cooldown"],
		"name": "SHARD MORTAR", "tag": "CLUSTER ARTILLERY", "group": "fortress",
		"color": Color(0.8, 0.55, 0.25), "layout": "A short upright tube of four blades angled skyward.",
		"summary": "Lobbed shells that split into cluster bomblets.",
		"combo": "Shell whatever GRAVITY WELL pulls together."},
	"crystal_wall": {"built": true, "script": "res://scripts/weapons/crystal_wall.gd",
		"usage": ["LMB  raise an 18m wall 10m ahead for 5s", "Blocks shots and players", "8s cooldown"],
		"name": "CRYSTAL WALL", "tag": "INSTANT COVER", "group": "fortress",
		"color": Color(0.6, 0.45, 0.35), "layout": "A flat slab of five blades side by side in front.",
		"summary": "Raise a crystal wall for 5s: solid cover for everyone.",
		"combo": "Wall off, then ARC PYLON the other side."},
	"arc_pylon": {"built": true, "script": "res://scripts/weapons/arc_pylon.gd",
		"usage": ["LMB  plant a pylon at your feet for 8s", "Zaps whoever is nearest within 16m", "One at a time; 10s cooldown"],
		"name": "ARC PYLON", "tag": "TESLA TURRET", "group": "fortress",
		"color": Color(0.85, 1.0, 0.3), "layout": "Two tall forks, one each side, pointing up.",
		"summary": "Plant a pylon that zaps anyone within 16m for 8s.",
		"combo": "Hold a room with SPIKE CARPET."},
	"spike_carpet": {"built": true, "script": "res://scripts/weapons/spike_carpet.gd",
		"usage": ["LMB  lay a 40m line of spikes ahead for 6s", "Anyone crossing it is cut and slowed", "7s cooldown"],
		"name": "SPIKE CARPET", "tag": "GROUND TRAP", "group": "fortress",
		"color": Color(0.5, 0.6, 0.2), "layout": "A row of small teeth along the bottom.",
		"summary": "Lay a line of crystal spikes that hurt and slow anyone crossing.",
		"combo": "Funnel them over it with CRYSTAL WALL."},
	"seeker_drone": {"built": true, "script": "res://scripts/weapons/seeker_drone.gd",
		"usage": ["LMB  launch a drone that orbits you for 10s", "It shoots whatever you aim nearest", "Keeps fighting while you switch weapons", "14s cooldown"],
		"name": "SEEKER DRONE", "tag": "COMPANION", "group": "fortress",
		"color": Color(0.45, 0.5, 0.6), "layout": "A small detached blade pair hovering above-left.",
		"summary": "A drone orbits you for 10s, firing at whatever you lock.",
		"combo": "Let the drone fight while you place traps."},
	# BRAWLER / CLOSE QUARTERS
	"crystal_saber": {"built": true, "script": "res://scripts/weapons/crystal_saber.gd",
		"usage": ["LMB  swing: cuts everything in a wide arc (8m)", "During the swing, shots that hit you are DEFLECTED back", "1s cooldown"],
		"name": "CRYSTAL SABER", "tag": "MELEE / DEFLECT", "group": "brawler",
		"color": Color(0.85, 0.1, 0.35), "layout": "One curved sword blade low on the right, sweeping forward.",
		"summary": "Melee arc; mid-swing it deflects shots back where they came from.",
		"combo": "BLINK EDGE in and cut."},
	"shock_knuckle": {"built": true, "script": "res://scripts/weapons/shock_knuckle.gd",
		"usage": ["LMB  charge your fists (3s)", "Your next DASH becomes a punch", "Anyone you hit takes a heavy hit and flies"],
		"name": "SHOCK KNUCKLE", "tag": "DASH PUNCH", "group": "brawler",
		"color": Color(0.95, 0.3, 1.0), "layout": "Two fists of stubby blades tight to the front.",
		"summary": "Charges your next dash into a damaging, knockback punch.",
		"combo": "Punch them off the map."},
	"buzzsaw": {"built": true, "script": "res://scripts/weapons/buzzsaw.gd",
		"usage": ["HOLD LMB  spin the blades up", "Anyone touching you gets shredded", "Faster you go, harder it cuts: ram people"],
		"name": "BUZZSAW", "tag": "SPINNING BLADES", "group": "brawler",
		"color": Color(0.65, 0.2, 0.5), "layout": "Eight small blades in a flat spinning disc round the middle.",
		"summary": "Blades spin round the ball; contact damage grows with your speed.",
		"combo": "Build speed with MOMENTUM weapons and ram."},
	"thorn_burst": {"built": true, "script": "res://scripts/weapons/thorn_burst.gd",
		"usage": ["HOLD LMB  charge (0.8s), RELEASE  burst", "A ring of shards all round you (22m)", "Longer charge, harder shards"],
		"name": "THORN BURST", "tag": "SHARD NOVA", "group": "brawler",
		"color": Color(1.0, 0.6, 0.85), "layout": "Many tiny spikes all over the ball, pointing out.",
		"summary": "Release a 360-degree ring of shards at short range.",
		"combo": "TETHER into a crowd and burst."},
	"mirage": {"built": true, "script": "res://scripts/weapons/mirage.gd",
		"usage": ["LMB  two decoys in your colour roll off for 7s", "Enemy locks and missiles can jump to them", "Any hit pops a decoy", "12s cooldown"],
		"name": "MIRAGE", "tag": "DECOYS", "group": "brawler",
		"color": Color(0.5, 0.35, 0.7), "layout": "Two ghostly blades trailing behind at angles.",
		"summary": "Two decoy balls peel off and run; enemy locks jump to them.",
		"combo": "Decoy, flank, SCATTER."},
	# MARKSMAN / LONG RANGE
	"beam_lance": {"built": true, "script": "res://scripts/weapons/beam_lance.gd",
		"usage": ["HOLD LMB  a steady laser", "Burns hotter the longer it stays on one target (up to 5x)", "Overheats after 3s of firing"],
		"name": "BEAM LANCE", "tag": "CONTINUOUS LASER", "group": "marksman",
		"color": Color(1.0, 0.15, 0.05), "layout": "Two long blades converging to a point far in front.",
		"summary": "A steady laser whose damage builds the longer it stays on one target.",
		"combo": "Keep them held with FROST, burn them down."},
	"piercer": {"built": true, "script": "res://scripts/weapons/piercer.gd",
		"usage": ["LMB  three-round burst", "Every round goes through every player in a line", "Walls still stop it"],
		"name": "PIERCER", "tag": "PENETRATING RIFLE", "group": "marksman",
		"color": Color(1.0, 0.7, 0.35), "layout": "One thin blade under the ball, reaching far forward.",
		"summary": "3-round hitscan bursts that punch through every player in a line.",
		"combo": "Line them up with GRAVITY WELL."},
	"arbalest": {"built": true, "script": "res://scripts/weapons/arbalest.gd",
		"usage": ["LMB  fire a heavy bolt that shoves hard", "Knocked into a wall: PINNED for 1.5s", "1.4s cooldown"],
		"name": "ARBALEST", "tag": "HEAVY BOLT", "group": "marksman",
		"color": Color(0.7, 0.35, 0.1), "layout": "A crossbow: a horizontal bow of two blades over one straight stock.",
		"summary": "A heavy bolt; anyone it knocks into a wall is pinned there (staggered).",
		"combo": "Pin them, then RAILGUN."},
	"ricochet_disc": {"built": true, "script": "res://scripts/weapons/ricochet_disc.gd",
		"usage": ["LMB  throw a disc", "Bounces off walls up to 4 times", "+35% damage after each bounce"],
		"name": "RICOCHET DISC", "tag": "BOUNCING DISC", "group": "marksman",
		"color": Color(0.9, 0.85, 0.5), "layout": "Two blades forming a flat ring on the left.",
		"summary": "A disc that bounces off walls up to 4 times, hitting harder each bounce.",
		"combo": "Bank shots into TUNNELS and around corners."},
	# MOMENTUM / SPEED
	"velocity_cannon": {"built": true, "script": "res://scripts/weapons/velocity_cannon.gd",
		"usage": ["LMB  fire a shot as hard as you're moving", "Standing still: a tickle; top speed: over half a health bar", "The meter shows your speed"],
		"name": "VELOCITY CANNON", "tag": "SPEED-SCALED SHOT", "group": "momentum",
		"color": Color(0.0, 0.55, 1.0), "layout": "One wide blade under the ball like a ram.",
		"summary": "Its damage scales with how fast you're going.",
		"combo": "Get to 500 with dashes, then fire."},
	"sonic_boom": {"built": true, "script": "res://scripts/weapons/sonic_boom.gd",
		"usage": ["LMB at 45 m/s+  fire your speed off as a shockwave", "Hits everyone in a 45m cone ahead", "You slow right down"],
		"name": "SONIC BOOM", "tag": "SPEED SHOCKWAVE", "group": "momentum",
		"color": Color(1.0, 0.0, 0.55), "layout": "Three swept-back blades in a chevron on top.",
		"summary": "At high speed, fire your speed off as a shockwave (you slow down).",
		"combo": "SLIPSTREAM back up to speed, boom again."},
	"slipstream": {"built": true, "script": "res://scripts/weapons/slipstream.gd",
		"usage": ["HOLD LMB  lay a glowing trail behind you (6s)", "Riding it pushes you faster", "Anyone crossing it gets cut"],
		"name": "SLIPSTREAM", "tag": "SPEED TRAIL", "group": "momentum",
		"color": Color(0.1, 1.0, 0.8), "layout": "Two long streamers trailing from the back.",
		"summary": "Leave a trail that speeds you up and cuts enemies who cross it.",
		"combo": "Loop your trail round a fight with BUZZSAW."},

	# --- Staff ("god") weapons: always white, never in the pool ------------------------
	"rain_of_god": {
		"name": "RAIN OF GOD", "tag": "STAFF // FIFTY GUNS", "access": "mod", "built": true,
		"color": GOD_WHITE, "script": "res://scripts/weapons/rain_of_god.gd",
		"layout": "Fifty blades wrapped all the way round the ball.",
		"summary": "The Gatling with fifty blades. A wall of fire that goes through walls.",
		"usage": [
			"HOLD LMB  fire ~50 shots/sec from fifty blades in turn",
			"Locks like the RAILGUN, at any range, THROUGH WALLS",
			"Locked shots hit the target directly, wherever it is",
			"No lock: hitscan down the crosshair",
			"UNPARRYABLE: goes straight through shields",
		],
		"combo": "Lock on and hold.",
	},
	"tears_of_an_angel": {
		"name": "TEARS OF AN ANGEL", "tag": "STAFF // ENDLESS SWARM", "access": "mod", "built": true,
		"color": GOD_WHITE, "script": "res://scripts/weapons/tears_of_an_angel.gd",
		"layout": "Four wings in an X, straight up and straight down.",
		"summary": "A white Swarm with no limits. Lock anyone, anywhere, as many times as you like.",
		"usage": [
			"HOLD LMB  lock targets anywhere on screen, any range, through walls",
			"No lock limit: stack as many missiles on a target as you want",
			"The crosshair counts your locks",
			"RELEASE  missiles leave one by one in quick succession",
			"Twice Swarm's speed, 25 damage each, straight THROUGH WALLS",
			"PARRYABLE, and a parried tear KILLS YOU instantly",
		],
		"combo": "Lock, lock, lock, release. Don't aim it at a shield.",
	},
	"pillars_of_god": {
		"name": "PILLARS OF GOD", "tag": "OWNER // ORBITAL STRIKE", "access": "owner", "built": true,
		"color": GOD_WHITE, "script": "res://scripts/weapons/pillars_of_god.gd",
		"layout": "A cross of light: blades straight up, down, left and right.",
		"summary": "Calls a pillar of light down from orbit onto whoever you're locked on to.",
		"usage": [
			"LMB  call the strike on the lock (or the crosshair point)",
			"Locks like the RAILGUN, at any range, THROUGH WALLS",
			"A targeting beam tracks them for 1.6s, a ring of light closing in",
			"Kills everyone in a 16m blast; 4s cooldown",
			"UNPARRYABLE: goes straight through shields",
		],
		"combo": "There is no combo. There is only the pillar.",
	},
}


static func by_id(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func is_staff(id: String) -> bool:
	return STAFF.has(id)


static func is_built(id: String) -> bool:
	return by_id(id).get("built", false)


## Pool weapon ids (never staff), in registry order.
static func pool() -> Array:
	var out: Array = []
	for id in WEAPONS:
		if not is_staff(id):
			out.append(id)
	return out


## Pool weapon ids in combo group `group`.
static func in_group(group: String) -> Array:
	return pool().filter(func(id: String) -> bool: return by_id(id)["group"] == group)


## Other weapons in the same group (the "works with" list).
static func partners(id: String) -> Array:
	var g: String = by_id(id).get("group", "")
	return in_group(g).filter(func(o: String) -> bool: return o != id) if g != "" else []


## A usable loadout from anything: LOADOUT_SIZE unique, built pool weapons, gaps filled
## from the default.
static func valid_loadout(ids) -> Array:
	var out: Array = []
	if typeof(ids) == TYPE_ARRAY or typeof(ids) == TYPE_PACKED_STRING_ARRAY:
		for id in ids:
			var s := String(id)
			if out.size() < LOADOUT_SIZE and not out.has(s) and not is_staff(s) and is_built(s):
				out.append(s)
	for id in DEFAULT_LOADOUT:
		if out.size() >= LOADOUT_SIZE:
			break
		if not out.has(id):
			out.append(id)
	return out


## How many of each group a loadout has: {group: count}.
static func group_counts(loadout: Array) -> Dictionary:
	var counts := {}
	for id in loadout:
		var g: String = by_id(String(id)).get("group", "")
		if g != "":
			counts[g] = int(counts.get(g, 0)) + 1
	return counts


## Groups whose set bonus a loadout earns (SET_SIZE or more from one group).
static func set_bonuses(loadout: Array) -> Array:
	var out: Array = []
	var counts := group_counts(loadout)
	for g in counts:
		if counts[g] >= SET_SIZE:
			out.append(g)
	return out


## This computer's player's loadout (Settings "loadout").
static func local_loadout(tree: SceneTree) -> Array:
	var settings := tree.root.get_node_or_null("Settings") if tree else null
	return valid_loadout(settings.call("get_value", "loadout") if settings else [])


## Every weapon a ball carries, by slot: the loadout, then the staff weapons.
static func slot_ids(loadout: Array) -> Array:
	return valid_loadout(loadout) + STAFF


## How many slots (from the first) this player may use right now: the loadout, then the
## staff weapons their role unlocks (none while hidden with key 0).
static func unlocked_count(tree: SceneTree) -> int:
	var mod := tree.root.get_node_or_null("Mod") if tree else null
	var role: String = mod.call("staff_role") if mod else ""
	var settings := tree.root.get_node_or_null("Settings") if tree else null
	var shown: bool = settings.call("get_value", "show_staff_weapons") if settings else true
	var n := LOADOUT_SIZE
	for id in STAFF:
		if not shown or not ACCESS[by_id(id)["access"]].has(role):
			break
		n += 1
	return n


## True if this player has any staff weapons (whether or not they're toggled on).
static func has_staff_weapons(tree: SceneTree) -> bool:
	var mod := tree.root.get_node_or_null("Mod") if tree else null
	var role: String = mod.call("staff_role") if mod else ""
	return ACCESS["mod"].has(role)
