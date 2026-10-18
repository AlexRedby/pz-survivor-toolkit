# Native video recording fixture

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

This fixture validates the B42.21 in-game recorder in a fresh, disposable profile. It does not launch the game itself. Build JavaPatches first, then prepare the profile:

```sh
python3 JavaPatches/build.py
python3 tests/native_queue/contributions/video-recording/prepare.py \
  --game "/path/to/Project Zomboid/Contents/Java" \
  --jdk "/path/to/jdk-25/Contents/Home" \
  --java "/path/to/game-bundled-java/bin/java" \
  --zombie-buddy-mod "/path/to/installed/ZombieBuddy" \
  --patch-mod "JavaPatches/build/PZToolkitJavaPatches" \
  --ffmpeg "/absolute/path/to/ffmpeg" \
  --profile "/absolute/path/to/new-disposable-profile" \
  --language EN
```

`--profile` must not already exist. Preparation copies the selected mods into that profile, compiles the included launcher, writes a local SHA approval policy with `deny-new`, sets `voiceEnable=false`, and writes `launch.json` containing `cwd` and `argv`. It never starts the game. EN is the default; RU is also accepted.

Review the generated `launch.json`, then explicitly launch it from Python:

```python
import json
import subprocess
from pathlib import Path

profile = Path("/absolute/path/to/new-disposable-profile")
launch = json.loads((profile / "launch.json").read_text())
with (profile / "native-launch.log").open("wb") as log:
    process = subprocess.Popen(
        launch["argv"], cwd=launch["cwd"], stdin=subprocess.DEVNULL,
        stdout=log, stderr=subprocess.STDOUT,
    )
```

Run this in an interactive macOS GUI session with the display awake. Cocoa display initialization can stall with `Connection Invalid` when launched from a sandbox without a usable GUI session. The generated command uses `launchctl asuser` and clears inherited JVM option variables to avoid a second Java agent. It may still need to run outside the sandbox. The fixture starts a fresh SP Sandbox named `VideoFixture`, records twice for about 3.5 seconds, and leaves the game running. Close only the process started above; do not reuse an existing save or terminate unrelated game processes.

After both `RESULT` records and `STOP` wall-time records appear, verify the clips:

```sh
python3 tests/native_queue/contributions/video-recording/verify.py \
  --profile "/absolute/path/to/new-disposable-profile" \
  --ffmpeg "/absolute/path/to/ffmpeg" \
  --ffprobe "/absolute/path/to/ffprobe"
```

For a human visual check, play either captured file with `ffplay -an -autoexit /path/to/capture.mp4` and inspect the extracted images.

Verification checks recorder success and the voice-disabled marker, dimensions, frame rate, frame count, duration, absent audio, and a full decode. It extracts first, middle, and last PNGs under `profile/verification/`. Keep generated profiles, logs, videos, and extracted images outside this contribution.

The live fixture checks successful captures, duplicate starts/stops and a recording restart. Invalid output paths are tested through the public `VideoRecording.start` API in headless `VideoChecks`, including relative paths, the profile root and symlink escapes, with no capture files or encoder created on rejection. Keeping expected error diagnostics out of the positive live scenario lets the common runtime audit remain strict. Frame readback uses the actual GLFW framebuffer size, which can differ from the requested window size on scaled or Retina displays. Synchronous GL readback can reduce game FPS; queued frames preserve elapsed time by holding the previous image. The recorder caps output at 4K, fails and finalizes on resize, and has a 15-second FFmpeg timeout.

Run the no-game tests from the repository root:

```sh
python3 -m unittest discover -s tests/native_queue/contributions/video-recording -p 'test_*.py'
```

Existing encoder edge-case coverage is reusable via `PZ_TEST_FFMPEG=/absolute/path/to/ffmpeg python3 JavaPatches/build.py --check-video`: missing encoder, stop before the first frame, timeline gaps, resize and bounded-buffer guards. Those tests do not require a game window.

## Supported scope and limits

The fixture does not establish support for multiplayer, Russian, Windows, Linux, long sessions, sustained 4K, live resize, or forced shutdown recovery. The Display hook is guarded by the fingerprint recorded in `manifest.json`. The recorder's API and limits are in [development: test video](../../../../docs/DEVELOPMENT.md#test-video).

Playback/visual inspection remains a manual check; `verify.py` performs decoding and extracts frames.

The common runner stages the same Lua fixture with its shared `ToolkitSmokeLauncher`, GUI mutex and owned-process cleanup through `tools/queue_checks/adapters/auxiliary.py`. Its adapter requires the terminal `PASSED` marker before invoking this contribution's unchanged FFprobe/decode/frame-extraction verifier. Pass explicit absolute `ffmpeg` and `ffprobe` paths in the common runner configuration. Current verification is recorded separately in each run report.
