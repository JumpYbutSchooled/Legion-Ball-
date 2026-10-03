extends RefCounted
## Keeps the synthesized sounds and music on disk (user://sound_cache/<set>/), so they're
## built once (a few seconds, the first time a version runs) and just loaded after that.
## `key` says what built them (the game version and the generator's source): when it
## changes, the old files are ignored and rebuilt.

const ROOT := "user://sound_cache/"


## The saved streams of `set_name` built with `key`, or {} if there are none.
static func load_set(set_name: String, key: String) -> Dictionary:
	var dir := ROOT + set_name + "/"
	var manifest := FileAccess.open(dir + "key.txt", FileAccess.READ)
	if not manifest:
		return {}
	var lines := manifest.get_as_text().split("\n")
	if lines.size() < 2 or lines[0] != key:
		return {}
	var out := {}
	for sound in lines[1].split(",", false):
		var stream := ResourceLoader.load(dir + sound + ".res", "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
		if not stream:
			return {}  # something's missing: build them all again
		out[sound] = stream
	return out


## Saves `streams` (name -> AudioStream) as `set_name` with `key`. Safe from a worker thread.
static func save_set(set_name: String, key: String, streams: Dictionary) -> void:
	var dir := ROOT + set_name + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	for sound in streams:
		if ResourceSaver.save(streams[sound], dir + String(sound) + ".res") != OK:
			return
	# The manifest last, so a half-written set is never mistaken for a whole one.
	var manifest := FileAccess.open(dir + "key.txt", FileAccess.WRITE)
	if manifest:
		manifest.store_string(key + "\n" + ",".join(PackedStringArray(streams.keys())))


## What identifies a build of `script`'s sounds: the game version, the sample rate and
## (when running from source) a hash of the generator itself.
static func key_for(script: Script, rate: int) -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	var version := f.get_as_text().strip_edges() if f else "?"
	return "%s|%d|%d" % [version, rate, script.source_code.hash() if script else 0]
