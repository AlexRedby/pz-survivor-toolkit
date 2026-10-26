"""Require real rendered scene receipts and screenshot files for this fixture."""
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
PNG = b'\x89PNG\r\n\x1a\n'


def verify(root, text):
    manifest = json.loads((HERE / 'manifest.json').read_text())
    if manifest['failure_marker'] in text or 'KahluaException' in text:
        raise ValueError('Inventory presentation fixture reported a failure')
    markers = ['[INVENTORY_SCREEN] SETUP nativeItems=15 externalOwners=false',
               '[INVENTORY_SCREEN] SORT count=7 bound=3 tail=4 selection=true anchor=true',
               manifest['completion_marker']]
    markers += ['[INVENTORY_SCREEN] DRAW ' + name + ' details=once bag=icons magazine=icons button=1 nativeTypes=true'
                for name in ('01-clean', '02-vanilla', '03-clean-again')]
    markers += manifest['assertion_markers']
    for marker in markers:
        if text.count(marker) != 1:
            raise ValueError('Missing/duplicate assertion evidence: ' + marker)
    expected = [name.removeprefix('inventory-').removesuffix('.png') for name in manifest['expected_screenshots']]
    if re.findall(r'\[INVENTORY_SCREEN\] SHOT (\S+)', text) != expected:
        raise ValueError('Missing/duplicate/reordered inventory screenshots')
    profiles = re.findall(r'\[INVENTORY_RENDER_PROFILE\] mode=(clean|vanilla) frames=(\d+) units=ms/calls ([^\r\n]+)', text)
    if [row[0] for row in profiles] != ['clean', 'vanilla']:
        raise ValueError('Missing/duplicate/reordered render profile windows')
    render_profiles = {}
    for mode, frames, measurements in profiles:
        frames = int(frames)
        entries = re.findall(r'(\w+)=(\d+)/(\d+)', measurements)
        metrics = {name: {'ms': int(ms), 'calls': int(calls)} for name, ms, calls in entries}
        required = {'normal', 'dragged', 'InventoryCapacity', 'InventoryIndicators',
                    'InventoryResearch', 'InventoryPlanting', 'InventoryRetention'}
        if (frames < 240 or len(metrics) != len(entries) or not required <= metrics.keys()
                or any(metrics[name]['calls'] <= 0 for name in required)
                or metrics['normal']['calls'] != frames or metrics['dragged']['calls'] != frames):
            raise ValueError('Incomplete render profile window: ' + mode)
        render_profiles[mode] = {'frames': frames, 'inclusive_metrics': metrics}
    micro = re.findall(r'\[INVENTORY_MICRO\] family=(\w+) series=(\d+) slot=(\d+) variant=(\w+) ms=(\d+) calls=(\d+) checksum=([\d.eE+-]+)', text)
    expected_jobs = [(family, series, slot, variant) for family, variants in
                     [('research', ['direct', 'context', 'context', 'direct']),
                      ('flat', ['records', 'flat', 'flat', 'records']),
                      ('soa', ['records', 'soa', 'soa', 'records'])]
                     for series in range(1, 7) for slot, variant in enumerate(variants, 1)]
    if [(row[0], int(row[1]), int(row[2]), row[3]) for row in micro] != expected_jobs:
        raise ValueError('Incomplete/reordered paired microbenchmark')
    micro_samples, checksums = [], {}
    for family, series, slot, variant, ms, calls, checksum in micro:
        checksum = float(checksum)
        if int(calls) != 24000 or checksums.setdefault(family, checksum) != checksum:
            raise ValueError('Unequal microbenchmark workload: ' + family)
        micro_samples.append(dict(family=family, series=int(series), slot=int(slot),
                                  variant=variant, ms=int(ms), calls=int(calls), checksum=checksum))
    screenshots = []
    for name in manifest['expected_screenshots']:
        path = Path(root) / 'client1/Screenshots' / name
        if not path.is_file() or path.read_bytes()[:8] != PNG:
            raise ValueError('Missing/invalid screenshot: ' + str(path))
        screenshots.append(str(path))
    return {'screenshots': screenshots, 'render_profiles': render_profiles, 'micro_samples': micro_samples,
            'limits': ['EN single-player with programmatic native UI callbacks; no physical input, Host or pixel-level screenshot verdict.']}
