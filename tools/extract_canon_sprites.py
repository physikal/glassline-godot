#!/usr/bin/env python3
"""Crop Josh-locked canon plates into painted toy-spy sprites.

Rifles / doll / hex stamps are lifted from assets/canon/ — not invented
as rectangles. Wood / hex-fill is keyed out so the paint stays.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
CANON = ROOT / "assets" / "canon"
OUT = ROOT / "assets" / "art_v2"
PREVIEW = Path("/tmp/art_crops")
OUT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)


def load_jpg(name: str) -> Image.Image:
    img = Image.open(CANON / name).convert("RGBA")
    return img


def crop(img: Image.Image, box: tuple[int, int, int, int], name: str) -> Image.Image:
    piece = img.crop(box)
    piece.save(PREVIEW / f"{name}.png")
    return piece


def dist(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def key_wood(src: Image.Image, samples: list[tuple[int, int]], thresh: float = 42.0) -> Image.Image:
    """Make pixels near sampled wood transparent. Keep painted gun / doll."""
    px = src.load()
    w, h = src.size
    woods = [src.getpixel((x, y))[:3] for x, y in samples if 0 <= x < w and 0 <= y < h]
    if not woods:
        woods = [(110, 72, 42)]
    out = src.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if min(dist((r, g, b), wcol) for wcol in woods) <= thresh:
                op[x, y] = (r, g, b, 0)
    return out


def key_near(src: Image.Image, colors: list[tuple[int, int, int]], thresh: float) -> Image.Image:
    px = src.load()
    w, h = src.size
    out = src.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if min(dist((r, g, b), c) for c in colors) <= thresh:
                op[x, y] = (r, g, b, 0)
    return out


def trim_alpha(img: Image.Image, pad: int = 2) -> Image.Image:
    bbox = img.split()[-1].getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(img.width, r + pad)
    b = min(img.height, b + pad)
    return img.crop((l, t, r, b))


def lock_wash(img: Image.Image) -> Image.Image:
    """Readable locked silhouette — same painted gun, cooler + darker, not a bar."""
    faded = ImageEnhance.Color(img).enhance(0.28)
    faded = ImageEnhance.Brightness(faded).enhance(0.62)
    return faded


def save_sprite(img: Image.Image, name: str) -> None:
    img.save(OUT / name)
    img.save(PREVIEW / name)


def extract_rifles(plate: Image.Image) -> None:
    ## Grid-locked on 1280x720 lobby-canon.jpg (RIFLE RACK plank at y≈160).
    ## Olive / tan / teal painted bolts — Fieldbolt / Railframe / Crescent.
    regions = {
        "fieldbolt": (24, 192, 292, 248),
        "railframe": (24, 252, 292, 308),
        "crescent": (24, 312, 292, 368),
        "held": (600, 320, 828, 408),
    }
    ## Sample open wall only — never the guns.
    wood_abs = [(36, 180), (250, 180), (36, 380), (250, 380), (120, 180)]
    for name, box in regions.items():
        raw = crop(plate, box, f"rifle_{name}_raw")
        local = [(x - box[0], y - box[1]) for x, y in wood_abs]
        ## Gentle wood key — keep olive / tan / teal / barrel ink.
        keyed = key_wood(raw, local, thresh=28)
        sprite = trim_alpha(keyed, 2)
        save_sprite(raw, f"rifle_{name}_plate.png")  # wood-backed, plate-accurate
        save_sprite(sprite, f"rifle_{name}.png")
        save_sprite(lock_wash(sprite), f"rifle_{name}_locked.png")
        save_sprite(lock_wash(raw), f"rifle_{name}_plate_locked.png")


def extract_operatives(teal: Image.Image, ghillie: Image.Image) -> None:
    ## Paper-doll crops — same hideout body. Keep a wood halo; do not over-key.
    teal_box = (536, 176, 768, 560)
    ghil_box = (536, 176, 768, 560)
    teal_raw = crop(teal, teal_box, "doll_teal_raw")
    ghil_raw = crop(ghillie, ghil_box, "doll_ghillie_raw")
    save_sprite(teal_raw, "doll_teal_plate.png")
    save_sprite(ghil_raw, "doll_ghillie_plate.png")
    wood = [(8, 8), (220, 8), (8, 360), (220, 360)]
    teal_s = trim_alpha(key_wood(teal_raw, wood, 26), 2)
    ghil_s = trim_alpha(key_wood(ghil_raw, wood, 26), 2)
    save_sprite(teal_s, "doll_teal.png")
    save_sprite(ghil_s, "doll_ghillie.png")
    face = crop(teal, (568, 176, 736, 312), "face_teal_raw")
    save_sprite(face, "face_teal_plate.png")
    save_sprite(trim_alpha(key_wood(face, [(6, 6), (160, 6)], 26), 1), "face_teal.png")
    gface = crop(ghillie, (568, 176, 736, 312), "face_ghillie_raw")
    save_sprite(gface, "face_ghillie_plate.png")
    save_sprite(trim_alpha(key_wood(gface, [(6, 6), (160, 6)], 26), 1), "face_ghillie.png")


def extract_hex(hex_map: Image.Image) -> None:
    ## Legend hexes (left column) are the Josh-locked painted stamps.
    legend = {
        "hex_open": (20, 148, 108, 216),
        "hex_brush": (20, 216, 108, 284),
        "hex_hard": (20, 296, 108, 364),
        "hex_unknown": (20, 376, 108, 444),
    }
    for name, box in legend.items():
        raw = crop(hex_map, box, f"{name}_legend_raw")
        save_sprite(raw, f"{name}_legend.png")

    ## Board hexes — same paint, larger clumps / rock piles.
    board = {
        "hex_brush": (488, 188, 552, 252),
        "hex_brush_b": (808, 188, 872, 252),
        "hex_hard": (568, 188, 632, 252),
        "hex_hard_b": (648, 188, 712, 252),
        "hex_open": (408, 188, 472, 252),
        "hex_unknown": (328, 168, 392, 232),
    }
    for name, box in board.items():
        raw = crop(hex_map, box, f"{name}_board_raw")
        save_sprite(raw, f"{name}_tile.png")

    ## Brush clump only — key the green hex fill, keep the darker painted bush.
    brush = crop(hex_map, (500, 200, 540, 240), "brush_clump_raw")
    brush = key_near(brush, [(118, 168, 72), (132, 178, 80), (148, 188, 92), (104, 156, 64)], 22)
    save_sprite(trim_alpha(brush, 1), "stamp_brush.png")

    rock = crop(hex_map, (580, 200, 620, 240), "rock_pile_raw")
    rock = key_near(rock, [(158, 162, 168), (148, 152, 158), (170, 174, 180), (140, 144, 150)], 18)
    save_sprite(trim_alpha(rock, 1), "stamp_rock.png")

    open_s = crop(hex_map, (416, 196, 464, 244), "open_speck_raw")
    save_sprite(open_s, "stamp_open.png")


def extract_optic_bits(optic: Image.Image) -> None:
    save_sprite(optic, "optic_plate.png")  # full plate used as Attack world
    fire = crop(optic, (1088, 528, 1248, 688), "optic_fire_raw")
    save_sprite(fire, "optic_fire.png")
    zoom = crop(optic, (36, 236, 196, 430), "optic_zoom_raw")
    save_sprite(zoom, "optic_zoom.png")


def contact_preview() -> None:
    files = sorted(OUT.glob("*.png"))
    if not files:
        return
    cols = 4
    cell = 220
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (40, 24, 16, 255))
    for i, path in enumerate(files):
        im = Image.open(path).convert("RGBA")
        im.thumbnail((cell - 16, cell - 16))
        x = (i % cols) * cell + (cell - im.width) // 2
        y = (i // cols) * cell + (cell - im.height) // 2
        sheet.paste(im, (x, y), im)
    sheet.save(PREVIEW / "sprite_sheet.png")


def main() -> None:
    teal = load_jpg("lobby-canon.jpg")
    ghil = load_jpg("lobby-ghillie.jpg")
    hx = load_jpg("hex-map.jpg")
    op = load_jpg("optic-attack.jpg")
    extract_rifles(teal)
    extract_operatives(teal, ghil)
    extract_hex(hx)
    extract_optic_bits(op)
    contact_preview()
    print("ART_V2_SPRITES", OUT)
    for p in sorted(OUT.iterdir()):
        print(f"  {p.name} {Image.open(p).size}")


if __name__ == "__main__":
    main()
