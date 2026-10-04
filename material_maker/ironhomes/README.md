# Iron Homes

This fork of Material Maker works inside a Unity project: the material library of Iron Homes'
layered materials (`docs/layered-materials.md` in that project).

- **Project.** `File > Load project...` takes a Unity project folder (one with `Assets/`). The last
  one opens at start; if it has gone, MM asks for its folder. Stored in `mm_config.ini`,
  section `ironhomes`.
- **Library.** `<project>/Assets/Materials/Layered/library.json` says where it is (`Library`). A
  material is `<name>.ptex` anywhere in its folders, with what a bake writes beside it. Names are
  lower case, unique across the library, never renamed (Houdini nodes and Unity's `base__coat`
  materials refer to them), and never hold `__` or `none`.
- **Materials panel** (`materials_panel.tscn`). The library as folders and materials, with the
  thumbnail each `.ptex` keeps. A click opens a material, or its tab if open. New, Folder,
  Clone, Delete. Delete lists every use first: Houdini nodes naming the material in any hip of the
  project, and what Unity made from it.
- **Save and bake.** `File > Save material` saves the graph and bakes it; `File > Bake material`
  only bakes. A bake is the material node's `Iron Homes` export target (`material.mmg`):
  `<name>_albedo.png` (output 0), `<name>_mask.png` (11: R metal, G occlusion, A smoothness),
  `<name>_normal.png` (7, OpenGL) and `<name>.json`, which takes the albedo colour, the normal
  strength and the new `Tile size (m)` parameter. From the command line:
  `--export-material --target "Iron Homes" -o <dir> <file>.ptex`.
- **Gone from File:** New, Load, Load recent, Load from website, paint projects, Save as, Save all,
  Export. Unsaved changes are always asked about on closing a tab and on quitting.
- **Previews.** The 3D preview starts on the plane; thumbnails are a tilted square plane, 128 px.
  Rescue copies of saved files live in `user://recovery`, not beside them in the library.

Everything Iron Homes adds outside this folder is marked `Iron Homes` in a comment, to keep merges
from upstream simple.
