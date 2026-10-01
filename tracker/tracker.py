"""Webcam body tracker: streams MediaPipe pose landmarks to Godot over UDP.

Usage:
    uv run tracker.py            # live webcam tracking
    uv run tracker.py --test     # fake animated pose, no camera needed
"""

import argparse
import json
import math
import socket
import time
import urllib.request
from pathlib import Path

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
)
MODEL_PATH = Path(__file__).parent / "pose_landmarker_lite.task"
NUM_LANDMARKS = 33


def _pack(points):
    return [[round(x, 4), round(y, 4), round(z, 4), round(v, 3)] for x, y, z, v in points]


def send(sock, addr, landmarks, world_landmarks, width, height):
    """landmarks: (x, y, z, visibility) in normalized image coords.
    world_landmarks: (x, y, z, visibility) in meters, origin between the hips, y down."""
    payload = {"w": width, "h": height, "lm": _pack(landmarks), "wlm": _pack(world_landmarks)}
    sock.sendto(json.dumps(payload).encode(), addr)


def fake_pose(t):
    """A standing figure that sways side to side and periodically raises both arms."""
    sway = 0.07 * math.sin(t * 0.8)
    arms_up = math.sin(t * 1.3) > 0.6
    pts = {
        0: (0.5 + sway, 0.2),  # nose
        11: (0.42 + sway, 0.35), 12: (0.58 + sway, 0.35),  # shoulders
        23: (0.45 + sway * 0.2, 0.6), 24: (0.55 + sway * 0.2, 0.6),  # hips
        25: (0.45, 0.75), 26: (0.55, 0.75),  # knees
        27: (0.45, 0.9), 28: (0.55, 0.9),  # ankles
    }
    if arms_up:
        pts.update({13: (0.38 + sway, 0.22), 14: (0.62 + sway, 0.22),
                    15: (0.4 + sway, 0.08), 16: (0.6 + sway, 0.08)})
    else:
        pts.update({13: (0.38 + sway, 0.47), 14: (0.62 + sway, 0.47),
                    15: (0.37 + sway * 0.5, 0.6), 16: (0.63 + sway * 0.5, 0.6)})
    pts.update({7: (pts[0][0] + 0.04, 0.19), 8: (pts[0][0] - 0.04, 0.19),  # ears
                31: (0.45, 0.92), 32: (0.55, 0.92)})  # toes
    reach = max(0.0, math.sin(t * 0.9)) * 0.4  # left hand reaches toward the camera
    nose = pts[0]
    image = [(*pts[i], 0.0, 1.0) if i in pts else (*nose, 0.0, 0.0) for i in range(NUM_LANDMARKS)]
    # World coords: meters, centered between the hips, y down, negative z toward the camera.
    world = []
    for i, (x, y, _, v) in enumerate(image):
        z = {7: 0.05, 8: 0.05, 0: -0.08, 31: -0.12, 32: -0.12, 13: -reach / 2, 15: -reach}.get(i, 0.0)
        world.append(((x - 0.5) * 2.3, (y - 0.6) * 2.3, z, v))
    return image, world


def run_test(sock, addr):
    print(f"Sending fake pose to {addr[0]}:{addr[1]} (Ctrl-C to stop)")
    start = time.monotonic()
    while True:
        image, world = fake_pose(time.monotonic() - start)
        send(sock, addr, image, world, 640, 480)
        time.sleep(1 / 30)


def run_live(sock, addr, camera_index, show_preview, fast=False):
    import cv2
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision

    if not MODEL_PATH.exists():
        print("Downloading pose model...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)

    cap = cv2.VideoCapture(camera_index)
    # Ask for a modest resolution at 30 fps; pose tracking doesn't need more, and big frames are slow.
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # always work on the newest frame, not a queued stale one
    if not cap.isOpened():
        raise SystemExit(
            f"Could not open camera {camera_index}. "
            "Check System Settings > Privacy & Security > Camera for your terminal app."
        )

    options = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
        # VIDEO mode tracks and smooths landmarks across frames, which trails fast movement a little;
        # IMAGE mode (--fast) treats every frame on its own: less lag, a bit more jitter.
        running_mode=vision.RunningMode.IMAGE if fast else vision.RunningMode.VIDEO,
        num_poses=1,
    )
    print(f"Tracking camera {camera_index} -> {addr[0]}:{addr[1]} (press q in the preview to quit)")
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        start = time.monotonic()
        last_ts = -1
        dark_since = None
        frames, fps_since = 0, time.monotonic()
        read_time = detect_time = 0.0
        while True:
            t_read = time.monotonic()
            ok, frame = cap.read()
            read_time += time.monotonic() - t_read
            if not ok:
                break
            if frame.mean() < 3:
                dark_since = dark_since or time.monotonic()
                if time.monotonic() - dark_since > 3:
                    print(f"Camera {camera_index} is only sending black frames. "
                          "Try another one with --camera 1 (or 2), or check the lid/lens cover.")
                    dark_since = time.monotonic() + 1000  # warn once
            else:
                dark_since = None
            # Landmarks come from the unmirrored camera image, so the data's right side is
            # your real right side; only the preview is mirrored below.
            height, width = frame.shape[:2]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            ts = max(int((time.monotonic() - start) * 1000), last_ts + 1)
            last_ts = ts
            t_detect = time.monotonic()
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect(image) if fast else landmarker.detect_for_video(image, ts)
            detect_time += time.monotonic() - t_detect

            if result.pose_landmarks:
                lms = [(l.x, l.y, l.z, l.visibility or 0.0) for l in result.pose_landmarks[0]]
                wlms = [(l.x, l.y, l.z, l.visibility or 0.0) for l in result.pose_world_landmarks[0]]
                send(sock, addr, lms, wlms, width, height)
                for x, y, _, v in lms:
                    if v > 0.5:
                        cv2.circle(frame, (int(x * width), int(y * height)), 4, (0, 255, 120), -1)
            else:
                send(sock, addr, [], [], width, height)  # heartbeat: tracker is up, nobody in view
            frames += 1
            if time.monotonic() - fps_since >= 5:
                fps = frames / (time.monotonic() - fps_since)
                wait_ms, detect_ms = read_time / frames * 1000, detect_time / frames * 1000
                # Waiting on the camera dominates -> the camera is the limit (usually low light).
                hint = "  (camera-limited: add light in front of you)" if fps < 24 and wait_ms > detect_ms else ""
                print(f"{fps:.0f} fps, {width}x{height}, camera wait {wait_ms:.0f} ms, pose model {detect_ms:.0f} ms{hint}")
                frames, fps_since = 0, time.monotonic()
                read_time = detect_time = 0.0
            if show_preview:
                preview = cv2.flip(frame, 1)  # mirror the preview so it feels like a mirror
                status = "Tracking" if result.pose_landmarks else "No person detected"
                color = (0, 255, 120) if result.pose_landmarks else (0, 180, 255)
                cv2.putText(preview, f"Camera {camera_index}: {status}", (16, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, color, 2)
                cv2.imshow("Body tracker (q to quit)", preview)
                if cv2.waitKey(1) & 0xFF in (ord("q"), 27):
                    break
    cap.release()
    cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4242)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--no-preview", action="store_true", help="don't show the webcam window")
    parser.add_argument("--test", action="store_true", help="send a fake animated pose instead of using the camera")
    parser.add_argument("--fast", action="store_true", help="no cross-frame smoothing: less lag, a bit more jitter")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    addr = (args.host, args.port)
    try:
        if args.test:
            run_test(sock, addr)
        else:
            run_live(sock, addr, args.camera, not args.no_preview, args.fast)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
