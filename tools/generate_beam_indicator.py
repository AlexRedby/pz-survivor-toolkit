#!/usr/bin/env python3
"""Build horizontal-ray variants from the installed authored dashboard sprites.

Requires Pillow and NumPy. Only ray columns are remapped; native dimensions,
colour, transparent padding, lamp housing and surrounding glow stay intact.
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
                # Neutral faceplate label; the runtime tints this soft alpha.
                mark = Image.new('RGBA', high.size, (255, 255, 255, 0))
                mark.putalpha(high.getchannel('A'))
                mark.save(output.with_name('high-mark.png'))
            print(f'{family}/{scale}: {image.width}x{image.height}')


if __name__ == '__main__':
    main()
