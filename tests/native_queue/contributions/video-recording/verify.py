"""Verify two completed native clips without starting Project Zomboid."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import re
import subprocess

RESULT = re.compile(r'\[VIDEO_TEST\] RESULT state=(\w+) file=(.+?) frames=(\d+) seconds=([\d.]+) captured=(\d+) dropped=(\d+) width=(\d+) height=(\d+) error=(.*)')


def parse_results(text):
    if 'VOICE_DISABLED' not in text or '[VIDEO_TEST] RESTART' not in text:
        raise ValueError('Missing VOIP check or recorder restart marker')
    stops = re.findall(r'\[VIDEO_TEST\] STOP wallMs=(\d+)', text)
    results = RESULT.findall(text)
    if len(stops) != 2 or len(results) != 2:
        raise ValueError('Expected exactly two STOP/RESULT pairs in a fresh profile')
    records = []
    for match, elapsed in zip(results, stops):
        state, file, frames, seconds, captured, dropped, width, height, error = match
        if state != 'completed' or error.strip():
            raise ValueError('Recorder failed: ' + error)
        records.append(dict(file=file, frames=int(frames), seconds=float(seconds), captured=int(captured),
                            dropped=int(dropped), width=int(width), height=int(height), elapsed_ms=int(elapsed)))
    if records[0]['file'] == records[1]['file']:
        raise ValueError('Restart reused the first output filename')
    return records


def validate_metadata(record, metadata):
    streams = metadata.get('streams', [])
    if len(streams) != 1 or streams[0].get('codec_type') != 'video':
        raise ValueError('Expected one video stream and no audio')
    video = streams[0]
    width, height = (record['width'] + 1)//2*2, (record['height'] + 1)//2*2
    if video['codec_name'] != 'h264' or (video['width'], video['height']) != (width, height):
        raise ValueError('Codec or dimensions differ from recorder status')
    if Fraction(video['r_frame_rate']) != 30 or Fraction(video['avg_frame_rate']) != 30:
        raise ValueError('Expected constant 30 FPS')
    frames, duration = int(video['nb_read_frames']), float(video['duration'])
    if frames != record['frames'] or frames < 3 or record['captured'] < 1:
        raise ValueError('Frame count differs from recorder status or capture is empty')
    # MP4's 1000 Hz movie clock quantizes duration; ffprobe prints six decimal places.
    duration_tolerance = 0.001001
    if abs(duration - frames/30) > duration_tolerance or abs(duration - record['seconds']) > duration_tolerance:
        raise ValueError('Encoded duration differs from frame count/status')
    if record['elapsed_ms'] < 3500 or abs(duration - record['elapsed_ms']/1000) > 2/30:
        raise ValueError('Encoded duration does not preserve the test interval')


def verify(profile, ffmpeg, ffprobe):
    profile = profile.resolve(strict=True)
    text = (profile/'console.txt').read_text(encoding='utf-8', errors='replace')
    records = parse_results(text)
    output = profile/'verification'
    output.mkdir(exist_ok=True)
    for index, record in enumerate(records, 1):
        video = Path(record['file']).resolve(strict=True)
        if not video.is_relative_to(profile/'videos'):
            raise ValueError('Recorded video is outside this profile/videos')
        probe = subprocess.run([str(ffprobe), '-v', 'error', '-count_frames', '-show_streams',
                                '-of', 'json', str(video)], check=True, capture_output=True, text=True, timeout=30)
        metadata = json.loads(probe.stdout)
        validate_metadata(record, metadata)
        subprocess.run([str(ffmpeg), '-v', 'error', '-xerror', '-i', str(video), '-f', 'null', '-'], check=True, timeout=30)
        frames = record['frames']
        select = f'select=eq(n\\,0)+eq(n\\,{frames//2})+eq(n\\,{frames-1})'
        subprocess.run([str(ffmpeg), '-v', 'error', '-y', '-i', str(video), '-vf', select,
                        '-fps_mode', 'vfr', str(output/f'clip-{index}-frame-%02d.png')], check=True, timeout=30)
        for frame in range(1, 4):
            if not (output/f'clip-{index}-frame-{frame:02d}.png').is_file():
                raise ValueError('Frame extraction did not produce three images')
        record['probe'] = metadata
    (output/'result.json').write_text(json.dumps(records, indent=2))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('profile', 'ffmpeg', 'ffprobe'):
        parser.add_argument('--' + flag, type=Path, required=True)
    args = parser.parse_args()
    try:
        records = verify(args.profile, args.ffmpeg, args.ffprobe)
        print('VIDEO_FIXTURE_VERIFY_PASS', [(r['frames'], r['seconds'], r['dropped']) for r in records])
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
