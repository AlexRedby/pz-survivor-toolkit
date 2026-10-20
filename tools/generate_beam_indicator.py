#!/usr/bin/env python3
"""Build horizontal-ray variants from the installed authored dashboard sprites.

Requires Pillow and NumPy. Warning variants remap only ray columns; native
dimensions, colour, transparent padding, housing and glow stay intact. The
standard rotary faceplate also receives native-sized repositioned legends.
No scale is synthesized from another: every authored size is processed directly.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

# Ray strip, centre, incline and vertical interval in the authored 2x artwork.
PROFILES = {
    'standard': (40, 31, 29, 40, 33, .32, 0, 31),
    'heavy': (60, 48, 12, 24, 18, -.40, 12, 38),
    'sport': (188, 178, 78, 89, 83, -.30, 74, 99),
}
SCALES = ('0.75x', '1x', '1.4x', '2x')


def rotary_panel(dashboard):
    """Native printed legends: OFF left, LOW upper-left, HIGH above the knob.

    Coordinates refer to the original 1490x344 standard faceplate. A blank
    strip at the same height supplies the background beneath the old LOW
    print. Extract the native grey glyph against that background, straighten
    only its ray columns for HIGH, and retain LOW's original sloping rays.
    """
    scale = dashboard.width / 1490
    x0, y0, x1, y1 = [round(n * scale) for n in (162, 220, 196, 246)]
    width, height = x1 - x0, y1 - y0
    source = np.asarray(dashboard.convert('RGBA'))
    donor_x = round(126 * scale)
    background = source[y0:y1, donor_x:donor_x + width].copy()
    printed = source[y0:y1, x0:x1].astype(float)
    base = background.astype(float)
    # Native legend is neutral grey; retain its actual brightness/antialiasing.
    alpha = np.clip((printed[:, :, :3].mean(2) - base[:, :, :3].mean(2))
                    / (255 - base[:, :, :3].mean(2)), 0, 1)
    low = np.full((height, width, 4), 255, dtype=np.uint8)
    low[:, :, 3] = np.rint(alpha * 255).astype(np.uint8)
    high = low.copy()
    rows = np.arange(height)
    for x in range(round(21 * scale), min(width, round(33 * scale))):
        offset = .4 * (x - 26 * scale)
        high[:, x, 3] = np.rint(np.interp(rows + offset, rows, low[:, x, 3], left=0, right=0))
    panel = Image.new('RGBA', (x1, round(266 * scale)))
    panel.paste(Image.fromarray(background), (x0, y0))
    panel.alpha_composite(Image.fromarray(high), (x0, y0))
    panel.alpha_composite(Image.fromarray(low), (x0 - round(42 * scale), y0 + round(18 * scale)))
    return panel


def straighten(image, family):
    width, height, left, right, centre, slope, top, bottom = PROFILES[family]
    sx, sy = image.width / width, image.height / height
    x0, x1 = round(left * sx), round(right * sx)
    source = np.asarray(image.convert('RGBA')).astype(float)
    # Interpolate premultiplied colour, avoiding dark fringes at soft alpha edges.
    pixels = source.copy()
    pixels[:, :, :3] *= pixels[:, :, 3:4] / 255
    changed = pixels.copy()
    rows = np.arange(image.height)
    weight = np.ones(image.height) if family == 'standard' else np.minimum(
        np.clip((rows - top * sy) / (2 * sy), 0, 1),
        np.clip((bottom * sy - rows) / (2 * sy), 0, 1))
    for x in range(x0, x1):
        offset = slope * (x / sx - centre) * sy
        # Keep broad background glow fixed; rectify only the ray signal above it.
        for channel in range(4):
            base = np.zeros(image.height) if family == 'standard' else (
                (x1 - x) * pixels[:, max(0, x0 - 1), channel]
                + (x - x0 + 1) * pixels[:, min(image.width - 1, x1), channel]
            ) / (x1 - x0 + 1)
            signal = pixels[:, x, channel] - base
            shifted = np.interp(rows + offset, rows, signal, left=0, right=0)
            changed[:, x, channel] += (shifted - signal) * weight
    changed[:, :, :3] = np.divide(changed[:, :, :3] * 255, changed[:, :, 3:4],
        out=np.zeros_like(changed[:, :, :3]), where=changed[:, :, 3:4] > 0)
    output = source.copy()
    # Copy untouched pixels byte-for-byte, including RGB behind zero alpha.
    output[:, x0:x1] = changed[:, x0:x1]
    return Image.fromarray(np.uint8(np.clip(np.rint(output), 0, 255)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dashboard-root', type=Path, required=True,
        help='RealisticDashboardAndGauges/42/media/ui/vehicles')
    parser.add_argument('--output', type=Path,
        default=Path(__file__).resolve().parents[1] / 'PZSurvivorToolkit/42/media/ui/PZSurvivorToolkit/beams')
    args = parser.parse_args()
    for family in PROFILES:
        for scale in SCALES:
            source = args.dashboard_root / family / 'dash' / scale / 'warning_light.png'
            image = Image.open(source).convert('RGBA')
            output = args.output / family / scale / 'high.png'
            output.parent.mkdir(parents=True, exist_ok=True)
            high = straighten(image, family)
            high.save(output)
            if family == 'standard':
                # Derived from this scale's actual faceplate, not warning art.
                dashboard = Image.open(source.with_name('dash.png')).convert('RGBA')
                rotary_panel(dashboard).save(output.with_name('light-panel.png'))
            print(f'{family}/{scale}: {image.width}x{image.height}')


if __name__ == '__main__':
    main()
