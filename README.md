# Statico's Godot Roguelike Example

This is an incomplete, copyable roguelike game made with Godot 4. It was originall going to be a sci-fi roguelike, but I decided to open-soruce it as a learning example. You can use it as a base for your own roguelike game. Play it [here](https://roguelike.statico.io), or play my original sci-fi themed roguelike [here](https://vesta.statico.io).

All code and assets are licensed permissively. The code is MIT licensed, the font is CC0, and the tileset is [Dawnlike from DawnBringer](https://opengameart.org/content/16x16-dawnhack-roguelike-tileset) and has its own license.

Questions? Ping me as `@statico` on the [Roguelikes Discord server](https://discord.gg/QATuUBAuQS).

[![](https://github.com/user-attachments/assets/c326179c-dd2f-4e97-bc69-a18296267a67)](https://roguelike.statico.io/)

**Tips:** Click to move or attack. Right-click to use ranged weapon. WASD and QEZC work as movement. Use the inventory button or <kbd>i</kbd> key to pick up and manage items. Yes, there's a delay when you click the "Play" button while assets load.

## Features

- ✅ Turn-based roguelike mechanics (movement, vision, combat)
- ✅ Inventory and equipment system with modular components
- ✅ BSP-based dungeon generation with procedural content
- ✅ Monster AI with behavior trees and factions
- ✅ Combat system with D20-based mechanics, damage types, and status effects
- ✅ Nutrition system affecting healing and survival
- ✅ Field of view with fog of war
- ✅ Throwable items with area-of-effect damage
- ✅ Data-driven item and monster definitions
- ✅ Dungeon generator preview tool inside Godot
- ✅ Sprite toolchain for [Dawnlike](https://opengameart.org/content/16x16-dawnhack-roguelike-tileset) tiles that can be adapted to other tilesets

### Missing Features

- 🚫 Scrolls, wands, rings, and amulets
- 🚫 Shops and economy
- 🚫 Quests and objectives
- 🚫 Save/load system

## Development Setup

You can clone this repo and run it in Godot immediately. However, I recommend VS Code or the Cursor IDE alongside Godot in order to have the best editing experience.

### Suggested Setup

1. Install [gdtoolkit](https://github.com/Scony/gdtoolkit) - I recommend using [uv](https://docs.astral.sh/uv/):
   1. `uv venv`
   1. `source .venv/bin/activate`
   1. `uv pip install gdtoolkit`
   1. `gdlint --version` and check that it's 4.3.3 or later
1. Install [VS Code](https://code.visualstudio.com/) or [Cursor](https://www.cursor.com/)
1. Run `code` or `cursor` from the command line with the `uv` virtual environment activated so that `gdlint` and `gdformat` are accessible in the path. (I don't know a better way to do this.)
1. Install the [Godot Tools](https://marketplace.visualstudio.com/items?itemName=geequlim.godot-tools) extension
1. Install the [GDScript Formatter and Linter](https://marketplace.cursorapi.com/items?itemName=EddieDover.gdscript-formatter-linter) extension
1. Open the project in Godot -- this starts the language server so that the formatter and linter can be used
1. Open the project in VS Code / Cursor
1. Run `Tasks: Run Task` and select `Run Godot Project`
   - I like to bind "Rerun Last Task" to `Cmd-R` for a fast way to run the project from VS Code / Cursor

### Editing Data

Monster and item data is stored in CSV files in the `assets/data/` directory. I recommmend [LibreOffice](https://www.libreoffice.org/) to edit the CSV files.

CSV data files need their import settings set to "Keep" in the project settings in order to not generate translation files. [Read more here.](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_translations.html#doc-importing-translations)

### Art Pipeline

The art pipeline is designed to quickly ingest an existing tileset and give them simple names, like `wall-5-nw` and `reptile-10` that can be referenced in the code as [StringNames](https://docs.godotengine.org/en/stable/classes/class_stringname.html#class-stringname). The tools and pipeline are in the `art/` directory.

The full Dawnlike tileset isn't included in the project because that would be full redistribution, and I want to make sure nobody uses the entire tileset without understanding the author's license. If you want to use all of the Dawnlike tiles, you can:

1. Read [the Dawnlike tileset license](https://opengameart.org/content/16x16-dawnhack-roguelike-tileset)
1. Unzip the tileset into `art/Dawnlike`
1. `cd art/`
1. Read through the `gen_*.py` scripts
   1. Set all the things like `SET_THIS_TO_FALSE_TO_GET_ALL_ITEMS` to `False`
   1. Remove the watermark if you want
1. Run `uv pip install -r requirements.txt`
1. Run all the `gen_*.py` scripts
1. Open the `gen_*_tileset.gd` scripts _from within Godot_ (you may have to disable the External Editor checkbox in the project settings) and run them (Cmd-Shift-X on Mac). You may need to reload the project.

You can also adapt these tools to read other tilesets, like Oryx tiles. They're easily editable with Cursor or Claude Code.

### Map Generator Preview

You can use the map generator preview tool to test map generation parameters. Open `scenes/debug/map_generator_tool.tscn`, click MapGeneratorTool, and then click the "Regenerate Map" button to see the map generated with the current parameters.

[<img height="500" alt="map generator tool screenshot" src="https://github.com/user-attachments/assets/ccdea42a-4813-444d-807e-10ba1fcbd75d" />](https://roguelike.statico.io/)

### Item & Sprite Explorers

Use these tools to quickly reference tile and item names. Open `scenes/debug/sprite_explorer.tscn` and `scenes/debug/item_explorer.tscn` and click Run Current Scene (usually `Cmd-B` on Mac) to run them.

<img width="400" alt="sprite viewer screenshot" src="https://github.com/user-attachments/assets/332db409-0a65-4a67-9270-b05f0808c6e2" />
<img width="400" alt="item explorer screenshot" src="https://github.com/user-attachments/assets/5bffd8d3-cbb3-4f7d-9265-539ce3cfe7c9" />

## Architecture Overview

**World Management** (`src/world.gd`)

- Central singleton that manages game state, turn progression, and coordinates all systems
- Handles player actions, monster AI turns, and system updates (nutrition, status effects, healing)
- Manages map generation and level transitions

**Turn-Based Engine** (`src/world.gd`, `src/actions/`)

- Actions are the fundamental unit of gameplay - every player input and monster decision becomes an `Action`
- Turn progression: Player acts → All monsters with sufficient energy act → Systems update → Vision updates
- Energy system determines when monsters can act (faster monsters act more frequently)

**Map Generation** (`src/map_generators/`, `src/world_plan.gd`)

- BSP-based dungeon generation with configurable parameters
- Multiple generator types (dungeon, arena) with different layouts
- Procedural room placement, corridor connection, and content population
- World planning system for multi-level dungeon structure

**Combat System** (`src/combat.gd`, `src/damage.gd`)

- D20-based combat with attack rolls, damage calculation, and resistances
- Multiple damage types with monster-specific resistances
- Melee and ranged combat with different mechanics
- Status effects and area-of-effect damage

**Monster AI** (`src/monster_ai.gd`, `src/monster.gd`)

- Behavior tree system for complex AI decision making
- Different behavior types: aggressive, fearful, curious, passive
- Pathfinding integration for movement and combat positioning
- Faction system for monster relationships

**Inventory & Equipment** (`src/equipment.gd`, `src/item.gd`, `scenes/ui/inventory_modal.gd`)

- Modular equipment system with multiple slots (armor, weapons, accessories)
- Hierarchical item system supporting containers and modules
- Drag-and-drop inventory interface
- Equipment affects combat stats and capabilities
- Originally there was a sci-fi style power and module system but it was overly complex for this example

**Vision & Rendering** (`src/map.gd`, `src/map_renderer.gd`)

- Field of view calculation using shadowcasting algorithm
- Fog of war with "seen but not visible" tiles
- Tile-based rendering with sprite management
- Visual effects system for combat and interactions

**Status Effects & Nutrition** (`src/status_effect.gd`, `src/nutrition.gd`)

- Status effect system with duration and magnitude
- Nutrition system affecting healing and survival
- Natural healing based on nutrition level
- Status effects can modify behavior and capabilities

### Data Flow

1. **Input**: Player input → Action creation → World processing
2. **Turn Processing**: Action execution → Monster AI → System updates → Vision update
3. **Rendering**: World state → Map renderer → Visual effects → UI updates
4. **Data**: CSV files → Factory classes → Game objects

### Key Files to Explore

- `src/world.gd` - Core game loop and state management
- `src/monster_ai.gd` - AI behavior trees and decision making
- `src/map_generators/dungeon_generator.gd` - Dungeon generation algorithm
- `src/combat.gd` - Combat resolution and damage calculation
- `src/equipment.gd` - Equipment system and item management
- `scenes/game/game.gd` - Main game scene and input handling
- `assets/data/` - CSV files defining items and monsters

## Licenses

Source code is MIT licensed.

Artwork is from [Dawnlike from DawnBringer](https://opengameart.org/content/16x16-dawnhack-roguelike-tileset) and has its own license.

The font is [Pixel Operator](https://www.dafont.com/pixel-operator.font) and is licensed under [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
