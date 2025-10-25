#!/usr/bin/env python3
"""
Script to process DawnLike world tilesets into individual sprite files.
Each PNG contains 16x16 tiles arranged in a grid.
"""

import os
import sys
import json
import tempfile
import shutil
from pathlib import Path
from PIL import Image
import re
from collections import defaultdict
from PIL import ImageDraw, ImageFont

# Configuration
TILE_SIZE = 16
OBJECTS_DIR = Path("art/DawnLike/Objects")
OUTPUT_DIR = Path("assets/generated")
TRANSPARENCY_THRESHOLD = 0.1  # Skip tiles with less than 10% non-transparent pixels

# Tile extraction limits
SET_THIS_TO_FALSE_TO_GET_ALL_TILES = True  # Set to False to extract all tiles instead of just first 7 blocks

# Atlas configuration
SPRITE_WIDTH = 16
SPRITE_HEIGHT = 16

WATERMARK = "DawnLike tiles by DawnBringer"

def find_project_root():
    """Find the project root directory by looking for project.godot file."""
    current_dir = Path.cwd()

    # Check current directory and parent directories
    for path in [current_dir] + list(current_dir.parents):
        if (path / "project.godot").exists():
            return path

    # If not found, assume current directory is project root
    print("Warning: Could not find project.godot file. Using current directory as project root.")
    return current_dir

def change_to_project_root():
    """Change to the project root directory."""
    project_root = find_project_root()
    os.chdir(project_root)
    print(f"Changed to project root: {project_root}")
    return project_root

def extract_used_tile_names():
    """Extract tile names from map_renderer.gd by finding StringName references like &"tile-name"."""
    map_renderer_path = Path("src/map_renderer.gd")
    used_tile_names = set()

    if not map_renderer_path.exists():
        print(f"Warning: {map_renderer_path} not found. Using all tiles.")
        return None

    # Regex pattern to match StringName references like &"tile-name"
    pattern = r'&"([^"]+)"'

    with open(map_renderer_path, 'r', encoding='utf-8') as f:
        content = f.read()
        matches = re.findall(pattern, content)
        used_tile_names.update(matches)

    print(f"Found {len(used_tile_names)} used tile names in map_renderer.gd:")
    for tile_name in sorted(used_tile_names):
        print(f"  {tile_name}")
    print()

    return used_tile_names

def get_pattern_map_for_tile_type(tile_type):
    """Get the pattern mapping for a given tile type."""
    if tile_type == "wall":
        return {
            # Row 0
            (0, 0): "se", (1, 0): "ew", (2, 0): "sw",
            (3, 0): "lone", (4, 0): "sew",
            # Row 1
            (0, 1): "ns", (1, 1): "n",
            (3, 1): "nse", (4, 1): "nsew", (5, 1): "nsw",
            # Row 2
            (0, 2): "ne", (2, 2): "nw",
            (4, 2): "new",
        }
    elif tile_type == "floor":
        return {
            # Row 0
            (0, 0): "se", (1, 0): "sew", (2, 0): "sw",
            (3, 0): "s", (5, 0): "lone",
            # Row 1
            (0, 1): "nse", (1, 1): "nsew", (2, 1): "nsw", (3, 1): "ns",
            (4, 1): "e", (5, 1): "ew", (6, 1): "w",
            # Row 2
            (0, 2): "ne", (1, 2): "new", (2, 2): "nw",
            (3, 2): "n",
        }
    return {}

def ensure_output_directory():
    """Create output directory if it doesn't exist."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Using output directory: {OUTPUT_DIR}")

def is_tile_transparent(image_tile):
    """
    Check if a tile is mostly transparent.
    Returns True if the tile should be skipped.
    """
    # Convert to RGBA if not already
    if image_tile.mode != 'RGBA':
        image_tile = image_tile.convert('RGBA')

    # Count non-transparent pixels
    pixels = list(image_tile.getdata())
    non_transparent_count = sum(1 for pixel in pixels if pixel[3] > 0)

    # Calculate percentage of non-transparent pixels
    total_pixels = len(pixels)
    non_transparent_ratio = non_transparent_count / total_pixels

    return non_transparent_ratio < TRANSPARENCY_THRESHOLD

def process_ground_png(png_path, temp_dir):
    """Process Ground0.png file - extract all tiles as individual sprites."""
    print(f"Processing ground tiles: {png_path}")

    try:
        # Load the image
        image = Image.open(png_path)

        # Calculate grid dimensions
        width, height = image.size
        cols = width // TILE_SIZE
        rows = height // TILE_SIZE

        print(f"  Image size: {width}x{height}, Grid: {cols}x{rows}")

        sprite_count = 0
        saved_count = 0

        # Extract each tile
        for row in range(rows):
            for col in range(cols):
                # Calculate tile coordinates
                left = col * TILE_SIZE
                top = row * TILE_SIZE
                right = left + TILE_SIZE
                bottom = top + TILE_SIZE

                # Extract tile
                tile = image.crop((left, top, right, bottom))

                # Check if tile is transparent
                if is_tile_transparent(tile):
                    sprite_count += 1
                    continue

                # Save non-transparent tile
                output_filename = f"ground-{sprite_count}.png"
                output_path = temp_dir / output_filename

                # Convert to RGBA to ensure proper transparency handling
                if tile.mode != 'RGBA':
                    tile = tile.convert('RGBA')

                tile.save(output_path, 'PNG')
                saved_count += 1
                sprite_count += 1

        print(f"  Saved {saved_count} ground tiles (skipped {sprite_count - saved_count} transparent tiles)")

    except Exception as e:
        print(f"Error processing {png_path}: {e}")

def process_floor_wall_png(png_path, temp_dir, tile_type, used_tile_names=None):
    """Process Floor.png or Wall.png file - extract tiles in 7x3 blocks with connectivity patterns."""
    print(f"Processing {tile_type} tiles: {png_path}")

    try:
        # Load the image
        image = Image.open(png_path)

        # Calculate grid dimensions
        width, height = image.size
        cols = width // TILE_SIZE
        rows = height // TILE_SIZE

        print(f"  Image size: {width}x{height}, Grid: {cols}x{rows}")

        # Skip first 3 rows as requested
        start_row = 3

        # Calculate how many 7x3 blocks we have
        available_rows = rows - start_row
        blocks_per_row = cols // 7
        total_blocks = (available_rows // 3) * blocks_per_row

        print(f"  Available blocks: {total_blocks} (skipping first 3 rows)")

        # Determine which blocks to process
        blocks_to_process = []
        if used_tile_names is not None:
            # Only process blocks that contain tiles we actually use
            for block_idx in range(total_blocks):
                # Check if any tile in this block is used
                block_used = False
                pattern_map = get_pattern_map_for_tile_type(tile_type)
                for local_row in range(3):
                    for local_col in range(7):
                        # Generate the expected tile name for this position
                        pattern = pattern_map.get((local_col, local_row), "unknown")
                        if pattern != "unknown" and pattern != "none":
                            expected_tile_name = f"{tile_type}-{block_idx + 1}-{pattern}"
                            if expected_tile_name in used_tile_names:
                                block_used = True
                                break
                    if block_used:
                        break

                if block_used:
                    blocks_to_process.append(block_idx)
        elif SET_THIS_TO_FALSE_TO_GET_ALL_TILES:
            blocks_to_process = list(range(min(7, total_blocks)))
        else:
            blocks_to_process = list(range(total_blocks))

        print(f"  Processing {len(blocks_to_process)} blocks")

        saved_count = 0

        # Process each 7x3 block
        for block_idx in blocks_to_process:
            # Calculate block position
            block_row = (block_idx // blocks_per_row) * 3 + start_row
            block_col = (block_idx % blocks_per_row) * 7

            block_name = f"{tile_type}-{block_idx + 1}"
            print(f"  Processing block {block_idx + 1}: {block_name}")

            # Extract tiles from this 7x3 block and map to connectivity patterns
            pattern_tiles = {}

            # Map the 7x3 block to connectivity patterns
            # Based on common autotile layouts
            if tile_type == "wall":
                pattern_map = {
                    # Row 0
                    (0, 0): "se", (1, 0): "ew", (2, 0): "sw",
                    (3, 0): "lone", (4, 0): "sew",
                    # Row 1
                    (0, 1): "ns", (1, 1): "n",
                    (3, 1): "nse", (4, 1): "nsew", (5, 1): "nsw",
                    # Row 2
                    (0, 2): "ne", (2, 2): "nw",
                    (4, 2): "new",
                }
            elif tile_type == "floor":
                pattern_map = {
                    # Row 0
                    (0, 0): "se", (1, 0): "sew", (2, 0): "sw",
                    (3, 0): "s", (5, 0): "lone",
                    # Row 1
                    (0, 1): "nse", (1, 1): "nsew", (2, 1): "nsw", (3, 1): "ns",
                    (4, 1): "e", (5, 1): "ew", (6, 1): "w",
                    # Row 2
                    (0, 2): "ne", (1, 2): "new", (2, 2): "nw",
                    (3, 2): "n",
                }

            # Extract each tile in the block
            for local_row in range(3):
                for local_col in range(7):
                    # Calculate absolute tile coordinates
                    abs_row = block_row + local_row
                    abs_col = block_col + local_col

                    # Skip if outside image bounds
                    if abs_row >= rows or abs_col >= cols:
                        continue

                    # Calculate tile coordinates
                    left = abs_col * TILE_SIZE
                    top = abs_row * TILE_SIZE
                    right = left + TILE_SIZE
                    bottom = top + TILE_SIZE

                    # Extract tile
                    tile = image.crop((left, top, right, bottom))

                    # Check if tile is transparent
                    if is_tile_transparent(tile):
                        continue

                    # Get pattern name for this position
                    pattern = pattern_map.get((local_col, local_row), "unknown")
                    if pattern == "none" or pattern == "unknown":
                        continue

                    # Save tile with pattern name
                    output_filename = f"{block_name}-{pattern}.png"
                    output_path = temp_dir / output_filename

                    # Convert to RGBA to ensure proper transparency handling
                    if tile.mode != 'RGBA':
                        tile = tile.convert('RGBA')

                    tile.save(output_path, 'PNG')
                    saved_count += 1

        print(f"  Saved {saved_count} {tile_type} tiles")

    except Exception as e:
        print(f"Error processing {png_path}: {e}")

def process_decor_png(png_path, temp_dir, used_tile_names=None):
    """Process Decor0.png file - extract all tiles from rows 4-15."""
    print(f"Processing decor tiles: {png_path}")

    try:
        # Load the image
        image = Image.open(png_path)

        # Calculate grid dimensions
        width, height = image.size
        cols = width // TILE_SIZE
        rows = height // TILE_SIZE

        print(f"  Image size: {width}x{height}, Grid: {cols}x{rows}")

        # Process rows 4-15 (inclusive)
        start_row = 4
        end_row = min(15, rows - 1)  # Ensure we don't exceed image bounds

        print(f"  Processing rows {start_row} to {end_row}")

        sprite_count = 0
        saved_count = 0

        # Extract tiles from rows 4-15
        for row in range(start_row, end_row + 1):
            for col in range(cols):
                # Calculate tile coordinates
                left = col * TILE_SIZE
                top = row * TILE_SIZE
                right = left + TILE_SIZE
                bottom = top + TILE_SIZE

                # Extract tile
                tile = image.crop((left, top, right, bottom))

                # Check if tile is transparent
                if is_tile_transparent(tile):
                    sprite_count += 1
                    continue

                # Check if this tile is used
                expected_tile_name = f"decor-{sprite_count}"
                if used_tile_names is not None and expected_tile_name not in used_tile_names:
                    sprite_count += 1
                    continue

                # Save non-transparent tile
                output_filename = f"decor-{sprite_count}.png"
                output_path = temp_dir / output_filename

                # Convert to RGBA to ensure proper transparency handling
                if tile.mode != 'RGBA':
                    tile = tile.convert('RGBA')

                tile.save(output_path, 'PNG')
                saved_count += 1
                sprite_count += 1

        print(f"  Saved {saved_count} decor tiles (skipped {sprite_count - saved_count} transparent tiles)")

    except Exception as e:
        print(f"Error processing {png_path}: {e}")

def process_tile_png(png_path, temp_dir, used_tile_names=None):
    """Process Tile.png file - extract all tiles regardless of SET_THIS_TO_FALSE_TO_GET_ALL_TILES."""
    print(f"Processing tile tiles: {png_path}")

    try:
        # Load the image
        image = Image.open(png_path)

        # Calculate grid dimensions
        width, height = image.size
        cols = width // TILE_SIZE
        rows = height // TILE_SIZE

        print(f"  Image size: {width}x{height}, Grid: {cols}x{rows}")

        sprite_count = 0
        saved_count = 0

        # Extract each tile (all tiles, ignoring SET_THIS_TO_FALSE_TO_GET_ALL_TILES)
        for row in range(rows):
            for col in range(cols):
                # Calculate tile coordinates
                left = col * TILE_SIZE
                top = row * TILE_SIZE
                right = left + TILE_SIZE
                bottom = top + TILE_SIZE

                # Extract tile
                tile = image.crop((left, top, right, bottom))

                # Check if tile is transparent
                if is_tile_transparent(tile):
                    sprite_count += 1
                    continue

                # Check if this tile is used
                expected_tile_name = f"tile-{sprite_count}"
                if used_tile_names is not None and expected_tile_name not in used_tile_names:
                    sprite_count += 1
                    continue

                # Save non-transparent tile
                output_filename = f"tile-{sprite_count}.png"
                output_path = temp_dir / output_filename

                # Convert to RGBA to ensure proper transparency handling
                if tile.mode != 'RGBA':
                    tile = tile.convert('RGBA')

                tile.save(output_path, 'PNG')
                saved_count += 1
                sprite_count += 1

        print(f"  Saved {saved_count} tile tiles (skipped {sprite_count - saved_count} transparent tiles)")

    except Exception as e:
        print(f"Error processing {png_path}: {e}")

def process_doors_png(png_path, temp_dir, tile_type, used_tile_names=None):
    """Process Door0.png or Door1.png file - extract all tiles."""
    print(f"Processing door tiles: {png_path}")

    try:
        # Load the image
        image = Image.open(png_path)

        # Calculate grid dimensions
        width, height = image.size
        cols = width // TILE_SIZE
        rows = height // TILE_SIZE

        print(f"  Image size: {width}x{height}, Grid: {cols}x{rows}")

        sprite_count = 0
        saved_count = 0

        # Extract each tile
        for row in range(rows):
            for col in range(cols):
                # Calculate tile coordinates
                left = col * TILE_SIZE
                top = row * TILE_SIZE
                right = left + TILE_SIZE
                bottom = top + TILE_SIZE

                # Extract tile
                tile = image.crop((left, top, right, bottom))

                # Check if tile is transparent
                if is_tile_transparent(tile):
                    sprite_count += 1
                    continue

                # Check if this tile is used
                expected_tile_name = f"{tile_type}-{sprite_count}"
                if used_tile_names is not None and expected_tile_name not in used_tile_names:
                    sprite_count += 1
                    continue

                # Save non-transparent tile
                output_filename = f"{tile_type}-{sprite_count}.png"
                output_path = temp_dir / output_filename

                # Convert to RGBA to ensure proper transparency handling
                if tile.mode != 'RGBA':
                    tile = tile.convert('RGBA')

                tile.save(output_path, 'PNG')
                saved_count += 1
                sprite_count += 1

        print(f"  Saved {saved_count} door tiles (skipped {sprite_count - saved_count} transparent tiles)")

    except Exception as e:
        print(f"Error processing {png_path}: {e}")

def collect_world_sprites(temp_dir):
    """Collect all sprite files."""
    sprite_files = list(temp_dir.glob("*.png"))
    return sorted(sprite_files)

def calculate_optimal_atlas_size(num_sprites):
    """Calculate the optimal atlas size for the given number of sprites."""
    import math

    # Calculate how many sprites fit per row
    # Start with a square-ish layout
    sprites_per_row = math.ceil(math.sqrt(num_sprites))

    # Calculate required dimensions
    atlas_width = sprites_per_row * SPRITE_WIDTH
    atlas_height = math.ceil(num_sprites / sprites_per_row) * SPRITE_HEIGHT

    # Round up to next power of 2 for better GPU compatibility (optional)
    def next_power_of_2(n):
        return 1 << (n - 1).bit_length()

    atlas_width = next_power_of_2(atlas_width)
    atlas_height = next_power_of_2(atlas_height)

    return atlas_width, atlas_height, sprites_per_row

def create_debug_tile():
    tile = Image.new('RGBA', (SPRITE_WIDTH, SPRITE_HEIGHT), (255, 165, 0, 255))  # Orange
    return tile

def create_atlas(sprite_files, used_tile_names=None):
    """Create the sprite atlas and coordinate JSON."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Filter sprite files to only include those used in map_renderer.gd
    filtered_sprite_files = []
    for sprite_file in sprite_files:
        sprite_name = sprite_file.stem
        if used_tile_names is not None and sprite_name not in used_tile_names:
            continue
        print(f"Adding sprite: {sprite_name}")
        filtered_sprite_files.append(sprite_file)

    # Add debug tile
    debug_tile = create_debug_tile()
    debug_tile_path = OUTPUT_DIR / "debug.png"
    debug_tile.save(debug_tile_path, 'PNG')
    filtered_sprite_files.append(debug_tile_path)

    atlas_width, atlas_height, sprites_per_row = calculate_optimal_atlas_size(len(filtered_sprite_files))

    print(f"Creating world atlas with {len(filtered_sprite_files)} sprites")
    print(f"Atlas dimensions: {atlas_width}x{atlas_height} ({sprites_per_row} sprites per row)")

    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))
    coordinates = {}

    for i, sprite_file in enumerate(filtered_sprite_files):
        sprite_image = Image.open(sprite_file).convert('RGBA')
        x = (i % sprites_per_row) * SPRITE_WIDTH
        y = (i // sprites_per_row) * SPRITE_HEIGHT
        atlas.paste(sprite_image, (x, y))
        sprite_name = sprite_file.stem
        coordinates[sprite_name] = [x, y]

    # Add watermark
    draw = ImageDraw.Draw(atlas)
    font = ImageFont.load_default()
    text = WATERMARK
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        text_w, text_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    except AttributeError:
        text_w, text_h = font.getsize(text)
    margin = 4
    x = atlas_width - text_w - margin
    y = atlas_height - text_h - margin
    # Draw black outline
    for dx in [-1, 0, 1]:
        for dy in [-1, 0, 1]:
            if dx or dy:
                draw.text((x+dx, y+dy), text, font=font, fill=(0,0,0,255))
    # Draw white text
    draw.text((x, y), text, font=font, fill=(255,255,255,255))

    atlas_path = OUTPUT_DIR / "world_tiles.png"
    atlas.save(atlas_path, 'PNG')

    json_data = {
        "tileSize": SPRITE_WIDTH,
        "sprites": coordinates
    }
    json_path = OUTPUT_DIR / "world_tiles.json"
    with open(json_path, 'w') as f:
        json.dump(json_data, f, indent=2)

    print(f"Created atlas at {atlas_path}")
    print(f"Created coordinate data at {json_path}")
    return True

def main():
    """Main function to process all world tile PNGs."""
    print("DawnLike World Tile Processor")
    print("=" * 40)

    # Change to project root directory
    change_to_project_root()
    print()

    # Extract used tile names from map_renderer.gd
    used_tile_names = extract_used_tile_names()

    # Check if objects directory exists
    if not OBJECTS_DIR.exists():
        print(f"Error: DawnLike Objects directory not found: {OBJECTS_DIR}")
        print()
        print("The DawnLike tileset is required to run this script.")
        print("Please follow the setup instructions in the main project README.md")
        print("to download and install the DawnLike tileset.")
        print()
        sys.exit(1)

    # Create output directory
    ensure_output_directory()

    # Define the files we need to process
    world_files = [
        ("Ground0.png", "ground"),
        ("Floor.png", "floor"),
        ("Wall.png", "wall"),
        ("Decor0.png", "decor"),
        ("Tile.png", "tile"),
        ("Door0.png", "doors0"),
        ("Door1.png", "doors1")
    ]

    # Check if all required files exist
    missing_files = []
    for filename, _ in world_files:
        if not (OBJECTS_DIR / filename).exists():
            missing_files.append(filename)

    if missing_files:
        print(f"Error: Missing required files: {missing_files}")
        print(f"These files should be in: {OBJECTS_DIR}")
        sys.exit(1)

    print(f"Found all required world tile files")
    print()

    # Create temporary directory and process files
    with tempfile.TemporaryDirectory() as temp_dir_str:
        temp_dir = Path(temp_dir_str)
        print(f"Using temporary directory: {temp_dir}")
        print()

        # Process each world file
        for filename, tile_type in world_files:
            file_path = OBJECTS_DIR / filename

            if tile_type == "ground":
                process_ground_png(file_path, temp_dir)
            elif tile_type == "decor":
                process_decor_png(file_path, temp_dir, used_tile_names)
            elif tile_type == "tile":
                process_tile_png(file_path, temp_dir, used_tile_names)
            elif tile_type == "doors0" or tile_type == "doors1":
                process_doors_png(file_path, temp_dir, tile_type, used_tile_names)
            else:
                process_floor_wall_png(file_path, temp_dir, tile_type, used_tile_names)
            print()

        print("Processing complete!")
        print()

        # Generate atlas from extracted tiles
        print("Generating world atlas...")
        sprite_files = collect_world_sprites(temp_dir)

        if sprite_files:
            success = create_atlas(sprite_files, used_tile_names)
            if success:
                print("Atlas generation complete!")
                print("Temporary files cleaned up.")
            else:
                print("Atlas generation failed!")
                sys.exit(1)
        else:
            print("No sprites found for atlas generation")

    # Temporary directory is automatically cleaned up here

if __name__ == "__main__":
    main()