#!/usr/bin/env python3
"""Crop Josh-locked canon plates into painted toy-spy sprites.

Rifles / doll / hex stamps are lifted from assets/canon/ — not invented
as rectangles. Wood / hex-fill is keyed out so the paint stays.
"""
from __future__ import annotations

import math
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


def hex_alpha_mask(width: int, height: int) -> Image.Image:
    """Pointy-top hex alpha — corners stay transparent so tiles are not rects."""
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    cx = (width - 1) / 2.0
    cy = (height - 1) / 2.0
    radius = min(width, height) / 2.0 - 0.6
    pts = []
    for i in range(6):
        ang = math.radians(60.0 * i - 30.0)
        pts.append((cx + radius * math.cos(ang), cy + radius * math.sin(ang)))
    draw.polygon(pts, fill=255)
    return mask


def apply_hex_mask(img: Image.Image) -> Image.Image:
    out = img.convert("RGBA")
    mask = hex_alpha_mask(out.width, out.height)
    out.putalpha(mask)
    return out


## Measured on match-board-canon.jpg. Same-row ? centers sit ~98px apart
## (flat-to-flat). A 94×108 window centered between rows pulled the neighbor
## border and a second ? into the mask, which tiled as a stair-stack.
BOARD_PITCH = 98.0
BOARD_HEX_CENTERS = {
    "hex_open": (472, 216),
    "hex_brush": (664, 216),
    "hex_hard": (712, 300),
    "hex_unknown": (517, 150),
}


def isolate_board_hex(plate: Image.Image, cx: float, cy: float, pitch: float = BOARD_PITCH) -> Image.Image:
    """One pointy face. Width is flat-to-flat, height is point-to-point."""
    width = int(round(pitch))
    height = int(round(2.0 * pitch / math.sqrt(3.0)))
    left = int(round(cx - width / 2.0))
    top = int(round(cy - height / 2.0))
    raw = plate.crop((left, top, left + width, top + height))
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    rad = width / math.sqrt(3.0)
    ccx = (width - 1) / 2.0
    ccy = (height - 1) / 2.0
    pts = []
    for i in range(6):
        ang = math.radians(60.0 * i - 30.0)
        pts.append((ccx + rad * math.cos(ang), ccy + rad * math.sin(ang)))
    draw.polygon(pts, fill=255)
    out = raw.convert("RGBA")
    out.putalpha(mask)
    return out


def _pointy_edge_distance(x: float, y: float, width: int, height: int) -> float:
    """Pixel distance inside a pointy-top hex. Negative is outside."""
    size = height / 2.0
    dx = abs(x - (width - 1) / 2.0)
    dy = abs(y - (height - 1) / 2.0)
    apothem = size * math.sqrt(3.0) / 2.0
    flat = apothem - dx
    slant = apothem - (dx * 0.5 + dy * math.sqrt(3.0) / 2.0)
    return min(flat, slant)


def flatten_board_hex(src: Image.Image, face: tuple[int, int, int], outline: tuple[int, int, int] = (14, 12, 10)) -> Image.Image:
    """Shared edge is one thin line. Drop the north shadow cap and neighbor bleed.

    The UNKNOWN crop's top point included the turn-bar black, which tiled as a
    stair / shingle. Interior paint (the ?, bushes, rocks) stays. The rim is a
    uniform face color plus a 3px outline on every side.
    """
    width, height = src.size
    px = src.load()
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    op = out.load()
    stroke = 3.0
    # Deep enough to eat the turn-bar black that sat in the UNKNOWN north point.
    # The ? / bush / rock paint lives further in (edge distance ~37+).
    rim = 30.0
    fr, fg, fb = face
    or_, og, ob = outline
    for y in range(height):
        for x in range(width):
            dist = _pointy_edge_distance(x, y, width, height)
            if dist < 0.0:
                continue
            if dist < stroke:
                op[x, y] = (or_, og, ob, 255)
            elif dist < rim:
                op[x, y] = (fr, fg, fb, 255)
            else:
                r, g, b, a = px[x, y]
                op[x, y] = (r, g, b, 255 if a else 255)
    return out


def extract_hex(hex_map: Image.Image) -> None:
    ## Tileable OPEN/BRUSH/HARD/? stamps from the match-board / hex-map plate.
    ## One face per kind — not a unique full-map painting.
    def box_at(cx: int, cy: int, hx: int, hy: int) -> tuple[int, int, int, int]:
        return (cx - hx, cy - hy, cx + hx, cy + hy)

    ## Legend chips — measured on match-board-canon / hex-map HUD column.
    legend = {
        "hex_open": box_at(76, 180, 40, 36),
        "hex_brush": box_at(76, 276, 40, 36),
        "hex_hard": box_at(76, 364, 40, 36),
        "hex_unknown": box_at(76, 448, 40, 36),
    }
    for name, box in legend.items():
        raw = crop(hex_map, box, f"{name}_legend_raw")
        save_sprite(apply_hex_mask(raw), f"{name}_legend.png")

    ## One tileable board face per kind. Center is the painted hex, pitch is
    ## the canon flat-to-flat gap, so the mask does not swallow the neighbor.
    ## Then flatten the rim so a north cap / neighbor pixel cannot shingle.
    face_colors = {
        "hex_open": (206, 160, 88),
        "hex_brush": (78, 112, 36),
        "hex_hard": (132, 128, 120),
        "hex_unknown": (42, 43, 44),
    }
    for name, center in BOARD_HEX_CENTERS.items():
        face = isolate_board_hex(hex_map, center[0], center[1])
        face = flatten_board_hex(face, face_colors[name])
        save_sprite(face, f"{name}_tile.png")

    ## Clump-only overlays from the same brush / hard faces.
    brush = crop(hex_map, box_at(656, 218, 22, 20), "brush_clump_raw")
    brush = key_near(
        brush,
        [(210, 163, 93), (212, 165, 95), (204, 160, 89), (196, 149, 81)],
        36,
    )
    save_sprite(trim_alpha(brush, 1), "stamp_brush.png")

    rock = crop(hex_map, box_at(796, 299, 22, 20), "rock_pile_raw")
    rock = key_near(
        rock,
        [(118, 115, 108), (146, 141, 137), (163, 160, 153), (107, 106, 104)],
        18,
    )
    save_sprite(trim_alpha(rock, 1), "stamp_rock.png")


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
    hx = load_jpg("match-board-canon.jpg" if (CANON / "match-board-canon.jpg").exists() else "hex-map.jpg")
    op = load_jpg("optic-attack.jpg")
    extract_rifles(teal)
    extract_operatives(teal, ghil)
    extract_hex(hx)
    extract_optic_bits(op)
    contact_preview()
    print("ART_V2_SPRITES", OUT)
    for p in sorted(OUT.glob("*.png")):
        print(f"  {p.name} {Image.open(p).size}")


if __name__ == "__main__":
    main()
