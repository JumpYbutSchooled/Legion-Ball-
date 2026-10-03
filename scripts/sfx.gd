extends Node
## Sound effects, all synthesized in code (no audio files to ship or update).
## Created by scripts/services.gd as /root/Sfx. Every sound is some flavour of warp:
## pitch sweeps sung by detuned, wobbling voices, filtered whooshes, low thumps and
## shimmer, all run through a sweeping flanger, a soft low-pass and a little air
## (_warp_fx), so nothing comes out buzzy or beepy.
##   Sfx.play(name, position)       3D sound out in the world
##   Sfx.play_ui(name)              flat sound for the local player (UI, own ball)
##   Sfx.make_loop(name, parent)    a looping 3D player the caller drives (volume/pitch)
## Built on a worker thread at startup; anything played before it's ready is skipped.

## CD quality (was 22.05 kHz: duller, with aliasing on the sweeps).
const RATE := 44100
const Graphics := preload("res://scripts/graphics.gd")
const SoundCache := preload("res://scripts/sound_cache.gd")
const POOL_3D := 32
const POOL_UI := 10

## Static helper so callers don't need to look the service up themselves.
static func play_at(tree: SceneTree, sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var sfx := tree.root.get_node_or_null("Sfx") if tree else null
	if sfx:
		sfx.call("play", sound, pos, volume_db, pitch)


static func play_flat(tree: SceneTree, sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var sfx := tree.root.get_node_or_null("Sfx") if tree else null
	if sfx:
		sfx.call("play_ui", sound, volume_db, pitch)


var _streams := {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_ui := 0
var _enabled := true
var _task := -1
## Identifies this build of the sounds in the disk cache (scripts/sound_cache.gd).
var _key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The dedicated server has no speakers.
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	# Sound effects go through the SFX channel (Settings: SFX volume).
	Graphics.ensure_buses()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 14.0
		p.max_distance = 260.0
		p.panning_strength = 0.8
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_ui.append(p)
	# Built before (this version)? Load them; otherwise build them, then keep them.
	_key = SoundCache.key_for(get_script(), RATE)
	var cached := SoundCache.load_set("sfx", _key)
	if cached.has("wind"):
		_streams = cached
		return
	_task = WorkerThreadPool.add_task(_build_all)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


func play(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _enabled or not _streams.has(sound):
		return
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	p.stream = _streams[sound]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func play_ui(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _enabled or not _streams.has(sound):
		return
	var p := _pool_ui[_next_ui]
	_next_ui = (_next_ui + 1) % _pool_ui.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## A looping player parented to `parent` (3D) that the caller turns up and down.
## Returns null until the sounds are built, so call it again later if needed.
func make_loop(sound: String, parent: Node) -> AudioStreamPlayer3D:
	if not _enabled or not _streams.has(sound):
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = _streams[sound]
	p.unit_size = 10.0
	p.max_distance = 200.0
	p.volume_db = -80.0
	parent.add_child(p)
	return p


## Same, but flat (for the local player's own wind).
func make_flat_loop(sound: String, parent: Node) -> AudioStreamPlayer:
	if not _enabled or not _streams.has(sound):
		return null
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = _streams[sound]
	p.volume_db = -80.0
	parent.add_child(p)
	return p


# --- Synthesis -------------------------------------------------------------------------

func _build_all() -> void:
	var s := {}
	# First the sounds the start screen and the menu need straight away (the intro plays
	# as soon as the game opens); they're usable as soon as they're built.
	# Impact frames: a reversed whoosh that sucks in and rises for the whole implosion,
	# then the crack and explosion.
	s["implode"] = _wav(_mix([
		_reverse(_sweep(0.45, 2400.0, 50.0, 0.5, 0.001, 1.6, 3, 0.35)),
		_gain(_reverse(_noise(0.45, 0.25, 0.001)), 0.8),
		_gain(_reverse(_shimmer(0.45, 1800.0, 200.0, 0.001)), 0.5),
	]))
	s["impact_boom"] = _wav(_impact_boom())
	s["rail"] = _wav(_mix([
		_sweep(1.0, 2600.0, 55.0, 0.7, 0.002, 2.6, 2, 0.22),
		_boom(0.9, 1.0),
	]))
	s["boom"] = _wav(_boom(1.3, 1.0))
	# Speedometer.
	var shatter := _glass(0.5)
	s["shatter"] = _wav(shatter)
	s["unshatter"] = _wav(_reverse(shatter))
	s["infinity"] = _wav(_mix([_glass(0.9), _shimmer(1.0, 300.0, 2400.0, 0.01)]))
	# Menu UI: a soft rising "bwoo" on hover, a quick downward "vwip" on press, and a
	# whooshing rise when a page opens.
	s["ui_hover"] = _wav(_gain(_sweep(0.08, 480.0, 780.0, 0.05, 0.004, 0.8, 1, 0.2), 0.3))
	s["ui_click"] = _wav(_mix([
		_gain(_sweep(0.13, 980.0, 300.0, 0.1, 0.002, 2.0, 1, 0.25), 0.45),
		_gain(_sweep(0.08, 170.0, 80.0, 0.0, 0.002), 0.35),
	]))
	s["ui_page"] = _wav(_mix([
		_gain(_sweep(0.34, 260.0, 1500.0, 0.25, 0.004, 0.6, 1, 0.3), 0.35),
		_gain(_noise(0.32, 0.22, 0.04), 0.22),
	]))
	_set_streams.call_deferred(s.duplicate())
	# Then everything else.
	# Movement.
	s["dash"] = _wav(_mix([
		_sweep(0.55, 900.0, 110.0, 0.55, 0.005, 2.2, 2, 0.12),
		_gain(_sweep(0.5, 180.0, 40.0, 0.0, 0.005, 1.5), 0.7),
	]))
	s["jump"] = _wav(_sweep(0.2, 220.0, 560.0, 0.15, 0.005, 0.7, 2, 0.3))
	s["land_slam"] = _wav(_boom(1.0, 1.2))
	# Weapons in and out: a rising / falling shimmer.
	s["equip"] = _wav(_gain(_shimmer(0.32, 260.0, 1500.0, 0.004), 0.55))
	s["unequip"] = _wav(_gain(_shimmer(0.26, 1400.0, 240.0, 0.004), 0.45))
	# Shots.
	s["zap"] = _wav(_mix([
		_gain(_sweep(0.14, 1500.0, 320.0, 0.25, 0.001, 1.8, 1, 0.35), 0.6),
		_gain(_sweep(0.08, 140.0, 60.0, 0.0, 0.001), 0.5),
	]))
	s["shotgun"] = _wav(_mix([
		_gain(_noise(0.28, 0.45, 0.001), 0.9),
		_sweep(0.24, 160.0, 40.0, 0.0, 0.001, 1.4),
		_gain(_sweep(0.22, 1300.0, 300.0, 0.0, 0.001, 2.0, 2), 0.3),
	]))
	s["vent"] = _wav(_mix([
		_gain(_noise(0.7, 0.7, 0.02), 0.6),
		_gain(_sweep(0.7, 700.0, 180.0, 0.0, 0.02, 1.2, 2), 0.4),
	]))
	s["tether"] = _wav(_mix([
		_gain(_sweep(0.12, 300.0, 1700.0, 0.2, 0.002, 0.6, 2, 0.5), 0.7),
		_delay(_gain(_sweep(0.35, 1700.0, 1500.0, 0.0, 0.002, 1.0, 3), 0.35), 0.1),
	]))
	s["missile"] = _wav(_mix([
		_gain(_noise(0.45, 0.3, 0.01), 0.7),
		_gain(_sweep(0.45, 450.0, 1000.0, 0.0, 0.01, 0.8, 2), 0.35),
	]))
	s["nova"] = _wav(_mix([
		_sweep(1.1, 1400.0, 35.0, 0.4, 0.002, 2.4, 2, 0.2),
		_boom(1.2, 1.1),
	]))
	# Shield and parry.
	s["shield"] = _wav(_mix([
		_shimmer(0.5, 180.0, 900.0, 0.01),
		_gain(_noise(0.45, 0.2, 0.05), 0.35),
	]))
	s["parry"] = _wav(_mix([
		_sweep(1.6, 3200.0, 30.0, 0.6, 0.001, 3.0, 3, 0.25),
		_boom(1.6, 1.4),
		_gain(_shimmer(0.8, 2400.0, 400.0, 0.001), 0.5),
	]))
	# Kills: a heavy downward warp.
	s["kill"] = _wav(_mix([
		_sweep(0.7, 1500.0, 45.0, 0.45, 0.001, 2.0, 2, 0.3),
		_boom(0.6, 0.8),
		_gain(_shimmer(0.5, 1200.0, 150.0, 0.001), 0.3),
	]))
	# Pillars of God: the wind-up, and the biggest blast in the game.
	s["orbital_charge"] = _wav(_orbital_charge())
	s["orbital_impact"] = _wav(_orbital_impact())
	# Loops.
	s["charge"] = _wav(_hum(1.0), true)
	s["wind"] = _wav(_wind(3.0), true)
	SoundCache.save_set("sfx", _key, s)
	_set_streams.call_deferred(s)


## Called twice: with the start screen's sounds, then with all of them.
func _set_streams(s: Dictionary) -> void:
	_streams = s
	if _task >= 0 and s.has("wind"):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	# One-shots get the warp treatment; loops are built smooth already (and must stay seamless).
	if not loop:
		samples = _warp_fx(samples)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## A warp: a tone gliding from f0 to f1 Hz. `curve` > 1 drops fast then settles.
## Sung by three slightly detuned voices with a wobble that grows as it goes, so it bends
## and phases instead of buzzing. `harmonics` adds a little warmth (soft 2nd / 3rd
## overtones, not a buzzy stack); `noise` mixes in a whoosh filtered by `lp` (0..1, higher
## = brighter, softened).
func _sweep(length: float, f0: float, f1: float, noise := 0.0, attack := 0.01, curve := 1.0, harmonics := 1, lp := 0.3) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := [0.0, 0.0, 0.0]
	var detune := [1.0, 1.006, 0.9935]
	var filtered := 0.0
	var filtered2 := 0.0
	var soft := _k(lp * 0.6)
	var wob := randf() * TAU
	for i in n:
		var t := float(i) / n
		var secs := float(i) / RATE
		var f := lerpf(f0, f1, 1.0 - pow(1.0 - t, curve))
		f *= 1.0 + 0.028 * sin(wob + TAU * 6.5 * secs) * (0.3 + t)
		var tone := 0.0
		for v in 3:
			phases[v] += TAU * f * detune[v] / RATE
			var ph: float = phases[v]
			var voice := sin(ph)
			if harmonics > 1:
				voice += 0.18 * sin(ph * 2.0)
			if harmonics > 2:
				voice += 0.06 * sin(ph * 3.0)
			tone += voice
		tone /= 3.0
		filtered += soft * (_n() - filtered)
		filtered2 += soft * (filtered - filtered2)
		var env := minf(float(i) / (attack * RATE), 1.0) * pow(1.0 - t, 2.0)
		out[i] = (tone * (1.0 - noise * 0.5) + filtered2 * noise * 2.6) * env * 0.85
	return out


## The warp every one-shot goes through (_wav): a sweeping flanger (a short delay that
## glides back and forth, fed back on itself: the whoosh/phase that makes it "warpy"), a
## soft low-pass to take the fizz off, and a faint airy echo. A little tail is added so
## the echo isn't cut off.
func _warp_fx(samples: PackedFloat32Array, amount := 1.0) -> PackedFloat32Array:
	var tail := int(0.09 * RATE)
	var n := samples.size() + tail
	var dry := samples.duplicate()
	dry.resize(n)
	var out := PackedFloat32Array()
	out.resize(n)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rate := randf_range(0.6, 1.1)
	var start := randf() * TAU
	var mix := 0.42 * amount
	for i in n:
		var secs := float(i) / RATE
		var d := (1.2 + 4.8 * (0.5 + 0.5 * sin(start + TAU * rate * secs))) * 0.001 * RATE
		var j := float(i) - d
		var delayed := 0.0
		if j >= 1.0:
			var j0 := int(j)
			var fr := j - j0
			delayed = buf[j0] * (1.0 - fr) + buf[j0 + 1] * fr
		buf[i] = dry[i] + delayed * 0.45 * amount
		out[i] = dry[i] + delayed * mix
	# Gentle low-pass (about 10 kHz): smooth, without dulling the detail.
	var a := 1.0 - exp(-TAU * 10000.0 / RATE)
	var lp := 0.0
	for i in n:
		lp += a * (out[i] - lp)
		out[i] = lp
	# Air: two quiet, darker echoes.
	var space := out.duplicate()
	for tap in [[0.031, 0.13], [0.053, 0.08]]:
		var off := int(tap[0] * RATE)
		var dark := 0.0
		for i in range(off, n):
			dark += _k(0.35) * (space[i - off] - dark)
			out[i] += dark * tap[1] * amount
	for i in n:
		out[i] *= 0.82
	return out


## Low thump plus rumbling noise: explosions.
func _boom(length: float, size: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var low := 0.0
	var crackle := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(85.0 / size, 28.0, 1.0 - pow(1.0 - t, 3.0)) / RATE
		low += _k(0.06) * (_n() - low)
		crackle += _k(0.5) * (_n() - crackle)
		var env := minf(float(i) / (0.002 * RATE), 1.0)
		var thump := sin(phase) * pow(1.0 - t, 3.0) * 1.1
		var rumble := low * 3.5 * pow(1.0 - t, 1.6)
		var crack := crackle * 0.5 * pow(maxf(1.0 - t * 5.0, 0.0), 2.0)
		out[i] = (thump + rumble + crack) * env * 0.85
	return out


## Filtered noise with a fast attack and a smooth decay.
func _noise(length: float, lp: float, attack: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var filtered := 0.0
	for i in n:
		var t := float(i) / n
		filtered += _k(lp) * (_n() - filtered)
		var env := minf(float(i) / (attack * RATE), 1.0) * pow(1.0 - t, 2.0)
		out[i] = filtered * env * 1.6
	return out


## Three detuned voices sweeping together, with a wobble: a crystal warp.
func _shimmer(length: float, f0: float, f1: float, attack: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := [0.0, 0.0, 0.0]
	var detune := [1.0, 1.007, 1.498]
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, 1.0 - pow(1.0 - t, 1.8)) * (1.0 + 0.02 * sin(t * 90.0))
		var v := 0.0
		for k in 3:
			phases[k] += TAU * f * detune[k] / RATE
			v += sin(phases[k]) * (0.6 if k < 2 else 0.3)
		var env := minf(float(i) / (attack * RATE), 1.0) * pow(sin(PI * t), 0.6)
		out[i] = v * env * 0.5
	return out


## Glassy shatter, warped: a spray of glints that each bend downward as they ring out
## (lower and softer than plain pings), over a falling whoosh.
func _glass(length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in 22:
		var start := int(pow(randf(), 1.8) * n * 0.65)
		var f := randf_range(900.0, 3600.0)
		var dur := int(randf_range(0.06, 0.24) * RATE)
		var amp := randf_range(0.1, 0.26)
		var bend := randf_range(0.45, 0.75)
		var phase := 0.0
		for j in dur:
			var i := start + j
			if i >= n:
				break
			var u := float(j) / dur
			phase += TAU * f * lerpf(1.0, bend, 1.0 - pow(1.0 - u, 2.0)) / RATE
			out[i] += (sin(phase) + 0.3 * sin(phase * 1.007)) * amp * pow(1.0 - u, 2.4) * minf(j / (0.002 * RATE), 1.0)
	# The break itself: a soft, falling whoosh instead of a crunch.
	var whoosh := _sweep(0.3, 1400.0, 260.0, 0.7, 0.002, 1.8, 1, 0.3)
	for i in mini(whoosh.size(), n):
		out[i] += whoosh[i] * 0.45
	return out


## Seamless 1s hum for charging: every frequency fits a whole number of cycles.
func _hum(length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# A slow, phasing warble (no fast tremolo, which buzzed): voices a cycle apart drift in
	# and out of phase, the pitch bends gently twice a second, and it swells once a loop.
	for i in n:
		var t := float(i) / RATE
		var bend := 0.9 * sin(TAU * 2.0 * t)
		var v := sin(TAU * 110.0 * t + bend) * 0.5 + sin(TAU * 111.0 * t - bend) * 0.42
		v += sin(TAU * 165.0 * t + bend * 1.5) * 0.18 + sin(TAU * 221.0 * t) * 0.08
		v *= 0.8 + 0.2 * sin(TAU * 1.0 * t)
		out[i] = v * 0.45
	return out


## Rushing air for speed: noise with a slow swell, crossfaded so the loop has no seam.
func _wind(length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var fade := int(0.5 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var a := 0.0
	var b := 0.0
	for i in raw.size():
		a += _k(0.05) * (_n() - a)
		b += _k(0.25) * (_n() - b)
		var t := float(i) / RATE
		raw[i] = a * 3.0 + b * 0.6 * (0.6 + 0.4 * sin(t * 2.3))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	for i in fade:
		var k := float(i) / fade
		out[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	for i in n:
		out[i] *= 0.5
	return out


## The kill explosion after the impact frames: a white-noise crack, a punch, a sub-bass
## drop that keeps falling, a long rumble, falling debris, a downward shimmer, and two
## echoes off the arena walls. Driven hard so it hits as loud as the format allows.
func _impact_boom() -> PackedFloat32Array:
	var n := int(2.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var sub_phase := 0.0
	var punch_phase := 0.0
	var rumble := 0.0
	var rumble2 := 0.0
	for i in n:
		var t := float(i) / RATE
		# Crack: a few ms of pure noise.
		var crack := randf_range(-1.0, 1.0) * exp(-t * 90.0) * 1.6
		# Punch: 140 -> 40 Hz in a tenth of a second.
		punch_phase += TAU * lerpf(140.0, 40.0, clampf(t / 0.12, 0.0, 1.0)) / RATE
		var punch := sin(punch_phase) * exp(-t * 9.0) * 1.4
		# Sub drop: 55 -> 18 Hz over two seconds.
		sub_phase += TAU * lerpf(55.0, 18.0, clampf(t / 2.0, 0.0, 1.0)) / RATE
		var sub := sin(sub_phase) * exp(-t * 1.6) * 1.2
		# Rumble: two layers of filtered noise, slow to fade.
		rumble += _k(0.04) * (_n() - rumble)
		rumble2 += _k(0.15) * (_n() - rumble2)
		var roar := (rumble * 5.0 + rumble2 * 0.8) * exp(-t * 1.3) * minf(t * 60.0, 1.0)
		# Debris: sparse clicks that thin out.
		var debris := 0.0
		if randf() < 0.004 * exp(-t * 1.5):
			debris = randf_range(-1.0, 1.0) * 0.9
		out[i] = crack + punch + sub + roar + debris
	# Downward shimmer over the top.
	var shimmer := _shimmer(1.4, 3000.0, 180.0, 0.001)
	for i in shimmer.size():
		out[i] += shimmer[i] * 0.35
	# Echoes off the arena walls.
	var dry := out.duplicate()
	for echo in [[0.19, 0.45], [0.41, 0.25]]:
		var offset := int(echo[0] * RATE)
		for i in range(offset, n):
			out[i] += dry[i - offset] * echo[1]
	return _drive(out, 1.5)


## Orbital strike wind-up (1.6s): a sub drone climbing, a detuned whine screaming up,
## rising static, a tremolo that speeds up, and a reversed crack sucking in at the end.
func _orbital_charge() -> PackedFloat32Array:
	var length := 1.6
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var sub_phase := 0.0
	var whine := [0.0, 0.0, 0.0]
	var detune := [1.0, 1.012, 1.5]
	var hiss := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / length
		sub_phase += TAU * lerpf(28.0, 75.0, k * k) / RATE
		var sub := sin(sub_phase) * (0.3 + 0.8 * k)
		var f := lerpf(250.0, 4200.0, pow(k, 2.5))
		var w := 0.0
		for v in 3:
			whine[v] += TAU * f * detune[v] / RATE
			w += sin(whine[v]) * (0.4 if v < 2 else 0.2)
		w *= pow(k, 1.5) * 0.6
		hiss += _k(lerpf(0.15, 0.8, k)) * (_n() - hiss)
		var noise := hiss * pow(k, 3.0) * 1.2
		# A wobble that speeds up (capped well below a buzz).
		var trem := 0.75 + 0.25 * sin(TAU * lerpf(2.0, 11.0, k * k) * t)
		out[i] = (sub + w + noise) * trem * minf(t * 20.0, 1.0)
	# The crack, reversed, landing right at the end.
	var crack := _reverse(_noise(0.18, 0.9, 0.001))
	var start := n - crack.size()
	for i in crack.size():
		out[start + i] += crack[i] * 1.3
	return _drive(out, 1.3)


## Orbital strike impact (4.5s): the sky tearing open (a noisy sweep plunging from 5kHz),
## a crack, a deep punch, a sub drop that keeps falling for seconds, a long two-layer
## roar, falling debris, a glassy downward shimmer, and three echoes rolling across the
## map. Driven as hard as it'll go.
func _orbital_impact() -> PackedFloat32Array:
	var n := int(4.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var tear_phase := 0.0
	var tear_noise := 0.0
	var punch_phase := 0.0
	var sub_phase := 0.0
	var rumble := 0.0
	var rumble2 := 0.0
	for i in n:
		var t := float(i) / RATE
		tear_phase += TAU * lerpf(5000.0, 40.0, clampf(pow(t / 0.6, 0.5), 0.0, 1.0)) / RATE
		tear_noise += _k(0.6) * (_n() - tear_noise)
		var tear := (sin(tear_phase) * 0.5 + tear_noise * 0.8) * exp(-t * 5.0)
		var crack := randf_range(-1.0, 1.0) * exp(-t * 60.0) * 1.8
		punch_phase += TAU * lerpf(160.0, 30.0, clampf(t / 0.18, 0.0, 1.0)) / RATE
		var punch := sin(punch_phase) * exp(-t * 6.0) * 1.6
		sub_phase += TAU * lerpf(50.0, 12.0, clampf(t / 3.5, 0.0, 1.0)) / RATE
		var sub := sin(sub_phase) * exp(-t * 0.9) * 1.4
		rumble += _k(0.03) * (_n() - rumble)
		rumble2 += _k(0.12) * (_n() - rumble2)
		var roar := (rumble * 6.0 + rumble2 * 1.0) * exp(-t * 0.8) * minf(t * 40.0, 1.0)
		var debris := 0.0
		if randf() < 0.006 * exp(-t * 0.9):
			debris = randf_range(-1.0, 1.0)
		out[i] = tear + crack + punch + sub + roar + debris
	var shimmer := _shimmer(2.2, 4000.0, 100.0, 0.001)
	for i in shimmer.size():
		out[i] += shimmer[i] * 0.45
	var dry := out.duplicate()
	for echo in [[0.25, 0.5], [0.55, 0.35], [0.95, 0.2]]:
		var offset := int(echo[0] * RATE)
		for i in range(offset, n):
			out[i] += dry[i - offset] * echo[1]
	return _drive(out, 1.8)


## A one-pole filter strength c tuned at 22.05 kHz, at this sample rate (so every
## sound keeps the tone it was designed with).
static func _k(c: float) -> float:
	return 1.0 - pow(1.0 - clampf(c, 0.0, 0.999), 22050.0 / RATE)


## White noise for those filters, scaled so the filtered result stays as loud as at
## 22.05 kHz.
static func _n() -> float:
	return randf_range(-1.0, 1.0) * sqrt(float(RATE) / 22050.0)


## Heavy soft clipping: louder overall, peaks rounded off instead of crackling.
func _drive(samples: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var norm := tanh(amount)
	for i in samples.size():
		samples[i] = tanh(samples[i] * amount) / norm
	return samples


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	# Soft clip so stacked layers stay loud without harsh clipping.
	for i in n:
		out[i] = tanh(out[i] * 1.1)
	return out


func _gain(samples: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in samples.size():
		samples[i] *= g
	return samples


func _delay(samples: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var pad := PackedFloat32Array()
	pad.resize(int(seconds * RATE))
	pad.append_array(samples)
	return pad


func _reverse(samples: PackedFloat32Array) -> PackedFloat32Array:
	var out := samples.duplicate()
	out.reverse()
	return out
