# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Starts the Unciv bridge when nobody else has. Development runs use the Unciv repo next to this project;
## portable Windows builds use their bundled bridge jar, assets and Java runtime. Output goes to user://logs.

## A bridge we launched quits by itself once no client has been connected for this long, so one orphaned
## by a crash or a force-stop from the editor doesn't keep running (and serving old code) for days.
const IDLE_EXIT_SECONDS := 180

var pid := -1
var log_path := ""
var error := ""


func unciv_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../unciv").simplify_path()


## Returns true if a launch was started. On failure, [member error] says why.
## More arguments for the bridge (" --debug" for --autoplay, whose AI turns go through a debug command)
var extra_args := ""


func launch(port: int) -> bool:
	var logs := ProjectSettings.globalize_path("user://logs")
	var unciv := unciv_dir()
	DirAccess.make_dir_recursive_absolute(logs)
	# Its own log when it isn't on the usual port (an autoplay run next to a game you are playing)
	log_path = logs.path_join("bridge.log" if port == 8765 else "bridge-%d.log" % port)

	if OS.get_name() == "Windows":
		var app_dir := OS.get_executable_path().get_base_dir()
		var packaged_runtime := app_dir.path_join("runtime/bin/java.exe")
		var packaged_jar := app_dir.path_join("bridge/UncivBridge.jar")
		if FileAccess.file_exists(packaged_jar) or DirAccess.dir_exists_absolute(app_dir.path_join("runtime")):
			var packaged_assets := ProjectSettings.globalize_path("user://data/unciv/android/assets")
			if not FileAccess.file_exists(packaged_runtime) or not FileAccess.file_exists(packaged_jar) or not DirAccess.dir_exists_absolute(packaged_assets.path_join("jsons")):
				error = "The bundled Unciv bridge is incomplete. Reinstall the game files."
				return false
			return _launch_packaged_windows(packaged_runtime, packaged_jar, packaged_assets, port, logs)

		if not DirAccess.dir_exists_absolute(unciv.path_join("bridge")):
			error = "Can't find the Unciv repo with the bridge at %s" % unciv
			return false

		# A small batch file keeps all the quoting under our control. We pick the JDK ourselves because
		# our own environment can be stale (Windows only hands new variables to newly started programs).
		var jdk := find_jdk()
		if jdk == "":
			error = "No Java 17 or newer found (Unciv needs JDK 21). Install it and set JAVA_HOME."
			return false
		print("Launching the bridge with the JDK in ", jdk)
		var bat := logs.path_join("start_bridge.bat")
		var script := "\r\n".join([
			"@echo off",
			"set \"JAVA_HOME=%s\"" % jdk.replace("/", "\\"),
			"cd /d \"%s\"" % unciv.replace("/", "\\"),
			"call gradlew.bat :bridge:run --console=plain --args=\"--port %d --exit-when-idle %d%s\" > \"%s\" 2>&1" % [port, IDLE_EXIT_SECONDS, extra_args, log_path.replace("/", "\\")],
		]) + "\r\n"
		var file := FileAccess.open(bat, FileAccess.WRITE)
		if file == null:
			error = "Couldn't write %s" % bat
			return false
		file.store_string(script)
		file.close()
		pid = OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	else:
		if not DirAccess.dir_exists_absolute(unciv.path_join("bridge")):
			error = "Can't find the Unciv repo with the bridge at %s" % unciv
			return false
		var command := "cd '%s' && ./gradlew :bridge:run --console=plain --args='--port %d --exit-when-idle %d%s' > '%s' 2>&1" % [unciv, port, IDLE_EXIT_SECONDS, extra_args, log_path]
		pid = OS.create_process("sh", ["-c", command])

	if pid <= 0:
		error = "Couldn't start Gradle"
		return false
	return true


## Starts the prebuilt bridge from a portable Windows package, without Gradle or a system Java install.
func _launch_packaged_windows(java_exe: String, bridge_jar: String, assets: String, port: int, logs: String) -> bool:
	var bat := logs.path_join("start_bridge.bat")
	var script := "\r\n".join([
		"@echo off",
		"cd /d \"%s\"" % assets.replace("/", "\\"),
		"\"%s\" -Xmx4G -jar \"%s\" --port %d --exit-when-idle %d > \"%s\" 2>&1" % [java_exe.replace("/", "\\"), bridge_jar.replace("/", "\\"), port, IDLE_EXIT_SECONDS, log_path.replace("/", "\\")],
	]) + "\r\n"
	var file := FileAccess.open(bat, FileAccess.WRITE)
	if file == null:
		error = "Couldn't write %s" % bat
		return false
	file.store_string(script)
	file.close()
	pid = OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	if pid <= 0:
		error = "Couldn't start the bundled Unciv bridge"
		return false
	return true


## Finds a JDK that can run Gradle (17+; Unciv itself wants 21), preferring the newest.
## Looks at JAVA_HOME, the JAVA_HOME saved in the registry (newer than our own environment
## if it was changed after this program started), and the usual install folders.
func find_jdk() -> String:
	var candidates: Array[String] = []
	candidates.append(OS.get_environment("JAVA_HOME"))
	if OS.get_name() == "Windows":
		for key in ["HKCU\\Environment", "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"]:
			var output: Array = []
			OS.execute("reg", ["query", key, "/v", "JAVA_HOME"], output)
			for line: String in "".join(output).split("\n"):
				var at := line.find("REG_")
				if line.strip_edges().begins_with("JAVA_HOME") and at >= 0:
					var value := line.substr(at).split(" ", false, 1)
					if value.size() > 1:
						candidates.append(value[1].strip_edges())
		for root in ["C:/Program Files/Eclipse Adoptium", "C:/Program Files/Java", "C:/Program Files/Microsoft",
				"C:/Program Files/Zulu", "C:/Program Files/Amazon Corretto", "C:/Program Files/BellSoft"]:
			if not DirAccess.dir_exists_absolute(root):
				continue
			for dir in DirAccess.get_directories_at(root):
				candidates.append(root.path_join(dir))
	var best := ""
	var best_version := 0
	for home in candidates:
		var version := _jdk_major_version(home)
		print("  JDK candidate %s -> %s" % [home, str(version) if version > 0 else "not usable"])
		if version >= 17 and version > best_version:
			best = home
			best_version = version
	return best


## Major Java version of the JDK at [param home], read from its 'release' file; 0 if it isn't one.
func _jdk_major_version(home: String) -> int:
	if home.strip_edges() == "":
		return 0
	var release := home.path_join("release")
	if not FileAccess.file_exists(release):
		return 0
	for line in FileAccess.get_file_as_string(release).split("\n"):
		if line.begins_with("JAVA_VERSION="):
			var version := line.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			var major := version.get_slice(".", 0)
			if major == "1":   # "1.8.0_x" style
				major = version.get_slice(".", 1)
			return major.to_int()
	return 0


## Kills the Gradle launcher process (the bridge itself is stopped with the 'shutdown' message first).
func stop() -> void:
	if pid > 0:
		if OS.get_name() == "Windows":
			OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"])
		else:
			OS.kill(pid)
		pid = -1


## The last few lines of the bridge log, to show the user what went wrong.
func log_tail(lines := 8) -> String:
	if log_path == "" or not FileAccess.file_exists(log_path):
		return ""
	var text := FileAccess.get_file_as_string(log_path).strip_edges()
	var all := text.split("\n")
	return "\n".join(all.slice(maxi(0, all.size() - lines)))
