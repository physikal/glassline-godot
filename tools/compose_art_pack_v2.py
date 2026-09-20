#!/usr/bin/env python3
"""Compose taste-gate still 06 and canon side-by-side contact sheets."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
UX = ROOT / "artifacts" / "ux"
CANON = ROOT / "assets" / "canon"
UX.mkdir(parents=True, exist_ok=True)


def load(path: Path, size: tuple[int, int] | None = None) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    if size:
        img = img.resize(size, Image.Resampling.NEAREST)
    return img


def label_bar(text: str, width: int, fill=(26, 20, 16, 255)) -> Image.Image:
    bar = Image.new("RGBA", (width, 28), fill)
    d = ImageDraw.Draw(bar)
    d.text((10, 7), text, fill=(244, 239, 228, 255))
    return bar


def side_by_side(left: Image.Image, right: Image.Image, left_cap: str, right_cap: str, out: Path) -> None:
    w = 640
    h = 360
    l = left.resize((w, h), Image.Resampling.NEAREST)
    r = right.resize((w, h), Image.Resampling.NEAREST)
    sheet = Image.new("RGBA", (w * 2, h + 28), (20, 12, 8, 255))
    sheet.paste(label_bar(left_cap, w), (0, 0))
    sheet.paste(label_bar(right_cap, w), (w, 0))
    sheet.paste(l, (0, 28))
    sheet.paste(r, (w, 28))
    sheet.save(out)
    print("SBS", out)


def compose_ui_chips() -> None:
    cells = [
        (UX / "02_dynamic_rack.png", "MARKS ★"),
        (UX / "coach_tips_first_match.png", "COACH"),
        (UX / "queue_finding_rival.png", "QUEUE"),
        (UX / "end_summary_kill.png", "END"),
    ]
    tile_w, tile_h = 640, 360
    sheet = Image.new("RGBA", (tile_w * 2, tile_h * 2 + 56), (20, 12, 8, 255))
    for i, (path, cap) in enumerate(cells):
        if not path.exists():
            print("MISSING", path)
            continue
        img = load(path, (tile_w, tile_h))
        x = (i % 2) * tile_w
        y = (i // 2) * (tile_h + 28)
        sheet.paste(label_bar(cap, tile_w), (x, y))
        sheet.paste(img, (x, y + 28))
    out = UX / "06_ui_chips_marks_coach_queue_end.png"
    sheet.save(out)
    print("CHIPS", out)


def cream_card_box(img: Image.Image) -> tuple[int, int, int, int] | None:
    """Bounding box of the cream paper-doll card in a match still."""
    px = img.load()
    w, h = img.size
    xs: list[int] = []
    ys: list[int] = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y][:3]
            if r > 220 and 190 < g < 240 and 150 < b < 220 and r > g > b:
                xs.append(x)
                ys.append(y)
    if len(xs) < 80:
        return None
    return (max(0, min(xs) - 8), max(0, min(ys) - 8), min(w, max(xs) + 8), min(h, max(ys) + 8))


def compose_doll_sbs() -> None:
    live_path = UX / "04_operative_exposure_doll.png"
    canon_path = CANON / "lobby-canon.jpg"
    if not live_path.exists() or not canon_path.exists():
        print("SKIP side_by_side_exposure_doll.png")
        return
    live = load(live_path)
    box = cream_card_box(live)
    if box is None:
        box = (340, 200, 780, 620)
    doll = live.crop(box)
    canon = load(canon_path).crop((536, 176, 768, 560))
    side_by_side(doll, canon, "LIVE end-turn paper-doll", "CANON lobby-canon operative", UX / "side_by_side_exposure_doll.png")


def main() -> None:
    compose_ui_chips()
    compose_doll_sbs()
    pairs = [
        (
            UX / "02_dynamic_rack.png",
            CANON / "lobby-canon.jpg",
            "LIVE hideout / rack",
            "CANON lobby-canon",
            UX / "side_by_side_hideout.png",
        ),
        (
            UX / "03_hex_open_brush_hard_unknown.png",
            CANON / "hex-map.jpg",
            "LIVE hex stamps",
            "CANON hex-map",
            UX / "side_by_side_hex.png",
        ),
        (
            UX / "05_attack_optic_fieldbolt.png",
            CANON / "optic-attack.jpg",
            "LIVE Attack optic",
            "CANON optic-attack",
            UX / "side_by_side_optic.png",
        ),
        (
            UX / "ghillie_hideout.png",
            CANON / "lobby-ghillie.jpg",
            "LIVE ghillie hideout",
            "CANON lobby-ghillie",
            UX / "side_by_side_ghillie.png",
        ),
    ]
    for live, canon, lc, rc, out in pairs:
        if live.exists() and canon.exists():
            side_by_side(load(live), load(canon), lc, rc, out)
        else:
            print("SKIP", out.name, "missing", live.exists(), canon.exists())


if __name__ == "__main__":
    main()
