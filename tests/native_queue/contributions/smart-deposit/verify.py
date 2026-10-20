"""Require exact native drag/transfer receipts in both inventory modes."""
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
PNG = b'\x89PNG\r\n\x1a\n'


def verify(root, text):
    manifest = json.loads((HERE / 'manifest.json').read_text())
    if manifest['failure_marker'] in text or 'KahluaException' in text:
        raise ValueError('Smart Deposit fixture reported a failure')
    markers = ['[SMART_DEPOSIT] SETUP SP native=true storage=3', manifest['completion_marker']]
    for mode in ('clean', 'vanilla'):
        markers += [
            f'[SMART_DEPOSIT] PREVIEW {mode} accepted=3 rejected=1 pane=true page=true exact=true category=true fallback=true',
            f'[SMART_DEPOSIT] QUEUED {mode} nativeActions=3 rejected=false durationUnchanged=true',
            f'[SMART_DEPOSIT] EFFECT {mode} moved=3 retained=1 unique=true seeds=true capacity=true',
            f'[SMART_DEPOSIT] FULL {mode} accepted=0 rejected=4 pane=false page=false nativeActions=0',
        ]
    for marker in markers:
        if text.count(marker) != 1:
            raise ValueError('Missing/duplicate native evidence: ' + marker)
    if re.findall(r'\[SMART_DEPOSIT\] SHOT (\S+)', text) != manifest['expected_screenshots']:
        raise ValueError('Missing/duplicate/reordered Smart Deposit screenshots')
    screenshots = []
    for name in manifest['expected_screenshots']:
        path = Path(root) / 'client1/Screenshots' / name
        if not path.is_file() or path.read_bytes()[:8] != PNG:
            raise ValueError('Missing/invalid screenshot: ' + str(path))
        screenshots.append(str(path))
    return {'screenshots': screenshots, 'limits': [
        'EN SP with programmatic native drag/drop callbacks and native transfer actions; no physical input or Host coverage.',
        'Screenshots require visual inspection; callback receipts do not establish pixel-level feedback quality.',
    ]}
