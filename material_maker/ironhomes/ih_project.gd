class_name IHProject
extends RefCounted

## The Unity project Material Maker works in, for Iron Homes (its docs/layered-materials.md).
##
## A material is <name>.ptex anywhere in the project's library, with what Save bakes beside it:
## <name>.json and its textures. Folders only keep materials in order; a name is unique across the
## whole library and never changes once made, because Houdini nodes and Unity's base__coat
## materials refer to it by name.

const SECTION := "ironhomes"
const ROOT := "Assets/Materials/Layered"  ## library.json and the wear trim, beside the library
const INDEX := "library.json"
const TARGET := "Iron Homes"  ## the export target of material.mmg that bakes for the library
## What a bake writes beside <name>.ptex (the export target's files).
const BAKED := ["_albedo.png", "_mask.png", "_normal.png", ".json"]
## A Houdini node name, lower case; "__" is how a face names its base and its coat together.
const NAME_RULE := "^[a-z][a-z0-9_]*$"
const RESERVED := ["none"]
## Folders never searched for Houdini scenes: Unity's caches and the like.
const SKIP_DIRS := ["Library", "Temp", "Logs", "obj", "Build", "Builds", "UserSettings", "Packages", "backup", "node_modules"]
const HIP_EXTENSIONS := ["hip", "hiplc", "hipnc"]


# --- the project --------------------------------------------------------------------------------

static func project() -> String:
	return mm_globals.config.get_value(SECTION, "project", "")

static func set_project(path : String) -> void:
	mm_globals.config.set_value(SECTION, "project", path)
	mm_globals.config.save("user://mm_config.ini")

## A Unity project is a folder with Assets in it.
static func is_unity_project(path : String) -> bool:
	return path != "" and DirAccess.dir_exists_absolute(path.path_join("Assets"))

static func is_open() -> bool:
	return is_unity_project(project())

static func root() -> String:
	return project().path_join(ROOT)

## The library folder: library.json says where, relative to itself ("Library" when it does not).
static func library() -> String:
	var where := "Library"
	var index : String = root().path_join(INDEX)
	if FileAccess.file_exists(index):
		var data = JSON.parse_string(FileAccess.get_file_as_string(index))
		if data is Dictionary and data.has("library"):
			where = data.library
	return root().path_join(where).simplify_path()

## Makes the library folder (and a library.json saying where it is) if the project has neither.
static func ensure_library() -> void:
	DirAccess.make_dir_recursive_absolute(library())
	var index : String = root().path_join(INDEX)
	if not FileAccess.file_exists(index):
		var f := FileAccess.open(index, FileAccess.WRITE)
		f.store_string(JSON.stringify({ library="Library" }, "    ") + "\n")

static func in_library(path : String) -> bool:
	return is_open() and path.simplify_path().begins_with(library() + "/")


# --- materials ----------------------------------------------------------------------------------

## Every material's .ptex in the library, by its lower-case name.
static func materials() -> Dictionary:
	var found := {}
	if is_open():
		_collect(library(), found)
	return found

static func _collect(dir : String, found : Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "ptex":
			var key : String = f.get_basename().to_lower()
			if not found.has(key):
				found[key] = dir.path_join(f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), found)

## Why a name cannot be a new material's, or "" when it can.
static func check_name(material_name : String) -> String:
	if not RegEx.create_from_string(NAME_RULE).search(material_name):
		return "A name is lower-case letters, digits and _, starting with a letter."
	if material_name.contains("__"):
		return "A name cannot hold \"__\": it joins a base and a coat."
	if material_name in RESERVED:
		return "\"%s\" means no coat." % material_name
	if materials().has(material_name.to_lower()):
		return "There is a material called %s already: %s" % [ material_name, materials()[material_name.to_lower()] ]
	return ""

## A new material's graph: a Material node and nothing else, its tile a metre.
static func new_graph() -> Dictionary:
	return {
		name="Material", type="graph", label="Graph", node_position={ x=0, y=0 }, parameters={},
		nodes=[ { name="Material", type="material", node_position={ x=0, y=0 }, parameters={ size=10, tile_metres=1.0 } } ],
		connections=[]
	}

## Writes a new material in a folder of the library; answers its path.
static func create(folder : String, material_name : String, data : Dictionary = new_graph()) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	var path : String = folder.path_join(material_name + ".ptex")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", true))
	return path

## The files a material is: its graph, what it bakes, and the .meta Unity keeps for each.
static func files_of(ptex : String) -> PackedStringArray:
	var out := PackedStringArray([ ptex ])
	for suffix in BAKED:
		out.append(ptex.get_basename() + suffix)
	var with_meta := PackedStringArray()
	for f in out:
		with_meta.append(f)
		with_meta.append(f + ".meta")
	return with_meta

static func delete(ptex : String) -> void:
	for f in files_of(ptex):
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# --- where a material is used -------------------------------------------------------------------

## Every place a material is used, by where it is: Houdini nodes that name it in a scene of the
## project, and what Unity made from it — a base__coat material, a model or a piece naming one.
## Answers { "Houdini: houdini/iron homes.hiplc": [ "/obj/...", ... ], "Unity": [ ... ] }.
static func usages(material_name : String) -> Dictionary:
	var out := {}
	if not is_open():
		return out
	for hip in _files_with(project(), HIP_EXTENSIONS):
		var nodes := _hip_nodes_naming(hip, material_name)
		if not nodes.is_empty():
			out["Houdini: " + hip.trim_prefix(project() + "/")] = nodes
	var unity := PackedStringArray()
	var generated : String = root().path_join("Generated")
	if DirAccess.dir_exists_absolute(generated):
		for f in DirAccess.get_files_at(generated):
			if f.get_extension() == "mat" and _combination_names(f.get_basename(), material_name):
				unity.append("material " + f.get_basename())
	var needle_a : String = (material_name + "__").to_utf8_buffer().hex_encode()
	var needle_b : String = ("__" + material_name).to_utf8_buffer().hex_encode()
	for f in _files_with(project().path_join("Assets"), [ "fbx", "asset" ]):
		var hex : String = FileAccess.get_file_as_bytes(f).hex_encode()
		if _byte_find(hex, needle_a) >= 0 or _byte_find(hex, needle_b) >= 0:
			unity.append(f.trim_prefix(project() + "/"))
	if not unity.is_empty():
		out["Unity"] = unity
	return out

static func _combination_names(combination : String, material_name : String) -> bool:
	var parts := combination.split("__")
	return parts.size() == 2 and (parts[0] == material_name or parts[1] == material_name)

static func _files_with(dir : String, extensions : Array) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in extensions:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d in SKIP_DIRS or d.begins_with("."):
			continue
		out.append_array(_files_with(dir.path_join(d), extensions))
	return out

## The nodes of a Houdini scene whose material parameter (IH Base Material, IH Coat) or default
## base (IH Layered Out) is this material. A hip keeps each node's parameters as plain text:
##   <node path>.parm\0{ ... material\t[ 0\tlocks=0 ]\t(\tpaint_red\t) ... }
static func _hip_nodes_naming(hip : String, material_name : String) -> PackedStringArray:
	var out := PackedStringArray()
	var hex : String = FileAccess.get_file_as_bytes(hip).hex_encode()
	var value : String = ("\t(\t" + material_name + "\t)").to_utf8_buffer().hex_encode()
	var parm_end : String = ".parm".to_utf8_buffer().hex_encode() + "00"
	var at := _byte_find(hex, value)
	while at >= 0:
		var line_start : int = _byte_rfind(hex, "0a", at)
		var parm_name : String = _bytes_text(hex, line_start + 2 if line_start >= 0 else 0, at).split("\t")[0]
		if parm_name in [ "material", "default_base" ]:
			var block : int = _byte_rfind(hex, parm_end, at)
			if block >= 0:
				var path := _path_before(hex, block)
				if path != "" and not out.has("/" + path):
					out.append("/" + path)
		at = _byte_find(hex, value, at + 2)
	return out

static func _byte_find(hex : String, needle : String, from : int = 0) -> int:
	var at := hex.find(needle, from)
	while at >= 0 and at % 2 == 1:
		at = hex.find(needle, at + 1)
	return at

static func _byte_rfind(hex : String, needle : String, before : int) -> int:
	var at := hex.rfind(needle, before)
	while at >= 0 and at % 2 == 1:
		at = hex.rfind(needle, at - 1)
	return at

static func _bytes_text(hex : String, from : int, to : int) -> String:
	return hex.substr(from, to - from).hex_decode().get_string_from_utf8()

## The node path that ends where a ".parm" header begins: the run of path characters before it,
## from the network it starts with (obj/, mat/ ...), whatever header bytes precede that.
static func _path_before(hex : String, end : int) -> String:
	var start := end
	while start >= 2:
		var c : int = hex.substr(start - 2, 2).hex_to_int()
		var ok : bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c in [ 95, 47, 46, 45 ]
		if not ok:
			break
		start -= 2
	var text := _bytes_text(hex, start, end)
	var found := RegEx.create_from_string("(obj|mat|out|stage|shop|ch|img|tasks)/[A-Za-z0-9_./-]+$").search(text)
	return found.get_string() if found else ""
