"""Saved evidence and real CapFrameX 1.9.1.5 schemas; no game or Windows needed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tests/optimizer_trial/TrialReadiness.ps1'
PWSH = shutil.which('pwsh')


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class TrialReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz-readiness-')
        self.root = Path(self.temp.name)
        self.options = self.root / 'options.ini'
        self.options.write_text('width=2560\nheight=1440\nvsync=false\nframeRate=144\n')
        self.config = self.root / 'AppSettings.json'
        self.config.write_text(json.dumps({'UseSensorLogging': True}))
        self.recording = self.root / 'capture.json'

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, body):
        harness = self.root / 'fixture.ps1'
        harness.write_text("""
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. $env:PZ_READINESS_SCRIPT
$client=[pscustomobject]@{Version='1.9.1.5';ConfigPath=$env:PZ_CONFIG}
""" + body + '\n$result | ConvertTo-Json -Depth 20 -Compress\n')
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness)],
                                env=dict(os.environ, PZ_READINESS_SCRIPT=str(SCRIPT),
                                         PZ_CONFIG=str(self.config), PZ_OPTIONS=str(self.options),
                                         PZ_RECORDING=str(self.recording)),
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def readiness(self):
        return self.invoke('$result=Get-TrialCaptureReadiness $client $env:PZ_OPTIONS')

    def recorded(self, runs):
        self.recording.write_text(json.dumps({'Info': {'ProcessName': 'java.exe'}, 'Runs': runs}))
        return self.invoke('$result=Get-TrialRecordedSensors $env:PZ_RECORDING')

    def test_saved_config_is_advisory_boolean_false_is_preserved(self):
        self.config.write_text(json.dumps({'UseSensorLogging': False}))
        (self.root / 'SensorEntryConfiguration.json').write_text(json.dumps({
            '/nvidiagpu/0/load/0': True, '/intelcpu/0/temperature/0': False}))
        result = self.readiness()
        self.assertEqual(result['gameOptions']['targetStatus'], 'Matches')
        cx = result['capFrameX']
        self.assertEqual(cx['savedSensorLoggingStatus'], 'Disabled')
        self.assertIs(cx['savedUseSensorLogging'], False)
        self.assertEqual(cx['liveSensorLoggingStatus'], 'Unknown')
        selection = cx['selectionFiles'][0]
        self.assertEqual(selection['selected'], ['/nvidiagpu/0/load/0'])
        self.assertEqual(selection['disabled'], ['/intelcpu/0/temperature/0'])
        self.assertTrue(any('CapFrameX' in text and 'check' in text for text in result['summary']))

    def test_missing_config_does_not_claim_default_or_block(self):
        self.config.unlink()
        result = self.readiness()
        self.assertEqual(result['capFrameX']['savedSensorLoggingStatus'], 'Unknown')
        self.assertIsNone(result['capFrameX']['savedUseSensorLogging'])
        self.assertEqual(result['gameOptions']['targetStatus'], 'Matches')

    def test_unknown_config_path_does_not_read_another_installation(self):
        result = self.invoke('$client.ConfigPath=$null; $result=Get-TrialCaptureReadiness $client $env:PZ_OPTIONS')
        self.assertEqual(result['capFrameX']['configStatus'], 'Unknown')
        self.assertEqual(result['capFrameX']['selectionFiles'], [])

    def test_malformed_and_nonboolean_source_metadata_remains_unknown(self):
        for value in ('{bad', '[]', 'null', '{"UseSensorLogging":"false"}'):
            with self.subTest(config=value):
                self.config.write_text(value)
                result = self.readiness()
                self.assertEqual(result['capFrameX']['savedSensorLoggingStatus'], 'Unknown')
                self.assertIsNone(result['capFrameX']['savedUseSensorLogging'])

    def test_selection_nonboolean_false_string_is_not_enabled(self):
        (self.root / 'SensorEntryConfiguration.json').write_text(json.dumps({'gpu/load/0': 'false'}))
        result = self.readiness()['capFrameX']['selectionFiles'][0]
        self.assertEqual(result['status'], 'Unknown')
        self.assertEqual(result['selected'], [])
        self.assertEqual(result['invalidKeys'], ['gpu/load/0'])

    def test_saved_60_cap_is_observed_without_mismatch_or_mutation(self):
        text = 'width=2560\nheight=1440\nvsync=false\nframeRate=60\n'
        self.options.write_text(text)
        result = self.readiness()
        self.assertEqual(result['gameOptions']['targetStatus'], 'Matches')
        cap = next(c for c in result['gameOptions']['targetChecks'] if c['key'] == 'frameRate')
        self.assertEqual(cap['status'], 'Recorded')
        self.assertIsNone(cap['expected'])
        self.assertTrue(any('Saved FPS limit: 60.' in line for line in result['summary']))
        self.assertFalse(any('144' in line for line in result['summary'] if 'FPS' in line or 'frameRate' in line))
        self.assertEqual(self.options.read_text(), text)

    def test_absent_invalid_duplicate_settings_unknown(self):
        for text in ('width=2560\n', 'width=2560\nheight=1440\nvsync=0\nframeRate=144\n',
                     'width=2560\nheight=1440\nvsync=false\nframeRate=144\nframeRate=60\n'):
            with self.subTest(options=text):
                self.options.write_text(text)
                self.assertEqual(self.readiness()['gameOptions']['targetStatus'], 'Unknown')

    def test_compare_complete_options_after_json_roundtrip(self):
        result = self.invoke("""
$before=Get-TrialCaptureReadiness $client $env:PZ_OPTIONS
$before=$before | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$same=Get-TrialCaptureReadiness $client $env:PZ_OPTIONS
[IO.File]::AppendAllText($env:PZ_OPTIONS, "textureCompression=true`n")
$after=Get-TrialCaptureReadiness $client $env:PZ_OPTIONS
$result=[pscustomobject]@{same=(Compare-TrialCaptureSettings $before $same); different=(Compare-TrialCaptureSettings $before $after)}
""")
        self.assertEqual(result['same']['status'], 'Matches')
        self.assertEqual(result['different']['status'], 'Mismatch')
        self.assertEqual(result['different']['differences'], [
            {'key': 'textureCompression', 'reference': None, 'candidate': 'true'}])

    def test_compare_missing_options_is_unknown(self):
        self.options.unlink()
        result = self.invoke('$a=Get-TrialCaptureReadiness $client $env:PZ_OPTIONS; $result=Compare-TrialCaptureSettings $a $a')
        self.assertEqual(result['status'], 'Unknown')

    def test_modern_recording_schema_measured_inventory_and_zero_limits(self):
        # Real names/types and identifier structure from SessionSensorData2 and LHM.
        data = {
            'MeasureTime': {'Name': 'MeasureTime', 'Type': 'Time', 'Values': [0, .25]},
            'BetweenMeasureTime': {'Name': 'BetweenMeasureTime', 'Type': 'Time', 'Values': [0, .25]},
            '/intelcpu/0/load/0': {'Name': 'CPU Total', 'Type': 'Load', 'Values': [33, 44]},
            '/intelcpu/0/clock/0': {'Name': 'CPU Core #1', 'Type': 'Clock', 'Values': [4200, 4300]},
            '/intelcpu/0/temperature/0': {'Name': 'CPU Package', 'Type': 'Temperature', 'Values': [70, 72]},
            '/intelcpu/0/power/0': {'Name': 'CPU Package', 'Type': 'Power', 'Values': [65, 67]},
            '/nvidiagpu/0/load/0': {'Name': 'GPU Core', 'Type': 'Load', 'Values': [80, 90]},
            '/nvidiagpu/0/clock/0': {'Name': 'GPU Core', 'Type': 'Clock', 'Values': [1900, 1950]},
            '/nvidiagpu/0/temperature/0': {'Name': 'GPU Core', 'Type': 'Temperature', 'Values': [70, 72]},
            '/nvidiagpu/0/power/0': {'Name': 'GPU Power', 'Type': 'Power', 'Values': [180, 185]},
            '/nvidiagpu/0/factor/0': {'Name': 'GPU Power Limit', 'Type': 'Factor', 'Values': [0, 0]},
            '/ram/data/0': {'Name': 'RAM Game Used', 'Type': 'Data', 'Values': [8.1, 8.2]},
            '/nvidiagpu/0/smalldata/0': {'Name': 'GPU Memory Dedicated', 'Type': 'SmallData', 'Values': [4096, 4100]},
        }
        result = self.recorded([{'SensorData2': data}])
        self.assertEqual(result['status'], 'Recorded')
        for key, coverage in result['coverage'].items():
            self.assertEqual(coverage['status'], 'Unknown' if key == 'cpuLimits' else 'Recorded', key)
        self.assertEqual(result['coverage']['gpuLimits']['finiteSamples'], 2)
        self.assertEqual(len(result['sensors']), 11)

    def test_legacy_recording_schema(self):
        result = self.recorded([{'SensorData': {
            'MeasureTime': [0, 1], 'CpuUsage': [12, 14], 'CpuMaxThreadUsage': [80, 90],
            'CpuMaxClock': [4500, 4500], 'GpuUsage': [80, 90], 'GpuTemp': [65, 66],
            'VRamUsageGB': [4.5, 4.6], 'GPUPowerLimit': [0, 0]}}])
        self.assertEqual(result['coverage']['cpuLoad']['finiteSamples'], 4)
        self.assertEqual(result['coverage']['vramUsage']['status'], 'Recorded')
        self.assertEqual(result['coverage']['gpuLimits']['status'], 'Recorded')
        self.assertEqual(result['coverage']['cpuPower']['status'], 'Unknown')

    def test_no_sensors_and_timing_only_do_not_fabricate_hardware(self):
        for run in ({}, {'SensorData2': None}, {'SensorData': {'CpuTemp': []}},
                    {'SensorData2': {'MeasureTime': {'Name': 'MeasureTime', 'Type': 'Time', 'Values': [0, 1]}}}):
            with self.subTest(run=run):
                result = self.recorded([run])
                self.assertEqual(result['status'], 'Unknown')
                self.assertTrue(all(value['status'] == 'Unknown' for value in result['coverage'].values()))

    def test_nonfinite_null_false_and_strings_are_not_measured_numbers(self):
        result = self.recorded([{'SensorData2': {
            'gpu/temp': {'Name': 'GPU Core', 'Type': 'Temperature', 'Values': ['NaN', 'Infinity', None, False, '65']},
            'cpu/clock': {'Name': 'CPU Max', 'Type': 'Clock', 'Values': []}}}])
        self.assertEqual(result['status'], 'Unknown')
        self.assertTrue(all(sensor['finiteSamples'] == 0 for sensor in result['sensors']))

    def test_scalar_samples_are_unsupported_single_element_arrays_are_valid(self):
        result = self.recorded([{'SensorData2': {
            'gpu/temp': {'Name': 'GPU Core', 'Type': 'Temperature', 'Values': 65},
            'cpu/clock': {'Name': 'CPU Max', 'Type': 'Clock', 'Values': [4200]}}},
            {'SensorData': {'GpuTemp': 66, 'CpuUsage': [15]}}])
        self.assertEqual(result['coverage']['gpuTemperature']['status'], 'Unknown')
        self.assertEqual(result['coverage']['cpuClock']['finiteSamples'], 1)
        self.assertEqual(result['coverage']['cpuLoad']['finiteSamples'], 1)

    def test_malformed_recording_is_unknown(self):
        self.recording.write_text('{invalid')
        result = self.invoke('$result=Get-TrialRecordedSensors $env:PZ_RECORDING')
        self.assertEqual(result['status'], 'Unknown')
        self.assertEqual(result['jsonStatus'], 'Unknown')


if __name__ == '__main__':
    unittest.main()
