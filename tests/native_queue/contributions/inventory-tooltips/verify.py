"""Require native tooltip receipts and screenshot artifacts; pixels need review."""
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
PNG = b'\x89PNG\r\n\x1a\n'


def verify(root, text):
    manifest = json.loads((HERE / 'manifest.json').read_text())
    if manifest['failure_marker'] in text or 'KahluaException' in text:
        raise ValueError('Inventory tooltip fixture reported a failure')
    for marker in manifest['assertion_markers'] + [manifest['completion_marker']]:
        if text.count(marker) != 1:
            raise ValueError('Missing/duplicate native evidence: ' + marker)
    media = re.findall(r'\[INVENTORY_TOOLTIP\] MEDIA id=(\S+) skills=(\d+) recipes=(\d+) bothAvailable=(true|false)', text)
    if len(media) != 1 or int(media[0][1]) < 1:
        raise ValueError('Missing/duplicate native skill-media selection evidence')
    if media[0][3] == 'true' and int(media[0][2]) < 1:
        raise ValueError('Available native skill-and-recipe media was not selected')
    if re.findall(r'\[INVENTORY_TOOLTIP\] SHOT (\S+)', text) != manifest['expected_screenshots']:
        raise ValueError('Missing/duplicate/reordered inventory tooltip screenshots')
    screenshots = []
    for name in manifest['expected_screenshots']:
        path = Path(root) / 'client1/Screenshots' / name
        if not path.is_file() or path.read_bytes()[:8] != PNG:
            raise ValueError('Missing/invalid screenshot: ' + str(path))
        screenshots.append(str(path))
    return {'screenshots': screenshots, 'limits': [
        'EN SP with native items/tooltips and programmatic windows; no physical input or Host coverage.',
        'Screenshots require visual inspection; layout receipts do not establish pixel-level appearance.',
    ] + ([] if int(media[0][2]) else ['Native selected media has skills only; no combined skill/recipe tape was available.'])}
