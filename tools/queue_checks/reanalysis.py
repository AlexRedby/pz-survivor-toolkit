"""Write a new analysis of sealed observations without changing the native run."""
from pathlib import Path
from contextlib import nullcontext

from . import provenance, report, snapshot_storage


@snapshot_storage.with_inputs
def write(root, output, catalog, control=None):
    with snapshot_storage.available(control) if control is not None else nullcontext():
        return _write(root, output, catalog, control)


def _write(root, output, catalog, control=None):
    root, output = Path(root).resolve(), Path(output).resolve()
    control = Path(control).resolve() if control else None
    if output.exists():
        raise FileExistsError('Fresh reanalysis output directory required')
    if any(output.is_relative_to(run) for run in (root, control) if run is not None):
        raise ValueError('Reanalysis output must be outside the original and control runs')
    baseline = report.build_report(control, catalog, reanalysis=True) if control else None
    value = report.build_report(root, catalog, baseline, reanalysis=True)
    if baseline is not None:
        value['comparison']['control_run'] = str(control)
        value['comparison']['control_reanalysis'] = baseline['provenance']['reanalysis']
        if provenance.reanalysis_provenance(control) != baseline['provenance']['reanalysis']:
            raise ValueError('Control changed during reanalysis')
    output.mkdir(parents=True)
    report.write_json(output / 'report.json', value)
    (output / 'report.txt').write_text(report.summary(value), encoding='utf-8')
    report.write_json(output / 'coverage.json', report.matrix(catalog, [value]))
    if baseline is not None:
        report.write_json(output / 'control-report.json', baseline)
    return value
