extends RefCounted
## Every past update, from res://changelog.json (shipped in each update; tools/publish.ps1
## adds the new entry every time a version is published). Newest first:
## [{"version": "0.8.7", "date": "2026-09-26", "notes": "..."}, ...]

const PATH := "res://changelog.json"


static func entries() -> Array:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if not f:
		return []
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_ARRAY:
		return []
	var out: Array = []
	for e in data:
		if typeof(e) == TYPE_DICTIONARY and e.has("version"):
			out.append(e)
	return out


## Entries newer than `version` (all of them if it's ""), newest first.
static func since(version: String) -> Array:
	var out: Array = []
	for e in entries():
		if version == "" or newer(String(e["version"]), version):
			out.append(e)
	return out


## True if version `a` is newer than `b` ("0.8.10" > "0.8.9").
static func newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false
