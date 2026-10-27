"""Keep online sleeping displays available to the disposable macOS test client.

GLFW's Cocoa enumeration skips CGDisplayIsAsleep displays, although windowed
NSGL contexts need no display-mode switch. Patch only that reviewed branch in a
private copy extracted from the sealed game JAR. CoreGraphics observations in the
runner remain real; this neither wakes a display nor changes the installed game.
"""
import hashlib
import os
from pathlib import Path
import platform
import re
import subprocess
import zipfile


# B42.21 bundled GLFW 3.5.0. Full hashes guard instruction offsets and semantics.
# ARM64: cbnz w0, monitor-loop -> nop; x64: jne monitor-loop -> two nops.
REVIEWED = {
    'arm64': ('arm64', 'eef265b4e33c6cdf836452367b3531d93a594de00dde85351657e88a90d0e083',
              0x11b90, bytes.fromhex('40ffff35'), bytes.fromhex('1f2003d5')),
    'x86_64': ('x64', '49d4621ec8fec8e92b2a931d24db6ff5da99d0a87d9bb7140d6369f6c861b88c',
               0x12cad, bytes.fromhex('75e1'), bytes.fromhex('9090')),
}


def jvm_architecture(java):
    environment = {key: value for key, value in os.environ.items()
                   if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')}
    result = subprocess.run([str(java), '-XshowSettings:properties', '-version'],
                            check=True, capture_output=True, text=True, timeout=20, env=environment)
    matches = re.findall(r'^\s*os\.arch\s*=\s*(\S+)\s*$', result.stderr, re.M)
    if len(matches) != 1 or matches[0] not in ('aarch64', 'arm64', 'amd64', 'x86_64'):
        raise ValueError('Cannot identify the selected JVM architecture; no native input prepared')
    return 'arm64' if matches[0] in ('aarch64', 'arm64') else 'x86_64'


def prepare(game, directory, java=None):
    # The selected JVM may run under Rosetta independently of the Python runner.
    architecture = jvm_architecture(java) if java is not None else platform.machine()
    if architecture not in REVIEWED:
        raise ValueError('Unreviewed macOS GLFW architecture: ' + architecture)
    folder, expected, offset, before, after = REVIEWED[architecture]
    entry = 'macos/' + folder + '/org/lwjgl/glfw/libglfw.dylib'
    with zipfile.ZipFile(Path(game) / 'projectzomboid.jar') as archive:
        original = archive.read(entry)
    source_hash = hashlib.sha256(original).hexdigest()
    if source_hash != expected or original[offset:offset + len(before)] != before:
        raise ValueError('Unreviewed bundled GLFW for sleeping-display tests: ' + source_hash)
    directory = Path(directory)
    directory.mkdir()
    library = directory / 'libglfw.dylib'
    with library.open('xb') as stream:
        stream.write(original[:offset] + after + original[offset + len(before):])
    # ARM64 code pages require a valid signature after modification. No identity,
    # entitlements, game bundle or user keychain is changed by ad-hoc signing.
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(library)],
                   check=True, capture_output=True, text=True, timeout=20)
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(library)],
                   check=True, capture_output=True, text=True, timeout=20)
    return {'library': str(library), 'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
            'source_sha256': source_hash, 'source_entry': entry, 'architecture': architecture,
            'compatibility': 'retain-online-displays-during-sleep'}


def arguments(root, metadata):
    """Do not accept old snapshots or a library outside this run's owned input."""
    library = Path(root) / 'native/libglfw.dylib'
    if (not isinstance(metadata, dict) or metadata.get('library') != str(library)
            or metadata.get('compatibility') != 'retain-online-displays-during-sleep'
            or library.resolve() != Path(root).resolve() / 'native/libglfw.dylib'
            or library.is_symlink() or not library.is_file()
            or hashlib.sha256(library.read_bytes()).hexdigest() != metadata.get('sha256')):
        raise ValueError('Prepared macOS GLFW compatibility input is missing or changed; prepare a fresh run')
    return ['-Dorg.lwjgl.glfw.libname=' + str(library)]
