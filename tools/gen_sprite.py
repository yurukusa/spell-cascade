#!/usr/bin/env python3
"""Procedural symmetric sprite generator for game factory pipeline.

Generates pixel art sprites using Pillow + NumPy. No GUI required.
Outputs PNG files ready for Godot import.

Usage:
    python3 tools/gen_sprite.py --type enemy --size 32 --count 5 --out assets/sprites/enemies/
    python3 tools/gen_sprite.py --type projectile --size 16 --count 3 --palette fire
    python3 tools/gen_sprite.py --type icon --size 24 --count 1 --seed 42
"""

import argparse
import os
import random
from typing import List, Tuple

import numpy as np
from PIL import Image

# Color palettes (retro game-friendly, limited colors)
PALETTES = {
    "fire": [(255, 80, 20), (255, 160, 40), (255, 220, 80), (200, 40, 10)],
    "ice": [(60, 120, 255), (120, 180, 255), (200, 230, 255), (40, 80, 200)],
    "poison": [(40, 200, 60), (80, 255, 100), (160, 255, 120), (20, 140, 40)],
    "dark": [(80, 40, 120), (140, 60, 180), (180, 100, 220), (60, 20, 80)],
    "neutral": [(180, 180, 180), (220, 220, 220), (140, 140, 140), (100, 100, 100)],
    "gold": [(255, 200, 40), (255, 220, 100), (200, 160, 20), (180, 140, 10)],
}


def generate_symmetric_sprite(
    size: int, palette: List[Tuple[int, int, int]], density: float = 0.4, rng: random.Random = None
) -> Image.Image:
    """Generate a vertically symmetric pixel art sprite.

    Why symmetric: Most game entities (enemies, projectiles, icons) have
    bilateral symmetry. This makes procedural sprites look intentional.
    """
    if rng is None:
        rng = random.Random()

    half_w = (size + 1) // 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = img.load()

    # Generate the left half, mirror to right
    for y in range(size):
        for x in range(half_w):
            # Higher density near center for more cohesive shapes
            center_factor = 1.0 - abs(x - half_w / 2) / (half_w / 2) * 0.3
            center_factor *= 1.0 - abs(y - size / 2) / (size / 2) * 0.3

            if rng.random() < density * center_factor:
                color = rng.choice(palette)
                pixels[x, y] = (*color, 255)
                # Mirror
                mirror_x = size - 1 - x
                if mirror_x != x:
                    pixels[mirror_x, y] = (*color, 255)

    return img


def generate_projectile_sprite(
    size: int, palette: List[Tuple[int, int, int]], rng: random.Random = None
) -> Image.Image:
    """Generate a small projectile sprite (diamond/circle shape)."""
    if rng is None:
        rng = random.Random()

    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = img.load()
    center = size / 2
    radius = size / 2 - 1

    for y in range(size):
        for x in range(size):
            dist = ((x - center) ** 2 + (y - center) ** 2) ** 0.5
            if dist <= radius:
                # Core is brighter, edge is darker
                brightness = 1.0 - (dist / radius) * 0.5
                color = palette[0] if dist < radius * 0.5 else palette[1 % len(palette)]
                r = min(255, int(color[0] * brightness))
                g = min(255, int(color[1] * brightness))
                b = min(255, int(color[2] * brightness))
                alpha = 255 if dist < radius * 0.8 else int(255 * (1.0 - (dist - radius * 0.8) / (radius * 0.2)))
                pixels[x, y] = (r, g, b, max(0, alpha))

    return img


def generate_icon_sprite(
    size: int, palette: List[Tuple[int, int, int]], rng: random.Random = None
) -> Image.Image:
    """Generate an icon-style sprite (for upgrades, items)."""
    if rng is None:
        rng = random.Random()

    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = img.load()

    # Border
    border_color = palette[-1]
    for x in range(size):
        pixels[x, 0] = (*border_color, 255)
        pixels[x, size - 1] = (*border_color, 255)
    for y in range(size):
        pixels[0, y] = (*border_color, 255)
        pixels[size - 1, y] = (*border_color, 255)

    # Fill interior with symmetric pattern
    for y in range(2, size - 2):
        for x in range(2, size // 2):
            if rng.random() < 0.5:
                color = rng.choice(palette[:-1])
                pixels[x, y] = (*color, 255)
                pixels[size - 1 - x, y] = (*color, 255)

    return img


def main():
    parser = argparse.ArgumentParser(description="Procedural sprite generator")
    parser.add_argument("--type", choices=["enemy", "projectile", "icon"], default="enemy")
    parser.add_argument("--size", type=int, default=32, help="Sprite size in pixels")
    parser.add_argument("--count", type=int, default=5, help="Number of sprites to generate")
    parser.add_argument("--palette", choices=list(PALETTES.keys()), default="fire")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducibility")
    parser.add_argument("--out", default="assets/sprites/generated/", help="Output directory")
    parser.add_argument("--scale", type=int, default=1, help="Scale factor (nearest neighbor)")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    palette = PALETTES[args.palette]
    rng = random.Random(args.seed)

    generators = {
        "enemy": generate_symmetric_sprite,
        "projectile": generate_projectile_sprite,
        "icon": generate_icon_sprite,
    }
    gen_func = generators[args.type]

    print(f"Generating {args.count} {args.type} sprites ({args.size}x{args.size}, palette={args.palette})")

    for i in range(args.count):
        sprite = gen_func(args.size, palette, rng=rng)
        if args.scale > 1:
            new_size = args.size * args.scale
            sprite = sprite.resize((new_size, new_size), Image.NEAREST)

        filename = f"{args.type}_{args.palette}_{i:03d}.png"
        filepath = os.path.join(args.out, filename)
        sprite.save(filepath)
        size_kb = os.path.getsize(filepath) / 1024
        print(f"  {filename} ({size_kb:.1f}KB)")

    print(f"\nDone. {args.count} sprites saved to {args.out}")


if __name__ == "__main__":
    main()
