extends PanelContainer

## The Materials panel: the project's library (IHProject) as its folders and materials, each with
## its thumbnail. A click on a material opens it, or brings its tab forward; New, Folder, Clone and
## Delete change the library. It reads the library again whenever the window comes back to front,
## since Unity, git or a file browser may have changed it meanwhile.

const THUMBNAIL := 56
const MAX_LISTED := 24  ## places a delete warning lists before it only counts the rest

@onready var tree : Tree = %Tree
@onready var project_label : Label = %Project

var thumbnails := {}  ## ptex path -> [modified time and size, texture]


func _ready() -> void:
	tree.set_column_expand(0, true)
	tree.item_mouse_selected.connect(_on_item_clicked)
	tree.item_activated.connect(_on_item_activated)
	%New.pressed.connect(new_material)
	%Folder.pressed.connect(new_folder)
	%Clone.pressed.connect(clone_material)
	%Delete.pressed.connect(delete_selected)
	%Refresh.pressed.connect(refresh)
	refresh()

func _notification(what : int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_inside_tree():
		refresh()


# --- the tree -----------------------------------------------------------------------------------

func refresh() -> void:
	var selected : String = _selected_path()
	var collapsed := {}
	_remember_collapsed(tree.get_root(), collapsed)
	tree.clear()
	var buttons_on : bool = IHProject.is_open()
	for b in [ %New, %Folder, %Clone, %Delete ]:
		b.disabled = not buttons_on
	if not IHProject.is_open():
		project_label.text = "No project. File > Load project..."
		return
	project_label.text = IHProject.project().get_file()
	project_label.tooltip_text = IHProject.library()
	IHProject.ensure_library()
	var root : TreeItem = tree.create_item()
	root.set_metadata(0, { folder=IHProject.library() })
	_fill(root, IHProject.library(), collapsed)
	_select(tree.get_root(), selected)

func _fill(parent : TreeItem, dir : String, collapsed : Dictionary) -> void:
	var dirs := Array(DirAccess.get_directories_at(dir))
	dirs.sort()
	for d in dirs:
		var item : TreeItem = tree.create_item(parent)
		var path : String = dir.path_join(d)
		item.set_text(0, d)
		item.set_metadata(0, { folder=path })
		item.set_icon(0, get_theme_icon("Folder", "EditorIcons") if has_theme_icon("Folder", "EditorIcons") else null)
		_fill(item, path, collapsed)
		item.collapsed = collapsed.has(path)
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if f.get_extension() != "ptex":
			continue
		var path : String = dir.path_join(f)
		var item : TreeItem = tree.create_item(parent)
		item.set_text(0, f.get_basename())
		item.set_metadata(0, { material=path })
		item.set_tooltip_text(0, path.trim_prefix(IHProject.library() + "/"))
		var thumbnail := _thumbnail(path)
		if thumbnail:
			item.set_icon(0, thumbnail)
			item.set_icon_max_width(0, THUMBNAIL)

## The thumbnail a .ptex keeps (Save renders it: a plane), read again only when the file changes.
func _thumbnail(path : String) -> Texture2D:
	# a save can land in the same second as the file was made: its size tells them apart
	var modified := "%d %d" % [ FileAccess.get_modified_time(path), FileAccess.get_file_as_bytes(path).size() ]
	if thumbnails.has(path) and thumbnails[path][0] == modified:
		return thumbnails[path][1]
	var texture : Texture2D = null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.has("project_thumbnail"):
		var image := Image.new()
		if image.load_webp_from_buffer(Marshalls.base64_to_raw(data.project_thumbnail)) == OK:
			texture = ImageTexture.create_from_image(image)
	thumbnails[path] = [ modified, texture ]
	return texture

func _remember_collapsed(item : TreeItem, into : Dictionary) -> void:
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta is Dictionary and meta.has("folder") and item.collapsed and item != tree.get_root():
		into[meta.folder] = true
	for child in item.get_children():
		_remember_collapsed(child, into)

func _select(item : TreeItem, path : String) -> void:
	if item == null or path == "":
		return
	var meta = item.get_metadata(0)
	if meta is Dictionary and (meta.get("material", "") == path or meta.get("folder", "") == path):
		item.select(0)
		return
	for child in item.get_children():
		_select(child, path)

func _selected_path() -> String:
	var item : TreeItem = tree.get_selected()
	if item == null:
		return ""
	var meta = item.get_metadata(0)
	return meta.get("material", meta.get("folder", "")) if meta is Dictionary else ""

func _selected_material() -> String:
	var item : TreeItem = tree.get_selected()
	var meta = item.get_metadata(0) if item else null
	return meta.get("material", "") if meta is Dictionary else ""

## The folder new things go in: the selected one, or the selected material's, or the library.
func _selected_folder() -> String:
	var item : TreeItem = tree.get_selected()
	var meta = item.get_metadata(0) if item else null
	if meta is Dictionary:
		if meta.has("folder"):
			return meta.folder
		return meta.material.get_base_dir()
	return IHProject.library()

func _on_item_clicked(_position : Vector2, button : int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_open_selected()

func _on_item_activated() -> void:
	_open_selected()

func _open_selected() -> void:
	var path := _selected_material()
	if path != "":
		mm_globals.main_window.open_material(path)

## Brings the tree's selection to the material shown in the current tab.
func show_material(path : String) -> void:
	_select(tree.get_root(), path)


# --- changing the library -----------------------------------------------------------------------

func _ask_name(title : String, label : String, value : String) -> String:
	while true:
		var dialog = preload("res://material_maker/windows/line_dialog/line_dialog.tscn").instantiate()
		dialog.content_scale_factor = mm_globals.ui_scale_factor()
		dialog.min_size = Vector2(320, 90) * dialog.content_scale_factor
		add_child(dialog)
		var status = await dialog.enter_text(title, label, value)
		if not status.ok:
			return ""
		var why : String = IHProject.check_name(status.text)
		if why == "":
			return status.text
		await mm_globals.main_window.accept_dialog(why, false, true)
		value = status.text
	return ""

func new_material() -> void:
	if not IHProject.is_open():
		return
	var material_name := await _ask_name("New material", "Name (unique in the library, never changed):", "")
	if material_name == "":
		return
	var path := IHProject.create(_selected_folder(), material_name)
	refresh()
	await mm_globals.main_window.open_material(path)
	await mm_globals.main_window.save_material()   # bakes it, so Houdini and Unity see it at once

func new_folder() -> void:
	if not IHProject.is_open():
		return
	var dialog = preload("res://material_maker/windows/line_dialog/line_dialog.tscn").instantiate()
	dialog.content_scale_factor = mm_globals.ui_scale_factor()
	dialog.min_size = Vector2(320, 90) * dialog.content_scale_factor
	add_child(dialog)
	var status = await dialog.enter_text("New folder", "Folder name:", "")
	if not status.ok or status.text.strip_edges() == "" or status.text.contains("/"):
		return
	DirAccess.make_dir_recursive_absolute(_selected_folder().path_join(status.text.strip_edges()))
	refresh()

func clone_material() -> void:
	var source := _selected_material()
	if source == "":
		await mm_globals.main_window.accept_dialog("Select the material to clone.")
		return
	var material_name := await _ask_name("Clone %s" % source.get_file().get_basename(),
			"Name of the copy (unique in the library, never changed):", source.get_file().get_basename() + "_copy")
	if material_name == "":
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not data is Dictionary:
		await mm_globals.main_window.accept_dialog("Cannot read " + source)
		return
	data.erase("project_thumbnail")
	var path := IHProject.create(source.get_base_dir(), material_name, data)
	refresh()
	await mm_globals.main_window.open_material(path)
	await mm_globals.main_window.save_material()

func delete_selected() -> void:
	var item : TreeItem = tree.get_selected()
	var meta = item.get_metadata(0) if item else null
	if not meta is Dictionary or item == tree.get_root():
		return
	if meta.has("folder"):
		if not DirAccess.get_files_at(meta.folder).is_empty() or not DirAccess.get_directories_at(meta.folder).is_empty():
			await mm_globals.main_window.accept_dialog("Only an empty folder can be deleted.")
			return
		DirAccess.remove_absolute(meta.folder)
		refresh()
		return
	var path : String = meta.material
	var material_name : String = path.get_file().get_basename()
	mm_globals.set_tip_text("Looking for where %s is used..." % material_name)
	await get_tree().process_frame
	var used : Dictionary = IHProject.usages(material_name)
	mm_globals.set_tip_text("")
	var text := "Delete %s and everything it bakes?" % material_name
	if used.is_empty():
		text += "\n\nIt is used nowhere in the project."
	else:
		text += "\n\nIt is still used — these will lose it:"
		var shown := 0
		for place in used:
			text += "\n\n" + place
			for what in used[place]:
				shown += 1
				if shown <= MAX_LISTED:
					text += "\n    " + what
		if shown > MAX_LISTED:
			text += "\n\n... and %d more." % (shown - MAX_LISTED)
	var result = await mm_globals.main_window.accept_dialog(text, true, false)
	if result != "ok":
		return
	mm_globals.main_window.close_material(path, false)
	IHProject.delete(path)
	refresh()
