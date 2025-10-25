#!/usr/bin/env python3
"""
Script to process DawnLike character tilesets into individual sprite files.
Each PNG contains 16x16 tiles arranged in a grid.
Extracts non-transparent tiles and saves them as individual files.
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
import csv

# Configuration
TILE_SIZE = 16
CHARACTERS_DIR = Path("art/DawnLike/Characters")
OUTPUT_DIR = Path("assets/generated")
TRANSPARENCY_THRESHOLD = 0.1  # Skip tiles with less than 10% non-transparent pixels

# Sprite extraction limits
SET_THIS_TO_FALSE_TO_GET_ALL_CHARACTERS = True  # Set to False to extract all sprites

# Atlas configuration
SPRITE_WIDTH = 32  # Double width for 2 frames (16+16)
SPRITE_HEIGHT = 16  # Same as tile height

WATERMARK = "DawnLike tiles by DawnBringer"

def read_allowed_sprite_names_from_csv():
    """Read monsters.csv and extract sprite names from the appearance column."""
    monsters_csv_path = Path("assets/data/monsters.csv")
    allowed_sprite_names = set()

    with open(monsters_csv_path, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            appearance = row.get('appearance', '').strip()
            if appearance:
                sprite_names = [name.strip() for name in appearance.split(',')]
                allowed_sprite_names.update(sprite_names)

    print(f"Loaded {len(allowed_sprite_names)} sprite names from monsters.csv:")
    for sprite_name in sorted(allowed_sprite_names):
        print(f"  {sprite_name}")
    print()

    return allowed_sprite_names

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

def extract_character_name(filename):
    """Extract character name from filename (everything before the number)."""
    # Remove .png extension and extract name before the number
    name_without_ext = filename.stem
    match = re.match(r'^(.+?)(\d+)$', name_without_ext)
    if match:
        return match.group(1).lower(), int(match.group(2))
    return name_without_ext.lower(), 0

def process_character_png(png_path, temp_dir):
    """Process a single character PNG file."""
    print(f"Processing: {png_path}")

    try:
        # Load the image
        image = Image.open(png_path)

        # Extract character name and frame number
        char_name, frame = extract_character_name(png_path)

        # Calculate grid dimensions
        width, height = image.size
        cols = width // TILE_SIZE
        rows = height // TILE_SIZE

        print(f"  Character: {char_name}, Frame: {frame}")
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
                output_filename = f"{char_name}-{sprite_count}-{frame}.png"
                output_path = temp_dir / output_filename

                # Convert to RGBA to ensure proper transparency handling
                if tile.mode != 'RGBA':
                    tile = tile.convert('RGBA')

                tile.save(output_path, 'PNG')
                saved_count += 1
                sprite_count += 1

        print(f"  Saved {saved_count} tiles{limit_msg} (skipped {sprite_count - saved_count} transparent tiles)")

    except Exception as e:
        print(f"Error processing {png_path}: {e}")

def collect_sprite_pairs(temp_dir):
    """Collect all sprite files and group them by character and sprite number."""
    sprite_files = list(temp_dir.glob("*.png"))
    sprite_groups = defaultdict(list)

    for sprite_file in sprite_files:
        # Parse filename: character-sprite_number-frame.png
        parts = sprite_file.stem.split('-')
        if len(parts) >= 3:
            char_name = parts[0]
            sprite_num = parts[1]
            frame = parts[2]
            sprite_groups[f"{char_name}-{sprite_num}"].append((int(frame), sprite_file))

    return sprite_groups

def create_double_width_sprite(frame_0_path, frame_1_path):
    """Create a double-width sprite by combining two frames side by side."""
    # Load both frames
    frame_0 = Image.open(frame_0_path).convert('RGBA')
    frame_1 = Image.open(frame_1_path).convert('RGBA')

    # Create double-width sprite
    combined = Image.new('RGBA', (SPRITE_WIDTH, SPRITE_HEIGHT), (0, 0, 0, 0))

    # Paste frame 0 on the left, frame 1 on the right
    combined.paste(frame_0, (0, 0))
    combined.paste(frame_1, (TILE_SIZE, 0))

    return combined

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

    # Ensure minimum atlas size of 256x256
    MIN_ATLAS_SIZE = 256
    atlas_width = max(atlas_width, MIN_ATLAS_SIZE)
    atlas_height = max(atlas_height, MIN_ATLAS_SIZE)

    return atlas_width, atlas_height, sprites_per_row

def create_debug_tile():
    tile = Image.new('RGBA', (SPRITE_WIDTH, SPRITE_HEIGHT), (255, 165, 0, 255))  # Orange, double-width
    return tile

def create_atlas(sprite_groups):
    """Create the sprite atlas and coordinate JSON."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Prepare sprites for atlas
    atlas_sprites = []
    coordinates = {}

    allowed_sprite_names = read_allowed_sprite_names_from_csv()

    for sprite_name, frames in sorted(sprite_groups.items()):
        frames.sort(key=lambda x: x[0])
        if len(frames) == 2:
            frame_0_path = frames[0][1]
            frame_1_path = frames[1][1]
            combined_sprite = create_double_width_sprite(frame_0_path, frame_1_path)
            if SET_THIS_TO_FALSE_TO_GET_ALL_CHARACTERS and sprite_name not in allowed_sprite_names:
                continue
            print(f"Adding sprite: {sprite_name}")
            atlas_sprites.append((sprite_name, combined_sprite))
        elif len(frames) == 1:
            frame_path = frames[0][1]
            combined_sprite = create_double_width_sprite(frame_path, frame_path)
            if SET_THIS_TO_FALSE_TO_GET_ALL_CHARACTERS and sprite_name not in allowed_sprite_names:
                continue
            print(f"Adding sprite: {sprite_name}")
            atlas_sprites.append((sprite_name, combined_sprite))

    # Add debug tile
    debug_tile = create_debug_tile()
    atlas_sprites.append(("debug", debug_tile))

    atlas_width, atlas_height, sprites_per_row = calculate_optimal_atlas_size(len(atlas_sprites))

    print(f"Creating character atlas with {len(atlas_sprites)} sprites")
    print(f"Atlas dimensions: {atlas_width}x{atlas_height} ({sprites_per_row} sprites per row)")

    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

    for i, (sprite_name, sprite_image) in enumerate(atlas_sprites):
        x = (i % sprites_per_row) * SPRITE_WIDTH
        y = (i // sprites_per_row) * SPRITE_HEIGHT
        atlas.paste(sprite_image, (x, y))
        coordinates[sprite_name] = [x, y]

    # Add watermark
    from PIL import ImageDraw, ImageFont
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
    for dx in [-1, 0, 1]:
        for dy in [-1, 0, 1]:
            if dx or dy:
                draw.text((x+dx, y+dy), text, font=font, fill=(0,0,0,255))
    draw.text((x, y), text, font=font, fill=(255,255,255,255))

    atlas_path = OUTPUT_DIR / "character_tiles.png"
    atlas.save(atlas_path, 'PNG')

    json_data = {
        "tileWidth": SPRITE_WIDTH,
        "tileHeight": SPRITE_HEIGHT,
        "sprites": coordinates
    }
    json_path = OUTPUT_DIR / "character_tiles.json"
    with open(json_path, 'w') as f:
        json.dump(json_data, f, indent=2)

    print(f"Created atlas at {atlas_path}")
    print(f"Created coordinate data at {json_path}")
    return True

def main():
    """Main function to process all character PNGs."""
    print("DawnLike Character Tile Processor")
    print("=" * 40)

    # Change to project root directory
    change_to_project_root()
    print()

    # Check if characters directory exists
    if not CHARACTERS_DIR.exists():
        print(f"Error: DawnLike Characters directory not found: {CHARACTERS_DIR}")
        print()
        print("The DawnLike tileset is required to run this script.")
        print("Please follow the setup instructions in the main project README.md")
        print("to download and install the DawnLike tileset.")
        print()
        sys.exit(1)

    # Create output directory
    ensure_output_directory()

    # Find all PNG files in the characters directory
    png_files = list(CHARACTERS_DIR.glob("*.png"))

    if not png_files:
        print("No PNG files found in Characters directory")
        return

    print(f"Found {len(png_files)} PNG files to process")
    print()

    # Create temporary directory and process files
    with tempfile.TemporaryDirectory() as temp_dir_str:
        temp_dir = Path(temp_dir_str)
        print(f"Using temporary directory: {temp_dir}")
        print()

        # Process each PNG file
        total_processed = 0
        for png_file in sorted(png_files):
            process_character_png(png_file, temp_dir)
            total_processed += 1
            print()

        print(f"Processing complete! Processed {total_processed} files.")
        print(f"Individual tiles saved to: {temp_dir.absolute()}")
        print()

        # Generate atlas from extracted tiles
        print("Generating sprite atlas...")
        sprite_groups = collect_sprite_pairs(temp_dir)

        if sprite_groups:
            success = create_atlas(sprite_groups)
            if success:
                print("Atlas generation complete!")
                print("Temporary files cleaned up.")
            else:
                print("Atlas generation failed!")
                sys.exit(1)
        else:
            print("No sprite pairs found for atlas generation")

    # Temporary directory is automatically cleaned up here

if __name__ == "__main__":
    main()