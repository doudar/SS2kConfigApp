#!/usr/bin/env python3
"""Generate store-ready marketing screenshots from authentic app captures."""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "store_assets"
BACKGROUND = OUT / "source" / "generated_background.png"
APP_ICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"


def first_available_font(*candidates: str) -> str:
    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate
    raise FileNotFoundError(f"No supported font found in: {', '.join(candidates)}")


FONT_REGULAR = first_available_font(
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "C:/Windows/Fonts/arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)
FONT_BOLD = first_available_font(
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
)


@dataclass(frozen=True)
class Story:
    slug: str
    source: Path
    eyebrow: str
    headline: str
    detail: str
    accent: tuple[int, int, int]
    alt: str


STORIES = (
    Story(
        "workout",
        ROOT / "assets/Workout_Screen.png",
        "STRUCTURED WORKOUTS",
        "Own every interval.",
        "Live targets and training metrics keep every effort on track.",
        (239, 76, 67),
        "SmartSpin2k workout screen with interval graph, workout summary, and live FTP target.",
    ),
    Story(
        "settings",
        ROOT / "assets/settingsScreen.png",
        "SIMPLE SETUP",
        "Tune every detail.",
        "Settings, sensors, networking, and firmware controls in one place.",
        (76, 159, 94),
        "SmartSpin2k settings screen showing basic, Bluetooth, network, and advanced categories.",
    ),
    Story(
        "shifting",
        ROOT / "assets/shiftscreen.png",
        "VIRTUAL SHIFTING",
        "Shift your way.",
        "Responsive on-screen gearing puts control within easy reach.",
        (65, 151, 230),
        "SmartSpin2k virtual shifter with power, cadence, gear, and up and down controls.",
    ),
    Story(
        "power-curve",
        ROOT / "assets/resistanceChart.png",
        "RESISTANCE INSIGHT",
        "See the power curve.",
        "Understand resistance across cadence, gearing, and output.",
        (245, 166, 35),
        "SmartSpin2k resistance chart with multiple cadence curves and live power metrics.",
    ),
)


PLATFORMS = {
    "ios_iphone": (1284, 2778),
    "ios_ipad": (2752, 2064),
    "macos": (2880, 1800),
    "android_phone": (1080, 1920),
}

PHONE_PLATFORMS = {"ios_iphone", "android_phone"}


def flutter_source(platform: str, story: Story) -> Path:
    """Prefer the real Flutter render captured for this exact viewport."""
    captured = OUT / "source" / "flutter" / platform / f"{story.slug}.png"
    return captured if captured.exists() else story.source


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size=size)


def cover_background(size: tuple[int, int], focus: float = 0.5) -> Image.Image:
    source = Image.open(BACKGROUND).convert("RGB")
    width, height = size
    source_ratio = source.width / source.height
    target_ratio = width / height
    if source_ratio > target_ratio:
        crop_width = int(source.height * target_ratio)
        left = int((source.width - crop_width) * focus)
        source = source.crop((left, 0, left + crop_width, source.height))
    else:
        crop_height = int(source.width / target_ratio)
        top = max(0, (source.height - crop_height) // 2)
        source = source.crop((0, top, source.width, top + crop_height))
    source = source.resize(size, Image.Resampling.LANCZOS)
    source = ImageEnhance.Brightness(source).enhance(0.68)
    return source


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def fit_ui(source_path: Path, max_size: tuple[int, int]) -> Image.Image:
    ui = Image.open(source_path).convert("RGB")
    scale = min(max_size[0] / ui.width, max_size[1] / ui.height)
    target = (max(1, int(ui.width * scale)), max(1, int(ui.height * scale)))
    return ui.resize(target, Image.Resampling.LANCZOS)


def add_ui_card(canvas: Image.Image, ui: Image.Image, xy: tuple[int, int], radius: int) -> None:
    x, y = xy
    shadow_pad = max(24, radius // 2)
    shadow = Image.new("RGBA", (ui.width + shadow_pad * 2, ui.height + shadow_pad * 2), (0, 0, 0, 0))
    shadow_mask = rounded_mask(ui.size, radius).filter(ImageFilter.GaussianBlur(max(18, radius // 2)))
    shadow_alpha = Image.new("L", shadow.size, 0)
    shadow_alpha.paste(shadow_mask, (shadow_pad, shadow_pad))
    shadow.putalpha(shadow_alpha.point(lambda p: int(p * 0.7)))
    canvas.paste(shadow, (x - shadow_pad, y - shadow_pad), shadow)

    mask = rounded_mask(ui.size, radius)
    canvas.paste(ui, (x, y), mask)
    border = ImageDraw.Draw(canvas)
    border.rounded_rectangle(
        (x, y, x + ui.width - 1, y + ui.height - 1),
        radius=radius,
        outline=(255, 255, 255),
        width=max(2, radius // 10),
    )


def draw_brand(draw: ImageDraw.ImageDraw, x: int, y: int, scale: float) -> int:
    dot = int(16 * scale)
    draw.ellipse((x, y + int(7 * scale), x + dot, y + int(7 * scale) + dot), fill=(235, 40, 48))
    draw.text((x + int(30 * scale), y), "SmartSpin2K", font=font(int(34 * scale), True), fill="white")
    return y + int(58 * scale)


def wrap_text(
    draw: ImageDraw.ImageDraw,
    value: str,
    text_font: ImageFont.FreeTypeFont,
    max_width: int,
) -> list[str]:
    lines: list[str] = []
    line = ""
    for word in value.split():
        candidate = f"{line} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=text_font)[2] > max_width and line:
            lines.append(line)
            line = word
        else:
            line = candidate
    if line:
        lines.append(line)
    return lines


def render_portrait(platform: str, size: tuple[int, int], story: Story, index: int) -> Image.Image:
    width, height = size
    canvas = cover_background(size, focus=0.45 + index * 0.025)
    draw = ImageDraw.Draw(canvas)
    scale = width / 1080

    # A top-to-bottom veil separates the concise store message from the real UI.
    panel_h = int(height * 0.46)
    for y in range(panel_h):
        alpha = int(220 * (1 - (y / max(panel_h - 1, 1)) ** 2))
        draw.line((0, y, width, y), fill=(4, 6, 9, alpha))

    left = int(72 * scale)
    draw_brand(draw, left, int(68 * scale), scale)

    eyebrow_y = int(200 * scale)
    eyebrow_font = font(int(21 * scale), True)
    eyebrow_w = draw.textbbox((0, 0), story.eyebrow, font=eyebrow_font)[2] + int(42 * scale)
    draw.rounded_rectangle(
        (left, eyebrow_y, left + eyebrow_w, eyebrow_y + int(54 * scale)),
        radius=int(27 * scale),
        fill=story.accent,
    )
    draw.text(
        (left + int(21 * scale), eyebrow_y + int(13 * scale)),
        story.eyebrow,
        font=eyebrow_font,
        fill="white",
    )

    headline_y = eyebrow_y + int(92 * scale)
    headline_font = font(int(76 * scale), True)
    headline_lines = wrap_text(draw, story.headline, headline_font, int(width * 0.86))
    headline_step = int(86 * scale)
    for offset, text_line in enumerate(headline_lines):
        draw.text(
            (left, headline_y + offset * headline_step),
            text_line,
            font=headline_font,
            fill="white",
        )

    detail_y = headline_y + len(headline_lines) * headline_step + int(34 * scale)
    detail_font = font(int(30 * scale))
    detail_lines = wrap_text(draw, story.detail, detail_font, int(width * 0.84))
    for offset, text_line in enumerate(detail_lines):
        draw.text(
            (left, detail_y + offset * int(43 * scale)),
            text_line,
            font=detail_font,
            fill=(211, 218, 225),
        )

    ui = fit_ui(
        flutter_source(platform, story),
        (int(width * 0.72), int(height * 0.72)),
    )
    ui_x = (width - ui.width) // 2
    ui_y = height - ui.height - int(86 * scale)
    add_ui_card(canvas, ui, (ui_x, ui_y), max(24, int(38 * scale)))

    draw.rounded_rectangle(
        (left, height - int(55 * scale), left + int(150 * scale), height - int(43 * scale)),
        radius=int(6 * scale),
        fill=story.accent,
    )
    return canvas.convert("RGB")


def render_landscape(platform: str, size: tuple[int, int], story: Story, index: int) -> Image.Image:
    width, height = size
    canvas = cover_background(size, focus=0.44 + index * 0.03)
    draw = ImageDraw.Draw(canvas)
    scale = width / 1920

    # A subtle dark panel ensures the compact marketing copy remains readable.
    panel_w = int(width * (0.355 if platform != "ios_ipad" else 0.40))
    for x in range(panel_w):
        alpha = int(206 * (1 - (x / max(panel_w - 1, 1)) ** 2))
        draw.line((x, 0, x, height), fill=(4, 6, 9, alpha))

    left = int(92 * scale)
    top = int(72 * scale)
    draw_brand(draw, left, top, scale)

    eyebrow_y = int(235 * scale)
    draw.rounded_rectangle(
        (left, eyebrow_y, left + int(285 * scale), eyebrow_y + int(54 * scale)),
        radius=int(27 * scale),
        fill=story.accent,
    )
    draw.text(
        (left + int(20 * scale), eyebrow_y + int(12 * scale)),
        story.eyebrow,
        font=font(int(22 * scale), True),
        fill="white",
    )

    headline_y = eyebrow_y + int(92 * scale)
    max_headline = int(520 * scale)
    headline_font = font(int(78 * scale), True)
    # The supplied headlines fit on one or two clean lines at every target size.
    words = story.headline.split()
    lines: list[str] = []
    line = ""
    for word in words:
        candidate = f"{line} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=headline_font)[2] > max_headline and line:
            lines.append(line)
            line = word
        else:
            line = candidate
    lines.append(line)
    for offset, text_line in enumerate(lines):
        draw.text((left, headline_y + offset * int(90 * scale)), text_line, font=headline_font, fill="white")

    detail_y = headline_y + len(lines) * int(94 * scale) + int(28 * scale)
    detail_font = font(int(29 * scale))
    detail_width = int(520 * scale)
    detail_words = story.detail.split()
    detail_lines: list[str] = []
    line = ""
    for word in detail_words:
        candidate = f"{line} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=detail_font)[2] > detail_width and line:
            detail_lines.append(line)
            line = word
        else:
            line = candidate
    detail_lines.append(line)
    for offset, text_line in enumerate(detail_lines):
        draw.text(
            (left, detail_y + offset * int(42 * scale)),
            text_line,
            font=detail_font,
            fill=(211, 218, 225),
        )

    if platform == "ios_ipad":
        max_ui = (int(width * 0.78), int(height * 0.62))
        ui = fit_ui(flutter_source(platform, story), max_ui)
        ui_x = width - ui.width - int(95 * scale)
        ui_y = height - ui.height - int(95 * scale)
    else:
        max_ui = (int(width * 0.63), int(height * 0.83))
        ui = fit_ui(flutter_source(platform, story), max_ui)
        ui_x = width - ui.width - int(46 * scale)
        ui_y = (height - ui.height) // 2

    add_ui_card(canvas, ui, (ui_x, ui_y), max(24, int(30 * scale)))

    # Accent rule ties each story to the source UI without adding more copy.
    draw.rounded_rectangle(
        (left, height - int(88 * scale), left + int(120 * scale), height - int(76 * scale)),
        radius=int(6 * scale),
        fill=story.accent,
    )
    return canvas.convert("RGB")


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(f"{path.suffix}.tmp")
    image.save(temporary_path, "PNG", optimize=True)
    temporary_path.replace(path)


def feature_graphic() -> Image.Image:
    size = (1024, 500)
    canvas = cover_background(size, focus=0.52)
    draw = ImageDraw.Draw(canvas)

    android_workout = OUT / "source" / "flutter" / "android_phone" / "workout.png"
    ui = fit_ui(
        android_workout if android_workout.exists() else ROOT / "assets/Workout_Screen.png",
        (340, 380),
    )
    # Keep the UI near the center so Play's dynamic crops retain the focal point.
    add_ui_card(canvas, ui, (size[0] - ui.width - 72, (size[1] - ui.height) // 2), 18)

    draw.text((72, 105), "SmartSpin2K", font=font(68, True), fill="white")
    draw.text((74, 193), "Smart control", font=font(42, True), fill=(239, 76, 67))
    draw.text((74, 245), "for every ride.", font=font(42, True), fill="white")
    draw.rounded_rectangle((74, 330, 236, 340), radius=5, fill=(239, 76, 67))
    return canvas.convert("RGB")


def play_icon() -> Image.Image:
    icon = Image.open(APP_ICON).convert("RGBA")
    icon = ImageOps.fit(icon, (512, 512), method=Image.Resampling.LANCZOS)
    return icon


def contact_sheet(paths: list[Path]) -> None:
    thumbs: list[tuple[Path, Image.Image]] = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        image.thumbnail((480, 300), Image.Resampling.LANCZOS)
        thumbs.append((path, image.copy()))

    cell_w, cell_h = 520, 360
    columns = 4
    rows = (len(thumbs) + columns - 1) // columns
    sheet = Image.new("RGB", (cell_w * columns, cell_h * rows), (20, 23, 27))
    draw = ImageDraw.Draw(sheet)
    label_font = font(19, True)
    for idx, (path, image) in enumerate(thumbs):
        x = (idx % columns) * cell_w + 20
        y = (idx // columns) * cell_h + 20
        sheet.paste(image, (x, y))
        draw.text((x, y + 310), path.relative_to(OUT).as_posix(), font=label_font, fill="white")
    save_png(sheet, OUT / "preview-contact-sheet.png")


def main() -> None:
    outputs: list[Path] = []
    manifest_rows: list[dict[str, str]] = []

    for platform, size in PLATFORMS.items():
        for index, story in enumerate(STORIES, start=1):
            image = (
                render_portrait(platform, size, story, index)
                if platform in PHONE_PLATFORMS
                else render_landscape(platform, size, story, index)
            )
            path = OUT / platform / f"{index:02d}-{story.slug}.png"
            save_png(image, path)
            outputs.append(path)
            manifest_rows.append(
                {
                    "platform": platform,
                    "order": str(index),
                    "file": path.relative_to(OUT).as_posix(),
                    "dimensions": f"{size[0]}x{size[1]}",
                    "alt_text": story.alt,
                }
            )

    feature_path = OUT / "android" / "feature-graphic-1024x500.png"
    save_png(feature_graphic(), feature_path)
    outputs.append(feature_path)
    manifest_rows.append(
        {
            "platform": "android",
            "order": "feature",
            "file": feature_path.relative_to(OUT).as_posix(),
            "dimensions": "1024x500",
            "alt_text": "SmartSpin2K workout dashboard over an energetic power-curve background.",
        }
    )

    icon_path = OUT / "android" / "app-icon-512.png"
    save_png(play_icon(), icon_path)
    outputs.append(icon_path)
    manifest_rows.append(
        {
            "platform": "android",
            "order": "icon",
            "file": icon_path.relative_to(OUT).as_posix(),
            "dimensions": "512x512",
            "alt_text": "SmartSpin2K trainer controller hardware.",
        }
    )

    manifest_path = OUT / "manifest.csv"
    temporary_manifest_path = manifest_path.with_suffix(".csv.tmp")
    with temporary_manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=("platform", "order", "file", "dimensions", "alt_text"),
        )
        writer.writeheader()
        writer.writerows(manifest_rows)
    temporary_manifest_path.replace(manifest_path)

    contact_sheet([path for path in outputs if "app-icon" not in path.name])
    print(f"Generated {len(outputs)} store assets plus manifest and contact sheet in {OUT}")


if __name__ == "__main__":
    main()
