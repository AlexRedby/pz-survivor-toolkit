"""Check measured draw-palette contacts, not the requested animation/IK goals."""
import math
import re
from queue_checks.vehicle_pose_samples import FULL, NUMBER


def span(points):
    return max((math.dist(a,b) for a in points for b in points),default=0)


def analyze(text):
    issues,evidence=[],{}
    for case in FULL:
        rows=[]
        for line in re.findall(r'\[VEHICLE_POSE\] BONES '+case+r' ([^\n]+)',text):
            t=re.search(r'phase=('+NUMBER+')',line)
            if not t: continue
            bones={m[1]:tuple(map(float,m.groups()[1:])) for m in re.finditer(r'(Bip01_\w+)=('+NUMBER+'),('+NUMBER+'),('+NUMBER+')',line)}
            skin=re.search(r'skins=(\d+) skinError=('+NUMBER+')',line)
            if not skin: continue
            rows.append(dict(phase=float(t[1]),bones=bones,skins=int(skin[1]),skin_error=float(skin[2])))
        # Duplicate GPU presentations do not increase phase coverage.
        rows=list({r['phase']:r for r in rows}.values())
        entering=case.startswith('enter-')
        leading='R' if case.endswith('driver') else 'L'
        trailing='L' if leading=='R' else 'R'
        def window(a,b): return [r for r in rows if a<=r['phase']<=b]
        def foot(r,side): return r['bones']['Bip01_'+side+'_Foot']
        try:
            if len(rows)<8 or min(r['phase'] for r in rows)>.2 or max(r['phase'] for r in rows)<.85:
                raise ValueError('incomplete post-IK phase coverage')
            all_values=[v for r in rows for p in r['bones'].values() for v in p]+[r['skin_error'] for r in rows]
            if not all(math.isfinite(v) for v in all_values): raise ValueError('nonfinite post-IK pose')
            if min(r['skins'] for r in rows)<2 or max(r['skin_error'] for r in rows)>2e-5:
                raise ValueError('body/clothing palette disagreement')
            support=window(.13,.48) if entering else window(.13,.39)
            planted=window(.39,.64) if entering else window(.43,.96)
            # Include the leading foot's landing (.36 entry/.40 exit), so the
            # observed flight is bounded by its pre-action baseline and contact.
            swing=window(.1,.4)
            if min(len(support),len(planted),len(swing))<3: raise ValueError('incomplete contact windows')
            support_drift=span([foot(r,trailing) for r in support])
            lead_drift=span([foot(r,leading) for r in planted])
            if support_drift>.002 or lead_drift>.002: raise ValueError('planted ankle slides')
            baseline=re.search(r'\[VEHICLE_POSE\] CONTACT_BASE '+case+r' LY=('+NUMBER+r') RY=('+NUMBER+r')',text)
            if baseline is None: raise ValueError('missing pre-action foot baseline')
            takeoff=float(baseline[1 if leading=='L' else 2])
            land=foot(min(planted,key=lambda r:r['phase']),leading)[1]
            lead_lift=max(foot(r,leading)[1] for r in swing)-max(takeoff,land)
            if lead_lift<.01: raise ValueError('no measured lead-foot swing clearance')
            # A fixed support plus an advancing pelvis is the observed transfer of weight.
            weight=window(.39,.6) if entering else window(.43,.68)
            if len(weight)<3: raise ValueError('incomplete weight transfer')
            weight=sorted(weight,key=lambda r:r['phase'])
            pelvis_travel=math.dist(weight[0]['bones']['Bip01_Pelvis'],weight[-1]['bones']['Bip01_Pelvis'])
            if pelvis_travel<.03: raise ValueError('no pelvis transfer over the planted foot')
            length_error=0
            for side in ('L','R'):
                for upper,lower in (('Thigh','Calf'),('Calf','Foot')):
                    lengths=[math.dist(r['bones']['Bip01_'+side+'_'+upper],r['bones']['Bip01_'+side+'_'+lower]) for r in rows]
                    length_error=max(length_error,max(lengths)-min(lengths))
            if length_error>.001: raise ValueError('rendered leg length changed')
            evidence[case]=dict(samples=len(rows),leading=leading,support_drift=support_drift,
                               planted_lead_drift=lead_drift,lead_swing_clearance=lead_lift,
                               pelvis_weight_transfer=pelvis_travel,leg_length_span=length_error,
                               skins_min=min(r['skins'] for r in rows),skin_error=max(r['skin_error'] for r in rows))
        except (KeyError,ValueError) as error:
            issues.append(case+': '+str(error))
    return issues,evidence
