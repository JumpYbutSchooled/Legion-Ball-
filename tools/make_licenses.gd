extends SceneTree
## Writes THIRD_PARTY_LICENSES.txt (Godot, the libraries built into it, and GodotSteam),
## which their MIT-style licenses require shipping with the game. tools\build_steam.ps1
## runs it into the depot folder:
##   godot --headless --path . --script tools/make_licenses.gd -- <output file>

const GODOTSTEAM_LICENSE := "res://addons/godotsteam/license.md"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "THIRD_PARTY_LICENSES.txt"
	var out := PackedStringArray()
	out.append("Legion Ball uses the following third-party software.\n")
	out.append("=".repeat(72))
	out.append("Godot Engine (godotengine.org)\n")
	out.append(Engine.get_license_text())
	out.append("=".repeat(72))
	out.append("GodotSteam (godotsteam.com)\n")
	out.append(FileAccess.get_file_as_string(GODOTSTEAM_LICENSE))
	out.append("=".repeat(72))
	out.append("Steamworks SDK (steam_api64.dll) is distributed under the Steamworks SDK Access Agreement.\n")
	out.append("=".repeat(72))
	out.append("Components built into Godot Engine\n")
	var licenses := Engine.get_license_info()
	for part in Engine.get_copyright_info():
		out.append("- " + String(part["name"]))
		for piece in part["parts"]:
			for line in piece["copyright"]:
				out.append("    Copyright " + String(line))
			out.append("    License: " + String(piece["license"]))
	out.append("\n" + "=".repeat(72))
	out.append("License texts\n")
	for name in licenses:
		out.append("-".repeat(72))
		out.append(String(name) + "\n")
		out.append(String(licenses[name]))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_error("Can't write %s" % path)
		quit(1)
		return
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("Wrote %s" % path)
	quit()
