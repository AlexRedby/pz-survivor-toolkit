"""Trusted optimizer cache and browser fallback; fixtures never access the network."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PWSH=shutil.which('pwsh')
def ps(value):return "'"+str(value).replace("'","''")+"'"

@unittest.skipUnless(PWSH,'PowerShell required')
class DownloadCache(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='pz-download-cache-')
        self.root=Path(self.tmp.name).resolve();self.addCleanup(self.tmp.cleanup)
        self.package=self.root/'package';self.package.mkdir()
        self.zip=self.root/'browser.zip'
        files={'zombie/iso/worldgen/WorldGenUtils.class':b'world','zombie/core/skinnedmodel/advancedanimation/AnimationSet.class':b'animation'}
        with zipfile.ZipFile(self.zip,'w') as z:
            for name,data in files.items():z.writestr(name,data)
        self.manifest=self.root/'manifest.json'
        self.manifest.write_text(json.dumps({'profile':{'id':'xd3i-b42.21-d1bbdcf-bounded-v1','properties':{}},'release_url':'https://github.com/xD3I/PZ_Optimization/releases/download/fixture/fixture.zip','release_sha256':hashlib.sha256(self.zip.read_bytes()).hexdigest(),'release_bytes':self.zip.stat().st_size,'selected_files':{name:hashlib.sha256(data).hexdigest() for name,data in files.items()}}))
    def run_ps(self,body):
        p=self.root/'run.ps1';p.write_text("$env:USERPROFILE="+ps(self.root)+"\n. "+ps(ROOT/'tests/optimizer_trial/Launch-Trial.ps1')+" -SourceProfile "+ps(self.root/'source')+"\n$m=Get-Content -Raw "+ps(self.manifest)+" | ConvertFrom-Json\n$package="+ps(self.package)+"\n$source="+ps(self.zip)+"\n"+body)
        r=subprocess.run([PWSH,'-NoProfile','-NonInteractive','-File',str(p)],text=True,capture_output=True,timeout=20)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        return r.stdout
    def test_download_promotes_only_verified_bytes_and_cache_skips_network(self):
        self.run_ps("""
$script:downloads=0
function Save-TrialDownload {param($Uri,$Destination,$ExpectedBytes);$script:downloads++;if($ExpectedBytes -ne (Get-Item $source).Length){throw 'size not forwarded'};[IO.File]::Copy($source,$Destination,$false)}
$a=Get-TrialCandidate $package $m
$b=Get-TrialCandidate $package $m
if($script:downloads -ne 1 -or $a.Zip -ne $b.Zip){throw 'cache redownloaded'}
""")
        self.assertEqual((self.package/'Candidate/official-classes.zip').read_bytes(),self.zip.read_bytes())
        self.assertEqual(json.loads((self.package/'Candidate/last-download.json').read_text())['status'],'Verified')
        self.assertFalse(list((self.package/'Candidate').glob('*.download')))
    def test_timeout_or_bad_hash_preserves_partial_and_never_promotes(self):
        for kind in ('timeout','hash'):
            with self.subTest(kind=kind):
                package=self.package/kind;package.mkdir()
                code="$package="+ps(package)+"\nfunction Save-TrialDownload {param($Uri,$Destination,$ExpectedBytes);[IO.File]::WriteAllText($Destination,'partial');"+("throw 'Download inactivity timeout'" if kind=='timeout' else '')+"}\n"
                self.run_ps(code+"$caught=$false;try{Get-TrialCandidate $package $m}catch{$caught=$true};if(-not $caught){throw 'bad data accepted'}")
                self.assertFalse((package/'Candidate/official-classes.zip').exists())
                self.assertFalse((package/'Candidate/overlay').exists())
                status=json.loads((package/'Candidate/last-download.json').read_text())
                self.assertEqual(status['status'],'Failed');self.assertEqual(status['bytes'],7)
                self.assertEqual((package/'Candidate'/status['partialFile']).read_text(),'partial')
    def test_browser_zip_is_verified_and_original_is_unchanged(self):
        original=self.zip.read_bytes()
        self.run_ps("function Save-TrialDownload {throw 'network must not run'}\nGet-TrialCandidate $package $m -SourceZip $source | Out-Null")
        self.assertEqual(self.zip.read_bytes(),original)
        self.assertEqual((self.package/'Candidate/official-classes.zip').read_bytes(),original)
    def test_corrupt_existing_cache_is_preserved_and_not_extracted(self):
        directory=self.package/'Candidate';directory.mkdir();(directory/'official-classes.zip').write_bytes(b'bad existing cache')
        self.run_ps("function Save-TrialDownload {throw 'network must not run'}\n$caught=$false;try{Get-TrialCandidate $package $m}catch{$caught=$_.Exception.Message -match 'SHA-256 mismatch'};if(-not $caught){throw 'corrupt cache accepted'}")
        self.assertEqual((directory/'official-classes.zip').read_bytes(),b'bad existing cache')
        self.assertFalse((directory/'overlay').exists())

if __name__=='__main__':unittest.main()
