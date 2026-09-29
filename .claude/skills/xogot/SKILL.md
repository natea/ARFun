---
name: xogot
description: Drive the Xogot editor (a native Godot) from the command line via the bundled `xo` tool. Use it to inspect or modify a running Xogot instance — read scenes, walk and edit the node tree, get and set properties, manage groups, attach and detach scripts, read/edit/transfer project files, save and switch scenes, capture viewport and in-game screenshots, manage editor selection, run and stop the project, edit project settings, evaluate GDScript, and launch or activate Xogot instances. Use it also to drive the game while it runs — inspect its live node tree and on-screen controls, send keyboard, mouse, joypad and input-action events, evaluate GDScript inside it, and read performance monitors — and to run the project's `test_*.gd` test suites, batch several commands into one undoable operation that rolls back on failure, edit the InputMap, author GridMap cells and AnimationPlayer animations, look up any class's properties, methods, signals and documentation, read the editor Output log, and build UI, themes, materials, particles, cameras, audio, CSG and resources with single commands.
x-xogot-version: 1.6.1
---

# Xogot CLI control

Xogot is a Godot editor; the `xo` command drives a running Xogot instance from the shell, which can be invoked with /Applications/Xogot.app/Contents/MacOS/xo as it might not be on the path. Use it whenever the user asks you to inspect, modify, or run a Godot project that's open in Xogot. Always prefer it over AppleScript, `osascript`, or other indirect approaches.   



## Global flags

Every command accepts:

- `--output json|table|markdown` — output format (default: `json`)
- `--pretty` — pretty-print JSON
- `--app <name>` — target a specific Xogot instance

Default output is JSON. Prefer JSON when parsing.

When an option value starts with a minus sign, join the value to the option with `=`. For example, use `--position=-1,2,3` or `--value=-1`. Some options accept a separate negative value, but `node transform3d --position -1,2,3` fails to parse.

If multiple Xogot instances are running, find their names first:

```sh
xo list
```

Then pass `--app <name>` to subsequent commands.

## Inspecting the editor

Show what's open (Godot version, project, current scene, play/capture status):

```sh
xo editor state
```

Read the editor's Output panel — print() output, warnings and errors. This needs no debug
session; `xo debug console` reads the same log:

```sh
xo editor output --limit 50
```

Show the current editor mode (one of `3d`, `2d`, `gameplay`, `code`, or a plugin name):

```sh
xo editor mode get
```

Show what's selected:

```sh
xo editor selection get
```

Undo or redo editor actions:

```sh
xo editor undo
xo editor undo --count 3
xo editor redo
```

Show the path of the active scene:

```sh
xo scene current
```

Walk the active scene's node tree (paginate with `--depth`, `--offset`, `--limit` for large scenes):

```sh
xo scene tree
```

### Screenshots

`editor screenshot` is the highest-leverage inspection command:

```sh
xo editor screenshot ./shot.png
xo editor screenshot --source game ./game.png
xo editor screenshot --source viewport --view-target "Player,Enemy" --coverage ./shots.png
xo editor screenshot --max-resolution 0 ./full.png
```

Useful flags:

- `--source viewport|cinematic|game` — defaults to `viewport`
- `--max-resolution N` — longest-edge cap; `0` keeps native resolution (default `640`)
- `--view-target "Player,Enemy"` — comma-separated `Node3D` paths to frame in the shot (only honored with `--source viewport`)
- `--session dbg-N` / `--timeout S` — with `--source game`: which Godot debug session to capture from (required when several games are attached, e.g. a Simulator deploy plus an embedded run) and how long to wait for its reply. Works for embedded, Simulator, and device games alike; an old export template answers with "does not support remote game screenshots"
- `--coverage` — with `--view-target`, writes multiple shots covering the targets (output path becomes a base; each file gets a per-shot suffix)
- `--elevation`, `--azimuth`, `--fov` — degrees, or `null` to keep the current camera value

## Searching and reading the scene

Find nodes by name, type, or group — combine any of the filters below:

```sh
xo node find --type Camera3D
xo node find --iname player --group enemies --limit 5
xo node find --regexi '^enemy_\d+$'
```

Filters: `--name` / `--iname` (substring), `--regex` / `--regexi`, `--type` (exact Godot class), `--group`, `--offset`, `--limit`.

List a node's children (add `--recurse` for the whole subtree):

```sh
xo node children /Main
xo node children /Main --recurse
```

List the properties available on a node (omit the path for the scene root):

```sh
xo node property list /Main/Camera3D
```

Get one or more property values (omit the comma-separated names for all properties):

```sh
xo node property get /Main/Camera3D position,fov
```

Get a node's groups:

```sh
xo node group get /Main/Player
```

## Modifying the scene

Replace the editor selection (one node path per argument, or pass `--paths-json`):

```sh
xo editor selection set /Main/Player /Main/Enemy
```

Create a new node by built-in class, or instantiate a packed scene:

```sh
xo node create /Main/Camera3D --type Camera3D
xo node create /Main/Enemy --scene-type res://actors/enemy.tscn
```

Set, rename, move/reparent, duplicate, and delete nodes:

```sh
xo node property set /Main/Camera3D position 'Vector3(0, 1, 5)'   # structured values are NOT quoted; only strings are
xo node property set /Main/Player health 100
xo node property set /Main/Player nickname --nil
xo node rename /Main/Camera3D MainCamera
xo node move /Main/Player /Main/Players --index 0
xo node duplicate /Main/Enemy /Main/Enemy2
xo node delete /Main/Placeholder
```

Set transforms with the convenience commands (accepts `x,y[,z]` shorthand or a Godot Variant string; pick one rotation form):

```sh
xo node transform2d /Main/Sprite --position 100,50 --rotation 45 --scale 2,2
xo node transform3d /Main/Camera3D --position 0,1,5 --rotation-quaternion 0,0,0,1
```

Mutate array-typed properties (e.g. `Path3D.curve.points`, exported `Array` fields) with `xo node array append` / `xo node array remove` — see `--help` for index/value semantics.

Manage groups:

```sh
xo node group add /Main/Enemy hostile
xo node group remove /Main/Enemy hostile
xo node group set /Main/Enemy hostile,boss   # comma-separated; omit groups to clear all
```

Create, attach, or detach a script:

```sh
xo script create res://player/player.gd
xo script create res://player/player.gd --string 'extends Node3D'
xo script create res://player/player.gd --source /tmp/player.gd
xo script attach /Main/Player res://player/player.gd
xo script detach /Main/Player
```

## Reading and editing project files

Works on any text file in the project (scripts, `.tscn`, `.tres`, `project.godot`). Always go through these rather than touching the local path directly. Use `xo path resolve res://…` only when you need to hand a real filesystem path to another tool.

Read a file (paginate large files with `--offset` and `--limit` lines):

```sh
xo file read res://player/player.gd
xo file read res://main.tscn --offset 100 --limit 50
```

Edit a file with one or more targeted substring replacements. Each `--oldText` must be unique in the original file; pass repeated `--oldText`/`--newText` pairs to apply several edits in one call. Each edit is matched against the **original** file, so don't include overlapping or nested edits — split them into separate calls.

```sh
xo file edit res://player/player.gd \
  --oldText 'var speed = 5.0' --newText 'var speed = 7.5' \
  --oldText 'func jump():' --newText 'func jump(force: float = 1.0):'
```

Save an open editor file before reading or editing it from the CLI (flushes the editor's pending changes to disk):

```sh
xo file save res://player/player.gd
```

## Finding files, rescanning, reimporting, checking scripts

```sh
xo file search --name 'player*' --ext gd tscn     # glob on the file name, extension filter
xo file search --type Texture2D --path assets/    # resource type (subclasses match) + path substring
xo file scan --wait                               # rescan after adding files outside the editor; reports script classes added/removed
xo file reimport res://assets/hero.png            # requested | not_importable | missing (reimport is fire-and-forget)
xo script check res://player.gd                   # GDScript diagnostics (line, column, message, severity)
xo script outline res://player.gd                 # class_name, base, functions, signals, @export vars, constants
```

`script create` and `script patch` validate GDScript after writing and return `check` (`full`/`partial`/`none`) and `diagnostics` in the same reply, so fix errors before moving on.

## Transferring binary files

For binary assets (images, sounds, models, fonts), or when the project lives somewhere `path resolve` can't open:

```sh
xo file send /tmp/hero.png res://art/hero.png            # local → project
xo file get  res://saves/level_1.tres /tmp/level_1.tres  # project → local
```

For `send` the local path is first; for `get` it's second. Don't flip them.

## Working with scenes

```sh
xo scene list                                       # open scenes
xo scene list --all                                 # every scene in the project
xo scene activate res://main.tscn                   # open (creates tab if needed)
xo scene save                                       # save current
xo scene save-as --path res://main_v2.tscn          # save current under new path
xo scene create --path res://levels/level_2.tscn --root-type Node2D --root-name Level
xo scene new --unsaved --root-type Node2D           # untitled scene, nothing on disk
```

`scene create` (aliased `scene new`) writes the file immediately. Pass `--unsaved` to get the
editor's untitled scene instead: a new tab with unsaved changes and no file until a later
`scene save`. `--path` is optional with `--unsaved`, and is remembered for that save.

Check whether work is unsaved, and what undo would do next:

```sh
xo scene state                                      # current scene: unsaved, undo/redo depth
xo scene state --all                                # every open tab, plus the undo history
```

`xo scene delete` and `xo scene rename` round out file-level scene management — consult `--help` for flags.

## Running the project

```sh
xo project destination list
xo project run                                                # main scene, active destination
xo project run --scene res://test_room.tscn --destination <id>
xo project stop
```

## Project settings

Get or set Godot project settings (keys look like `application/run/main_scene`):

```sh
xo project setting get application/run/main_scene
xo project setting set application/run/main_scene '"res://main.tscn"'
```

`<value>` is parsed by `GD.strToVar`; quote strings as `'"text"'`. Do NOT quote structured values — `'"Vector3(0,1,5)"'` parses as a String, and assigning it to a Vector3 property is refused.

Autoload singletons and shader globals have dedicated subcommands — see `xo project autoload --help` and `xo project shader-global --help`.

## Input map

`xo inputmap` manages the project's InputMap actions (Project Settings > Input Map); every edit is undoable and saved with the project settings.

```sh
xo inputmap list                                   # user actions, deadzone, bindings with indexes
xo inputmap add jump --deadzone 0.2 --ensure       # --ensure: no error when it already exists
xo inputmap bind jump --key Space                  # physical key by default; --keycode / --label alternatives
xo inputmap bind jump --joy-button 0 ; xo inputmap bind move_right --joy-axis 0 --value 1
xo inputmap bind fire --mouse left --mods shift --ensure
xo inputmap unbind jump --key Space ; xo inputmap unbind jump --index 0 ; xo inputmap unbind jump --all
xo inputmap deadzone jump 0.3 ; xo inputmap rename jump leap ; xo inputmap remove leap
```

## Class reference

```sh
xo project types --basenode Control                 # every type below a base
xo project class CharacterBody2D                    # own properties (with defaults), methods, signals, enums, constants, inheritors
xo project class CharacterBody2D --inherited --docs # plus inherited members (tagged declared_in) and documentation
xo project class Player                             # a script class_name works too
```

## Resources

`xo resource` handles standalone `.tres` files and resource-typed properties: `info`, `search`, `load`, `set` (assign a resource to a node property), and `create`/`update`/`delete` for saved files. Consult `xo resource --help` for the exact shape.

## Debugging

`xo debug` drives debug sessions: `run`/`stop`/`status`, `pause`/`resume`/`step`/`step-into`, `breakpoint`, `stack` and `frame`, `eval` in the paused frame, plus `console` and `errors`. Use `xo debug --help` (and `<subcommand> --help`) to discover flags before driving a session.

## Driving the running game

`xo game` talks to the game that `project run` / `debug run` launched, through the editor's debug session (so it works for embedded, windowed, and remote runs; pass `--session` when several are attached, `--timeout` for slow games). `xo game console` is the exception: it is answered by the game play instance itself.

```sh
xo game status                                   # stopped | launching | live | missing | at-break
xo game tree --root /root/Main --depth 3          # live node tree (path, class, script, child_count)
xo game node /root/Main/Player --props            # one node with its current property values
xo game ui list                                   # Controls: text, visible, disabled, rect, center
xo game input key Space                           # tap; --press / --release to hold; --mods ctrl,shift
xo game input mouse button left --at 320,240      # click at window coords (use `ui list` center)
xo game input mouse move --to 100,80              # or --by=-5,10 for a delta
xo game input action jump --press                 # InputMap action; --release later, or default tap
xo game input joy button 0 ; xo game input joy axis 0 --value=-1
xo game input sequence --json '[{"frame":0,"action":"jump","tap":true},{"frame":5,"key":"Right","press":true},{"frame":30,"key":"Right","press":false}]' --wait-frames 10
xo game actions                                   # currently pressed actions (--all for every action)
xo game eval 'tree.current_scene.name'            # `tree` (SceneTree) and `root` (Window) are predefined; get_tree()/get_node() are NOT available
xo game eval 'root.get_node("Main/Player").position'   # reach nodes through `root`, without the leading /root/
xo game eval --file /tmp/probe.gd --timeout 5     # coroutines with `await` return when they finish
xo game perf --monitor time_fps memory_static     # Performance monitors; --editor reads the editor process
```

Node paths in the game are absolute from `/root` (the `tree` output shows them). `game eval` output includes the game's `print`s and any errors raised while it ran; a parse error is reported as an error with the compiler message. Frame-timed commands (`tap`, `click`, `sequence`, awaiting `eval`) cannot progress while the game is stopped at a breakpoint — resume it first. `editor state` reports `game_automation` (`stopped`/`launching`/`live`) without a round trip.

## Running project tests

`xo test` runs GDScript test suites inside the editor (nothing needs to be running). A suite is any `test_*.gd` under the project (or `--root res://tests`); every `test_*` method with no required arguments is a test, with optional `before_all`/`after_all`/`before_each`/`after_each` hooks. A test **fails** when it returns `false` or a String message, **errors** when an error is logged while it runs (script errors, failed `assert()`), and **times out** when an awaited coroutine does not finish within `--per-test-timeout`.

```sh
xo test list                                       # suites and their test names
xo test run                                        # everything; exit code 40 unless all passed
xo test run --suite test_player --test 'test_jump*' --exclude test_slow --full
xo test run --timeout 60                           # stops early with partial=true (checked between tests; a non-awaiting infinite loop cannot be interrupted)
xo test last                                       # the previous run's full report
```

Suites are compiled as `@tool` scripts for the run (the editor cannot instantiate plain scripts), and suites that extend `Node` are added to the editor tree, so `get_tree()` and `await get_tree().process_frame` work.

## UI, theme, material, particles, camera, audio, CSG workflows

Higher-level commands that compose the node and resource primitives; every scene edit is undoable, values are Godot Variant expressions (`Vector2(1, 2)`, `Color(1, 0, 0, 1)`, `"text"`), colors also accept `#rrggbb[aa]`.

```sh
xo ui build --parent /Main --spec '{"type":"VBoxContainer","name":"Menu","anchor":"center","children":[{"type":"Button","name":"Play","text":"Play"},{"type":"Label","text":"v1.0"}]}'
xo ui anchor /Menu full_rect --mode keep_size --margin 16 ; xo ui text /Menu/Play "Start"
xo ui draw /Hud --recipe '[{"circle":[40,40,30],"color":"#ff5500"},{"string":{"text":"HP","at":[10,90]},"color":"#fff"}]'

xo theme create res://ui/main.tres
xo theme set res://ui/main.tres --class Button --color font_color=#ffffff --constant h_separation=8 --font-size font_size=18
xo theme stylebox res://ui/main.tres --class Button --item normal --bg '#223344' --border 2 --border-color '#88aaff' --radius 6 --margins 8 4 8 4
xo theme apply /Menu res://ui/main.tres

xo material create standard res://materials/hero.tres --preset metal --set albedo_color='Color(0.8,0.2,0.2,1)'
xo material create shader res://materials/water.tres --shader res://shaders/water.gdshader --uniform speed=2.0
xo material assign /Hero res://materials/hero.tres --slot override      # surface:N | canvas | particles
xo material info res://materials/hero.tres ; xo material list

xo particles create --parent /Main --name Fire --dim 2d --preset fire       # fire | smoke | spark | magic | rain | explosion | lightning; --cpu for CPUParticles
xo particles configure /Fire --node amount=64 --process gravity='Vector3(0,-80,0)' color='Color(1,0.3,0,1)'
xo particles draw-pass /Sparks3D 1 res://meshes/spark.tres ; xo particles restart /Fire ; xo particles info /Fire

xo camera create 2d --parent /Player --preset platformer --current    # top-down | platformer | cinematic | action
xo camera set /Camera2D --limits 0,0,4096,2048 --smoothing 6 --drag-h 0.2 0.2
xo camera follow /Camera2D /Player ; xo camera current /Camera2D ; xo camera list

xo audio create 2d --parent /Player --name Footsteps --stream res://sfx/step.wav --volume=-6 --bus SFX
xo audio preview play res://sfx/step.wav ; xo audio preview stop ; xo audio list

xo csg create box --parent /Level --name Wall --size 'Vector3(4,2,0.5)' --op union ; xo csg op /Level/Hole subtraction

xo resource inline /Body/CollisionShape2D shape --type CircleShape2D --set radius=24   # create + configure a built-in resource
xo node fit-shape /Body/CollisionShape2D                                    # size a collision shape to sibling visuals
xo resource curve res://curves/ease.tres --points '[[0,0,0,2],[1,1,0,0]]'      # Curve; Curve2D/Curve3D by point arity or --type
xo resource environment res://env/night.tres --preset night                      # outdoor | indoor | studio | night, --sky
xo resource gradient-texture res://tex/sky.tres --stops '[{"offset":0,"color":"#0b1a3a"},{"offset":1,"color":"#7fb2ff"}]' --fill linear
xo resource noise-texture res://tex/noise.tres --noise-type simplex_smooth --frequency 0.02 --octaves 4 --seamless
xo resource search --base Texture2D                                              # subclasses match
xo tileset source export-image --resource res://tiles.tres 0 /tmp/atlas.png --max-size 512
```

## GridMap

```sh
xo gridmap library /Level/GridMap                          # MeshLibrary items: id, name, mesh, shapes, navmesh
xo gridmap cell set /Level/GridMap --at 0,0,0 --item floor --orientation 0   # item by id or name
xo gridmap fill /Level/GridMap --from 0,0,0 --to 9,0,9 --item floor
xo gridmap fill /Level/GridMap --from 4,1,4 --to 5,1,5    # no --item: erase the region
xo gridmap cell get /Level/GridMap --at 3,0,3 ; xo gridmap cell erase /Level/GridMap --at 3,0,3
xo gridmap used /Level/GridMap --item wall                # used cells (optionally per item)
xo gridmap orient /Level/GridMap --at 2,0,2 --orientation 10   # or --basis 'Basis(...)', --to X,Y,Z for a region
xo gridmap clear /Level/GridMap
```

## 3D Modeler

`xo modeler` inspects and edits meshes with the 3D Modeler. Use these commands:

- `modeler info [node]` shows the current Modeler state.
- `modeler mesh [node] [--limit N]` shows vertices, records, edges, and faces.
- `modeler shapes` lists shape kinds, parameters, defaults, and ranges.
- `modeler actions [node]` lists action names and explains unavailable actions.
- `modeler create <kind> ...` creates one of the 12 parametric shapes.
- `modeler poly create|edit ...` creates or edits a Poly Shape, including holes.
- `modeler bezier create|edit ...` creates or edits an experimental Bezier Shape.
- `modeler recipe set <node> ...` changes a saved shape recipe and rebuilds it.
- `modeler make-editable <node> [--preview] ...` converts a mesh or CSG node.
- `modeler strip <node>` removes editable mesh data.
- `modeler mode <node> <mode>` sets object, vertex, edge, or face mode.
- `modeler select <node> ...` selects elements by index, path, attribute, or ray.
- `modeler transform <node> ...` moves, rotates, scales, extrudes, or insets elements.
- `modeler cut <node> ...` cuts a closed contour into one face.
- `modeler action <node> <action> ...` runs an action from `modeler actions`.
- `modeler paint material|color|smoothing|position ...` changes mesh attributes.
- `modeler slot list|set|match|select|clear ...` manages mesh material slots.
- `modeler smoothing list|select|merge|clear ...` manages smoothing groups.
- `modeler palette show|load|save|reset|set-material|set-color ...` manages the Paint palette.
- `modeler uv ...` selects, groups, projects, transforms, unwraps, and exports UV data.
- `modeler export <node>... --path res://... ...` exports mesh files in the project.
- `modeler boolean <a> <b> --operation ...` runs an experimental Boolean operation.
- `modeler preferences get|set|reset ...` reads or saves Modeler preferences.

Face indices are zero-based. `--vertices` uses shared vertex indices. A mesh can have several
face-owned vertex records at one shared position, so use `--records` only when a command needs
raw record indices. Edges use two shared vertex indices in `a-b` form. Run `xo modeler mesh
<node>` before an indexed edit to read the current face, edge, shared vertex, and record numbers.
Topology changes can change these numbers.

A node-targeted command selects that node in the editor, as if you clicked it. The CLI does not
open confirmation sheets or live action-adjustment previews. Actions commit directly.
`make-editable --preview` is read-only and reports import counts.

Export paths must start with `res://` and stay inside the project. Export refuses to replace an
existing file unless you pass `--force`.

Boolean and Bezier commands are experimental and may give rough results. They run without
enabling the experimental preference.

Action options such as `--bevel-distance` apply to one command. They are never saved. Only
`modeler preferences set` saves a preference. `modeler create` starts from shape defaults and
ignores saved shape settings unless you pass `--use-saved-settings`.

An inline selection and its operation are two undo steps. For example, an action with `--faces`
first changes the selection and then changes the mesh. Use `xo editor undo [--count N]` and
`xo editor redo` to move through these steps.

This example builds and edits a small courtyard. Read indices again after each topology change:

```sh
xo scene create --path res://courtyard.tscn --root-type Node3D --root-name Courtyard

xo modeler create plane --name Floor --size 20,0,20 --param widthCuts=2 --param heightCuts=2
xo modeler create cube --name WallNorth --size 20,3,0.5 --position 0,1.5,-10
xo modeler create cube --name WallSouth --size 20,3,0.5 --position 0,1.5,10
xo modeler create cube --name Platform --size 4,1,4 --position 0,0.5,0
xo modeler create cylinder --name PillarA --size 0.6,4,0.6 --position 0,2,0 --param sides=12
xo modeler create cylinder --name PillarB --size 0.6,4,0.6 --position 3,2,3 --param sides=12

xo modeler poly create --name Border --outline '0,0;10,0;10,10;0,10' --hole '4,4;4,6;6,6;6,4' --height 0.25 --position=-5,0,-5

xo modeler create door --name Gate --position 0,1.5,-9.5
xo modeler recipe set /Gate --param pedimentHeight=0.7 --param sideWidth=0.6
xo modeler create arch --name Arch --position 0,3,-9.5
xo modeler recipe set /Arch --param degrees=180 --param sides=12
xo modeler create stairs --name Stairs --position 0,0,4
xo modeler recipe set /Stairs --param steps=8 --param circumference=0
xo modeler create cylinder --name Fountain --position=-3,1,0
xo modeler recipe set /Fountain --kind pipe --param thickness=0.15 --param sides=16

xo modeler mesh /WallNorth --limit 100
xo modeler transform /WallNorth --mode face --faces 0 --translate 0,1.5,0 --extrude
xo modeler transform /WallNorth --scale 0.6,0.6,1 --extrude
xo modeler action /WallNorth extrudeFaces --extrude-distance=-0.3
xo modeler mesh /WallSouth --limit 100
xo modeler action /WallSouth bevelEdges --mode edge --edges 0-1 --bevel-distance 0.1
xo modeler cut /Platform --face 0 --face-2d='-0.2,-0.2;0.2,-0.2;0.2,0.2;-0.2,0.2'
xo modeler action /Platform deleteFaces

xo modeler action /PillarB mirrorObjects --mode object --mirror-x --mirror-duplicate
xo modeler action /PillarB mergeObjects --with /PillarBMirror
xo modeler action /PillarB centerPivot

xo modeler paint material /Floor --material builtin:checker --mode face --all
xo modeler paint color /Gate --color 0.65,0.4,0.2,1 --mode face --all
xo modeler paint smoothing /WallSouth --faceted --mode face --all
xo modeler palette save --path res://courtyard_palette.tres

xo modeler uv auto-settings /Floor --mode face --all --scale 0.25,0.25 --world-space
xo modeler uv group /Floor --mode face --all
xo modeler uv project /Floor --projection planar --mode face --all
xo modeler uv fit /Floor --mode face --all
xo modeler uv stitch /Floor --source 0 --target 1
xo modeler uv unwrap /Floor --hard-angle 88 --pack-margin 4 --angle-error 8 --area-error 15
xo modeler uv rebuild-uv2 /Floor
xo modeler uv template /Floor ./courtyard_uv.png --size 1024

xo modeler action /Floor setCollider --mode object
xo modeler action /Border setTrigger --mode object
xo node create /ImportedSphere --type MeshInstance3D
xo resource inline /ImportedSphere mesh --type SphereMesh --set radial_segments=12
xo modeler make-editable /ImportedSphere --preview
xo modeler make-editable /ImportedSphere

xo modeler boolean /Fountain /PillarA --operation subtraction --name FountainCut
xo modeler export /FountainCut --path res://exports/fountain.glb --format gltf --force
xo modeler strip /ImportedSphere
xo scene save
```

## Animations

`xo animation` authors AnimationPlayer animations; every edit is undoable. Node paths may be absolute scene paths (`/Sprite`) — they are stored relative to the player's root node.

```sh
xo animation player create /Main                         # AnimationPlayer node
xo animation create /AnimationPlayer walk --length 1 --loop-mode pingpong --overwrite
xo animation list /AnimationPlayer ; xo animation get /AnimationPlayer walk --keys
xo animation track add-property /AnimationPlayer walk /Sprite position --keys '[{"t":0,"v":"Vector2(0,0)"},{"t":1,"v":"Vector2(100,0)"}]' --interpolation cubic
xo animation track add-method /AnimationPlayer walk /Main --calls '[{"t":0.5,"method":"play_step"}]'
xo animation tween /AnimationPlayer appear --spec '[{"path":"/Sprite:modulate","from":"Color(1,1,1,0)","to":"Color(1,1,1,1)","duration":0.4}]'
xo animation preset /AnimationPlayer hit shake --target /Sprite --duration 0.3   # fade-in | fade-out | slide | shake | pulse
xo animation validate /AnimationPlayer               # tracks whose node/property don't resolve
xo animation autoplay /AnimationPlayer walk ; xo animation autoplay /AnimationPlayer --clear
xo animation preview play /AnimationPlayer walk ; xo animation preview stop /AnimationPlayer
xo animation delete /AnimationPlayer walk
```

## Batching commands with rollback

`xo batch` runs several commands as one operation. Steps are ordinary xo argv arrays; they are validated first (a later step may refer to a node an earlier step creates), executed in order, and on the first failure the remaining steps are skipped and the editor undo history is rewound to the batch start. Use it when a scene edit only makes sense as a whole — build a node tree, configure it, attach resources.

```sh
xo batch --json '{"steps":[
  ["node","create","/Hero","--type","CharacterBody2D"],
  ["node","create","/Hero/Sprite","--type","Sprite2D"],
  ["node","property","set","/Hero/Sprite","texture","..."],
  ["script","attach","/Hero","res://hero.gd"]
]}'
xo batch --file plan.json --dry-run          # validate only
xo batch --file plan.json --strict           # refuse steps that could not be rolled back
```

Steps that write files, change project settings, or edit animations are executed but reported as `not_rolled_back` (`rollback_scope: partial`); `--strict` rejects them up front. Not batchable: run/stop, debug, screenshots, export, eval, `game *`, `test *`, and `node group add/remove` (use `node group set`). Exit codes: 30 rejected/invalid, 31 a step failed, 32 rollback incomplete.

## Editor mode switching

Switch the editor between built-in modes (`3d`, `2d`, `gameplay`, `code`) or a plugin:

```sh
xo editor mode set 3d
xo editor mode set "<custom plugin name>"
```

## Evaluating GDScript

Run GDScript directly in the editor as an `@tool extends EditorScript` — an escape hatch for things no structured command can express (custom inspections, bulk edits across many nodes, `EditorInterface` calls). **Prefer the structured commands above when they cover the task.**

```sh
xo eval 'Engine.get_version_info()'
xo eval 'EditorInterface.get_edited_scene_root().get_child_count()'
xo eval --file /tmp/dump_tree.gd
```

The positional inline form accepts exactly one expression. To evaluate multiple expressions, execute statements, or define and run functions, use the `--file` form; passing them inline will produce a parse error.

The reply contains `result`/`result_type` from the `_run()` return value and `output` from captured `print`s. File contents may be a bare block (auto-wrapped in `func _run():`), a block that defines its own `func _run():` (auto-wrapped with `@tool` / `extends EditorScript` headers), or a complete script starting with `@tool` or `extends …`. Pass either an inline expression argument or `--file`, never both.

## Logs, screenshots, reload, quit

```sh
xo editor output --limit 50 --details                 # Output panel with error stack frames; every entry has an index
xo editor output --since <cursor>                     # only entries newer than a previous reply's opaque `cursor`
xo editor output --source automation                  # what xo itself did (requests and replies); --source all merges both
xo editor output --previous-run                       # the Output panel from before the current game run
xo editor output --follow                             # stream new entries until Ctrl-C
xo editor clear --errors ; xo editor clear --automation
xo editor state                                       # includes new_errors_since_last_request and game_automation
xo editor screenshot --source viewport2d /tmp/2d.png  # the 2D editor viewport
xo editor screenshot --source game --allow-stale /tmp/game.png   # last frame (stale: true) when the game is frozen
xo editor screenshot --source game --session dbg-1 /tmp/sim.png  # a game deployed to a Simulator or device; --session picks it when several are attached
xo project run --no-save                              # smoke-test the on-disk project without saving in-memory edits
xo scene reload --force                               # discard the in-memory scene and reload it from disk
xo editor quit --save                                 # graceful quit (--discard to drop unsaved work)
```

`script create` / `script patch` return diagnostics for the file they wrote, so a broken script is visible in the same reply; `editor state`'s `new_errors_since_last_request` tells you whether anything else went wrong since your previous command.

## Lifecycle: launching and targeting instances

```sh
xo launch --new-project                                  # open project picker in a new instance
xo launch --new-project=/path/to/new --renderer mobile   # forward+, mobile, or compatibility
xo launch --editor /path/to/project                      # open editor on an existing project
xo launch --path /path/to/project                        # run a project without opening the editor
xo launch --download-git                                 # open the download-from-Git flow
xo activate "<instance-name>"                            # bring an instance to the front
xo ping "<instance-name>"                                # check liveness
```

## Critical conventions

- **Node paths are absolute from the edited scene's root, and that root is `/` itself.** Its children are `/Child`, never `/SceneRootName/Child` — including the root node's own name does not resolve. Don't use Godot's relative `..` form. Paths in the *running* game are different: `game` commands use the live tree's `/root/...` paths, which the `game tree` output shows.
- **Godot paths** use `res://…` (project) and `user://…` (writable user dir). Convert with `xo path resolve` only when handing a path to another tool.
- **Property values** for `node property set` and `project setting set` are run through `GD.strToVar`. Quote strings as `'"hello"'`, but pass structured values unquoted: `'Vector3(0,1,5)'`, `'Color(1,0,0,1)'`. Numbers can be bare: `100`. Use `--nil` (on `node property set`) to clear.
- **Negative option values:** Use the `--option=value` form for consistent parsing. For example, use `--position=-1,2,3`.
- **Read before you edit.** Run `file read` (and `file save` first if the editor may have unsaved changes) before constructing a `file edit`, so your `--oldText` matches the bytes on disk.
- Default output is JSON; pass `--pretty` for human reading.

## Discover the surface

`xo` is authoritative — when in doubt, ask it directly:

```sh
xo --help
xo <command> [<subcommand>] --help
```

## What you should NOT do

- Don't fabricate node paths from memory. Discover them with `xo scene tree` or `xo node find` first, then operate on the exact paths returned.
- Don't assume your working directory matches the Godot project. Use `res://` paths for project files; reach for `xo path resolve` only when you need a real filesystem path.
- Don't modify files under Godot control directly even if you find the path — always go through `xo`.
