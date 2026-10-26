"""Whole-transition evidence: a single seated sample cannot certify animation."""
import math
import re

FULL = ('enter-driver', 'exit-driver', 'enter-passenger', 'exit-passenger')
NUMBER = r'[-+0-9.Ee]+'


def analyze(text, baseline=False):
    issues, evidence = [], {}
    for case in FULL:
        rows = re.findall(r'\[VEHICLE_POSE\] SAMPLE ' + case + r' active ([^\n]+)', text)
        phases, heights, times = [], [], []
        for row in rows:
            head = re.search(r'Bip01_Head=(' + NUMBER + r'),(' + NUMBER + r'),(' + NUMBER + r')', row)
            tracks = re.findall(r'track=([^, ]+),(' + NUMBER + r'),(' + NUMBER + r'),false', row)
            live = [(name, float(weight), float(phase)) for name, weight, phase in tracks if float(weight) >= .9]
            if head and len(live) == 1:
                name, weight, phase = live[0]
                if name == 'Bob_IdleDriving' and not baseline:
                    issues.append(case + ': static driving pose replaced the transition')
                phases.append(phase); heights.append(float(head[2])); times.append(int(re.search(r'ms=(\d+)', row)[1]))
        render = re.findall(r'\[VEHICLE_POSE\] RENDER ' + case + r' ms=(\d+) [^\n]*inVehicle=true local=('
                            + NUMBER + r'),(' + NUMBER + r'),(' + NUMBER + r')', text)
        coords = [tuple(map(float, point[1:])) for point in render
                  if times and min(times)-50 <= int(point[0]) <= max(times)+50]
        finite = all(math.isfinite(value) for value in phases + heights + [v for p in coords for v in p])
        span = max(heights)-min(heights) if heights else 0
        travel = max((math.hypot(a[0]-b[0], a[2]-b[2]) for a in coords for b in coords), default=0)
        distinct = len(set(coords))
        evidence[case] = dict(samples=len(phases), phase_min=min(phases, default=None),
                              phase_max=max(phases, default=None), head_height_span=span,
                              rendered_samples=len(coords), rendered_positions=distinct, rendered_horizontal_travel=travel)
        if (not finite or len(set(phases)) < 5 or min(phases, default=1) > .2
                or max(phases, default=0) < .8):
            issues.append(case + ': incomplete active transition sampling')
        if not baseline and (span < .1 or len(coords) < 5 or distinct < 5 or travel < .2):
            issues.append(case + ': missing standing/seated motion or rendered doorway transfer')
        for phase in ('before', 'after', 'settled'):
            if not re.search(r'\[VEHICLE_POSE\] SAMPLE ' + case + ' ' + phase + r' ms=\d+', text):
                issues.append(case + ': missing ' + phase + ' boundary')
    return issues, evidence
