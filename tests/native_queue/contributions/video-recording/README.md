# Native video recording fixture

[Development](../../../../docs/DEVELOPMENT.md#test-video) · [Native runner](../../README.md)

This fixture validates the B42.21 in-game recorder through the shared native runner in a fresh, disposable SP profile. The adapter stages `VideoFixture.lua` and its encoder configuration; the common runner owns mod snapshots, local JAR approvals, silent settings, desktop admission, AeroSpace placement, PID/window checks and process cleanup. Build Java Patches first with the [mixed Kotlin/Java toolchain](../../../../docs/DEVELOPMENT.md#java-development). The fixture uses the built JAR and needs no separate Kotlin runtime.

## Prepare and run

Create a JSON options file outside the checkout, for example `/tmp/pz-video-options.json`, containing explicit executable paths:

```json
{
  "ffmpeg": "/absolute/path/to/ffmpeg",
  "ffprobe": "/absolute/path/to/ffprobe",
  "desktop_mode": "aerospace"
}
```

The FFmpeg build must include `libx264`. With `PZ_GAME` pointing to the directory containing `projectzomboid.jar` and `ZombieBuddy.jar`, and `PZ_JDK` to a JDK 25+ home:

```sh
python3 JavaPatches/build.py --game "$PZ_GAME" --jdk "$PZ_JDK"
python3 tools/check_action_queue.py prepare /tmp/pz-video-capture-fresh \
  --suite video-recording --cases captures --kind sp --mode toolkit --language EN \
  --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --workshop /path/to/workshop/content/108600 \
  --config /tmp/pz-video-options.json
python3 tools/check_action_queue.py resume /tmp/pz-video-capture-fresh
```

The run directory must not already exist at preparation. `prepare` creates snapshots without launching; `resume` launches that prepared run, stops its owned processes and writes the common report. To prepare and launch in one command, use `run` instead of `prepare` with another fresh run directory and the same arguments. EN is the default; RU is accepted, with historical language coverage listed below. The default mod subset is ZombieBuddy, Java Patches and Toolkit; it does not establish full-pack compatibility.

This configuration uses `desktop_mode=aerospace`, which requires successful placement in the assigned test workspace. Keep the shared runner's PID/window, focus/fullscreen and admission gates; do not invoke a separate launcher or use direct `Popen` to bypass them. See the [runner commands](../../README.md#commands) for preparation and resource options. The scenario starts a fresh Sandbox named `VideoFixture`, records twice for about 3.5 seconds, and checks duplicate starts/stops and recording restart. The adapter requires `[VIDEO_TEST] PASSED` before verifying the clips; the common report also requires readiness, clean runtime logs and unchanged inputs.

## Clip evidence

The client cache is `<run>/client1`, with captures under `videos/` and first/middle/last PNGs plus `result.json` under `verification/`. The common adapter invokes the clip verifier automatically. To repeat clip verification without launching the game:

```sh
python3 tests/native_queue/contributions/video-recording/verify.py \
  --profile /tmp/pz-video-capture-fresh/client1 \
  --ffmpeg /absolute/path/to/ffmpeg \
  --ffprobe /absolute/path/to/ffprobe
```

Verification checks recorder success and the voice-disabled marker, dimensions, frame rate, frame count, duration, absent audio and a full decode. For a human visual check, play either captured file with `ffplay -an -autoexit /path/to/capture.mp4` and inspect the extracted images. Keep generated profiles, logs, videos and extracted images outside this contribution. Standalone clip verification does not replace the common runtime and provenance report.

Invalid output paths are tested through the public `VideoRecording.start` API in headless `VideoChecks`, including relative paths, the profile root and symlink escapes, with no capture files or encoder created on rejection. Keeping expected error diagnostics out of the positive live scenario lets the common runtime audit remain strict. Frame readback uses the actual GLFW framebuffer size, which can differ from the requested window size on scaled or Retina displays. Synchronous GL readback can reduce game FPS; queued frames preserve elapsed time by holding the previous image. The recorder caps output at 4K, fails and finalizes on resize, and has a 15-second FFmpeg stop timeout.

Run the no-game adapter and clip checks from the repository root:

```sh
python3 -m unittest discover -s tests -p test_queue_auxiliary_adapters.py
python3 -m unittest discover -s tests/native_queue/contributions/video-recording -p 'test_*.py'
```

Existing encoder edge-case coverage is reusable via `PZ_TEST_FFMPEG=/absolute/path/to/ffmpeg python3 JavaPatches/build.py --check-video`: missing encoder, stop before the first frame, timeline gaps, resize and bounded-buffer guards. Those tests do not require a game window.

## Supported scope and limits

The dated validation in `manifest.json` is historical evidence. It does not establish current support for multiplayer, Russian, Windows, Linux, long sessions, sustained 4K or live resize; each new shared-runner report records its own coverage. The Display hook is guarded by the fingerprint recorded in `manifest.json`. The recorder's API and limits are in [development: test video](../../../../docs/DEVELOPMENT.md#test-video).

Playback and visual inspection remain manual checks; `verify.py` performs decoding and extracts frames.
