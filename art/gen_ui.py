#!/usr/bin/env python3
"""
Script to copy and watermark the DawnLike GUI0.png tileset as ui.png for use in the game.
Places a watermark in the lower right corner, matching the style of the world tileset atlas.
"""
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SRC_IMAGE = Path("art/DawnLike/GUI/GUI0.png")
DST_IMAGE = Path("assets/generated/ui.png")

WATERMARK = "DawnLike tiles by DawnBringer"
MARGIN = 4
TARGET_SIZE = (512, 512)


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

def add_watermark(image: Image.Image, text: str) -> Image.Image:
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        text_w, text_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    except AttributeError:
        text_w, text_h = font.getsize(text)
    x = image.width - text_w - MARGIN
    y = image.height - text_h - MARGIN
    # Draw black outline
    for dx in [-1, 0, 1]:
        for dy in [-1, 0, 1]:
            if dx or dy:
                draw.text((x+dx, y+dy), text, font=font, fill=(0,0,0,255))
    # Draw white text
    draw.text((x, y), text, font=font, fill=(255,255,255,255))
    return image

def main():
    print("DawnLike GUI Processor")
    print("=" * 40)

    # Change to project root directory
    change_to_project_root()
    print()

    if not SRC_IMAGE.exists():
        print(f"Source image not found: {SRC_IMAGE}")
        return
    DST_IMAGE.parent.mkdir(parents=True, exist_ok=True)
    img = Image.open(SRC_IMAGE).convert("RGBA")

    # Create new canvas and paste original image 1:1 in upper left
    print(f"Creating {TARGET_SIZE} canvas with original image {img.size} in upper left")
    canvas = Image.new('RGBA', TARGET_SIZE, (0, 0, 0, 0))
    canvas.paste(img, (0, 0))

    canvas = add_watermark(canvas, WATERMARK)
    canvas.save(DST_IMAGE)
    print(f"Copied and watermarked: {DST_IMAGE}")

if __name__ == "__main__":
    main()