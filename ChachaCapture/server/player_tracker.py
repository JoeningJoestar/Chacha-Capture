"""Face, head and upper-body tracker for Chacha Capture.

The bridge binds to loopback only. Camera images stay on this computer; GMod
receives a compact JSON object containing the 53 MediaPipe face coefficients
and optional upper-body rotations over the existing WebSocket connection.
"""

from __future__ import annotations

import argparse
import asyncio
from concurrent.futures import ThreadPoolExecutor
import json
import math
import sys
import time
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np
from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed


BLENDSHAPES = (
    "_neutral",
    "browDownLeft",
    "browDownRight",
    "browInnerUp",
    "browOuterUpLeft",
    "browOuterUpRight",
    "cheekPuff",
    "cheekSquintLeft",
    "cheekSquintRight",
    "eyeBlinkLeft",
    "eyeBlinkRight",
    "eyeLookDownLeft",
    "eyeLookDownRight",
    "eyeLookInLeft",
    "eyeLookInRight",
    "eyeLookOutLeft",
    "eyeLookOutRight",
    "eyeLookUpLeft",
    "eyeLookUpRight",
    "eyeSquintLeft",
    "eyeSquintRight",
    "eyeWideLeft",
    "eyeWideRight",
    "jawForward",
    "jawLeft",
    "jawOpen",
    "jawRight",
    "mouthClose",
    "mouthDimpleLeft",
    "mouthDimpleRight",
    "mouthFrownLeft",
    "mouthFrownRight",
    "mouthFunnel",
    "mouthLeft",
    "mouthLowerDownLeft",
    "mouthLowerDownRight",
    "mouthPressLeft",
    "mouthPressRight",
    "mouthPucker",
    "mouthRight",
    "mouthRollLower",
    "mouthRollUpper",
    "mouthShrugLower",
    "mouthShrugUpper",
    "mouthSmileLeft",
    "mouthSmileRight",
    "mouthStretchLeft",
    "mouthStretchRight",
    "mouthUpperUpLeft",
    "mouthUpperUpRight",
    "noseSneerLeft",
    "noseSneerRight",
    "tongueOut",
)

POSE_KEYS = (
    "head",
    "neck",
    "waist",
    "spine",
    "left_clavicle",
    "left_upper_arm",
    "left_forearm",
    "left_wrist",
    "right_clavicle",
    "right_upper_arm",
    "right_forearm",
    "right_wrist",
)
UPPER_BODY_KEYS = POSE_KEYS[2:]
WINDOW_TITLE = "Chacha Capture | Face + Head"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="GMod face and upper-body tracker")
    parser.add_argument("--camera", type=int, default=0, help="OpenCV camera number")
    parser.add_argument(
        "--list-cameras",
        action="store_true",
        help="scan camera indexes and exit",
    )
    parser.add_argument(
        "--camera-scan-count",
        type=int,
        default=10,
        help="number of camera indexes to scan with --list-cameras",
    )
    parser.add_argument("--port", type=int, default=8667, help="local WebSocket port")
    parser.add_argument("--fps", type=float, default=30.0, help="maximum tracking FPS")
    parser.add_argument("--width", type=int, default=640, help="capture width (480p preset)")
    parser.add_argument("--height", type=int, default=480, help="capture height (480p preset)")
    parser.add_argument(
        "--processing-width",
        type=int,
        default=480,
        help="tracking input width; capture and preview keep their full aspect ratio",
    )
    parser.add_argument("--preview", action="store_true", help="show camera and pose preview")
    parser.add_argument("--no-mirror", action="store_true", help="do not mirror the camera")
    parser.add_argument("--no-pose", action="store_true", help="disable upper-body processing")
    parser.add_argument(
        "--pose-complexity",
        type=int,
        choices=(0, 1, 2),
        default=0,
        help="MediaPipe Pose model complexity",
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=Path(__file__).with_name("face_landmarker.task"),
        help="path to face_landmarker.task",
    )
    return parser.parse_args()


def list_cameras(scan_count: int) -> int:
    """Print camera indexes that OpenCV can open, including virtual cameras."""
    scan_count = max(1, min(int(scan_count), 64))
    if sys.platform == "win32":
        backends = (("DirectShow", cv2.CAP_DSHOW), ("Media Foundation", cv2.CAP_MSMF))
    else:
        backends = (("automatic", cv2.CAP_ANY),)

    found: dict[int, tuple[str, int, int]] = {}
    for backend_name, backend in backends:
        for index in range(scan_count):
            if index in found:
                continue
            camera = cv2.VideoCapture(index, backend)
            try:
                if not camera.isOpened():
                    continue
                ok, frame = camera.read()
                if not ok or frame is None or not frame.size:
                    continue
                height, width = frame.shape[:2]
                found[index] = (backend_name, width, height)
            finally:
                camera.release()

    if not found:
        print("[Camera] no usable cameras found")
        print("[Camera] install and start the Iriun Webcam driver, then run this scan again")
        return 1

    print("[Camera] available camera indexes:")
    for index in sorted(found):
        backend_name, width, height = found[index]
        print(f"  {index}: {width}x{height} ({backend_name})")
    print("[Camera] start with --camera N, for example: start_player_tracker.bat --camera 1")
    return 0


def vector(landmark: Any) -> np.ndarray:
    return np.array((landmark.x, landmark.y, landmark.z), dtype=np.float64)


def safe_normalize(value: np.ndarray) -> np.ndarray:
    length = float(np.linalg.norm(value))
    return value / length if length > 1e-7 else np.zeros(3, dtype=np.float64)


def angle_between(first: np.ndarray, second: np.ndarray) -> float:
    first = safe_normalize(first)
    second = safe_normalize(second)
    return math.degrees(math.acos(float(np.clip(np.dot(first, second), -1.0, 1.0))))


def elbow_flexion(shoulder: np.ndarray, elbow: np.ndarray, wrist: np.ndarray) -> float:
    """Return zero for a straight elbow and a positive bend up to 145°."""
    upper_from_elbow = shoulder - elbow
    lower_from_elbow = wrist - elbow
    interior = angle_between(upper_from_elbow, lower_from_elbow)
    return clamp(180.0 - interior, 0.0, 145.0)


def matrix_euler_degrees(matrix: Any) -> list[float]:
    """Convert MediaPipe's facial rotation matrix to GMod pitch/yaw/roll.

    MediaPipe's first two Euler axes map to the opposite named axes in
    Source's Angle convention.  Keep the conversion here so the JSON protocol
    can consistently describe angles in GMod order.
    """
    rotation = np.asarray(matrix, dtype=np.float64)[:3, :3]
    horizontal = math.sqrt(rotation[0, 0] ** 2 + rotation[1, 0] ** 2)
    if horizontal > 1e-6:
        pitch = math.atan2(rotation[2, 1], rotation[2, 2])
        yaw = math.atan2(-rotation[2, 0], horizontal)
        roll = math.atan2(rotation[1, 0], rotation[0, 0])
    else:
        pitch = math.atan2(-rotation[1, 2], rotation[1, 1])
        yaw = math.atan2(-rotation[2, 0], horizontal)
        roll = 0.0
    # Source/GMod pitch uses the opposite sign from MediaPipe's vertical turn.
    game_pitch = -yaw
    # Keep the default horizontal direction unmirrored. Camera-specific
    # horizontal reversal is exposed separately in the GMod UI.
    game_yaw = -pitch
    return [math.degrees(game_pitch), math.degrees(game_yaw), math.degrees(roll)]


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def resize_for_tracking(frame: np.ndarray, maximum_width: int) -> np.ndarray:
    """Downscale inference without cropping the camera's horizontal view."""
    height, width = frame.shape[:2]
    if maximum_width <= 0 or width <= maximum_width:
        return frame
    scale = maximum_width / width
    return cv2.resize(
        frame,
        (maximum_width, max(1, round(height * scale))),
        interpolation=cv2.INTER_AREA,
    )


def body_axes(
    left_shoulder: np.ndarray,
    right_shoulder: np.ndarray,
    left_hip: np.ndarray | None = None,
    right_hip: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Build a stable up/right/forward frame from the visible torso.

    Arm angles measured directly against the camera axes are the source of
    most of the old "elbow behind the body" failures. A torso-relative frame
    follows a player's lean and slight turn, while preserving anatomical left
    and right labels.
    """
    right_axis = safe_normalize(right_shoulder - left_shoulder)
    if float(np.linalg.norm(right_axis)) < 1e-7:
        right_axis = np.array((1.0, 0.0, 0.0), dtype=np.float64)
    if left_hip is not None and right_hip is not None:
        shoulder_mid = (left_shoulder + right_shoulder) * 0.5
        hip_mid = (left_hip + right_hip) * 0.5
        up_axis = safe_normalize(shoulder_mid - hip_mid)
    else:
        # MediaPipe image/world coordinates point down on Y.
        up_axis = np.array((0.0, -1.0, 0.0), dtype=np.float64)
    if float(np.linalg.norm(up_axis)) < 1e-7:
        up_axis = np.array((0.0, -1.0, 0.0), dtype=np.float64)
    front_axis = safe_normalize(np.cross(up_axis, right_axis))
    if float(np.linalg.norm(front_axis)) < 1e-7:
        front_axis = np.array((0.0, 0.0, -1.0), dtype=np.float64)
    # MediaPipe's smaller z values are closer to the camera. Force this axis
    # to point toward the camera so every downstream calculation uses the
    # same hard convention: positive front, negative back.
    if front_axis[2] > 0.0:
        front_axis = -front_axis
    return up_axis, right_axis, front_axis


def limb_angles(
    start: np.ndarray,
    end: np.ndarray,
    side: float,
    axes: tuple[np.ndarray, np.ndarray, np.ndarray] | None = None,
) -> list[float]:
    """Return bounded upper-arm pitch/yaw relative to the player's torso.

    `side` is -1 for the anatomical left arm and +1 for the right arm. The
    outward component is made positive for both arms; the GMod client later
    applies its model-side mirror when assigning the two bones.
    """
    direction = safe_normalize(end - start)
    if axes is None:
        up_axis = np.array((0.0, -1.0, 0.0), dtype=np.float64)
        right_axis = np.array((1.0, 0.0, 0.0), dtype=np.float64)
        front_axis = np.array((0.0, 0.0, -1.0), dtype=np.float64)
    else:
        up_axis, right_axis, front_axis = axes
    down_component = float(np.dot(direction, -up_axis))
    outward_component = float(np.dot(direction, right_axis * side))
    front_component = float(np.dot(direction, front_axis))
    lateral = math.degrees(math.atan2(outward_component, down_component))
    # Forward tilt is independent of whether the arm is below or above the
    # shoulder. Using `down_component` directly makes an overhead arm look
    # like a 180-degree forward turn; use the non-front magnitude as the
    # reference instead.
    non_front_reference = max(
        math.sqrt(down_component * down_component + outward_component * outward_component),
        1e-5,
    )
    forward = math.degrees(math.atan2(front_component, non_front_reference))

    # A webcam cannot reliably distinguish a shoulder rotating through the
    # back hemisphere. Keep the upper arm in the useful human range: down to
    # side to overhead and the front of the torso. This prevents the classic
    # 180-degree "arm flips behind the body" failure.
    lateral = clamp(lateral, 0.0, 108.0)
    # The output is a front-half target, not a full spherical rotation. A
    # negative value would put the shoulder behind the torso, so discard it.
    forward = clamp(forward, 0.0, 55.0)
    return [forward, lateral, 0.0]


def forearm_angles(
    shoulder: np.ndarray,
    elbow: np.ndarray,
    wrist: np.ndarray,
    side: float,
    axes: tuple[np.ndarray, np.ndarray, np.ndarray] | None = None,
) -> list[float]:
    """Convert the elbow-to-wrist direction into a stable local target.

    The old implementation used total elbow flexion as the forearm yaw. That
    makes a raised forearm look as if it has folded behind the body. The target
    is derived from the actual lower-arm direction in the torso frame: vertical
    motion drives pitch and toward/away motion drives yaw. A straight arm stays
    close to zero, while a 90-degree raised forearm produces a 90-degree pitch
    target.
    """
    direction = safe_normalize(wrist - elbow)
    if axes is None:
        up_axis = np.array((0.0, -1.0, 0.0), dtype=np.float64)
        right_axis = np.array((1.0, 0.0, 0.0), dtype=np.float64)
        front_axis = np.array((0.0, 0.0, -1.0), dtype=np.float64)
    else:
        up_axis, right_axis, front_axis = axes
    up_component = float(np.dot(direction, up_axis))
    outward_component = float(np.dot(direction, right_axis * side))
    front_component = float(np.dot(direction, front_axis))

    # The outward component is the reference direction for a straight arm.
    # Keep a small floor so a vertical forearm cannot create an unstable atan2
    # jump while the person crosses the camera's centre line.
    pitch_reference = max(abs(outward_component), 1e-5)
    yaw_reference = max(abs(outward_component), 0.18)
    pitch = math.degrees(math.atan2(up_component, pitch_reference))
    # Match limb_angles' convention: positive means toward the camera/front.
    # A rearward depth estimate is rejected so the elbow cannot flip behind
    # the torso when MediaPipe briefly swaps its z ordering.
    yaw = math.degrees(math.atan2(front_component, yaw_reference))
    return [clamp(pitch, -110.0, 110.0), clamp(yaw, 0.0, 65.0), 0.0]


def wrist_angles(
    elbow: np.ndarray,
    wrist: np.ndarray,
    index_finger: np.ndarray,
    pinky: np.ndarray,
    side: float,
) -> list[float]:
    """Estimate wrist bend and roll from the forearm and hand landmarks."""
    forearm = safe_normalize(wrist - elbow)
    hand = safe_normalize((index_finger + pinky) * 0.5 - wrist)
    bend = clamp(angle_between(forearm, hand), 0.0, 75.0)
    hand_axis = safe_normalize(pinky - index_finger)
    roll = clamp(math.degrees(math.atan2(hand_axis[1], max(abs(hand_axis[0]), 1e-5))), -60.0, 60.0)
    return [0.0, side * bend, side * roll]


class PoseSmoother:
    def __init__(self, amount: float = 0.6, hold_seconds: float = 0.18, release_seconds: float = 0.24) -> None:
        self.amount = amount
        self.hold_seconds = hold_seconds
        self.release_seconds = release_seconds
        self.values: dict[str, list[float]] = {}
        self.last_seen: dict[str, float] = {}

    @staticmethod
    def smooth_angle(previous: float, current: float, amount: float) -> float:
        delta = (current - previous + 180.0) % 360.0 - 180.0
        return previous + delta * amount

    def apply(self, pose: dict[str, Any]) -> dict[str, Any]:
        now = time.monotonic()
        result: dict[str, Any] = {"tracking": bool(pose.get("tracking"))}
        tracked_parts = pose.get("tracked_parts")
        if isinstance(tracked_parts, list):
            result["tracked_parts"] = tracked_parts
        for key in POSE_KEYS:
            current = pose.get(key)
            if isinstance(current, list) and len(current) == 3:
                previous = self.values.get(key, list(current))
                smoothed = [
                    self.smooth_angle(previous[index], float(current[index]), self.amount)
                    for index in range(3)
                ]
                self.values[key] = smoothed
                self.last_seen[key] = now
                result[key] = [round(value, 4) for value in smoothed]
                continue
            previous = self.values.get(key)
            last_seen = self.last_seen.get(key)
            if previous is None or last_seen is None:
                continue
            age = now - last_seen
            if age <= self.hold_seconds + self.release_seconds:
                factor = 1.0 if age <= self.hold_seconds else max(
                    0.0, 1.0 - (age - self.hold_seconds) / self.release_seconds
                )
                held = [value * factor for value in previous]
                self.values[key] = held
                result[key] = [round(value, 4) for value in held]
        return result


def open_camera(args: argparse.Namespace) -> tuple[Any, np.ndarray, str]:
    """Open and warm up a camera, trying the common Windows backends."""
    if sys.platform == "win32":
        candidates = (
            ("DirectShow", cv2.CAP_DSHOW),
            ("Media Foundation", cv2.CAP_MSMF),
            ("automatic", cv2.CAP_ANY),
        )
    else:
        candidates = (("automatic", cv2.CAP_ANY),)

    attempted: list[str] = []
    for backend_name, backend in candidates:
        attempted.append(backend_name)
        print(f"[Camera] trying camera {args.camera} with {backend_name}...")
        camera = cv2.VideoCapture(args.camera, backend)
        if sys.platform == "win32":
            # Most Windows webcams expose 1080p at useful frame rates through
            # their MJPEG mode. Unsupported cameras simply ignore this hint.
            camera.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        camera.set(cv2.CAP_PROP_FPS, args.fps)
        camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        if camera.isOpened():
            for _ in range(8):
                ok, frame = camera.read()
                if ok and frame is not None and frame.size:
                    return camera, frame, backend_name
                time.sleep(0.08)
        camera.release()
        print(f"[Camera] {backend_name} could not deliver a frame; trying the next backend")

    backends = ", ".join(attempted)
    raise RuntimeError(
        f"cannot open camera {args.camera} (tried {backends}). "
        "Close Camera/OBS/Discord and other programs using the webcam; "
        "then try --camera 1 if Windows has assigned a different camera number"
    )


def create_pose_tracker(args: argparse.Namespace) -> tuple[Any | None, str]:
    """Create MediaPipe Pose, retrying with the light model on failure."""
    if args.no_pose:
        return None, "face + head"

    complexities = [args.pose_complexity]
    if args.pose_complexity != 0:
        complexities.append(0)
    failures: list[str] = []
    for complexity in complexities:
        try:
            print(f"[Pose] loading upper-body model (complexity {complexity})...")
            context = mp.solutions.pose.Pose(
                static_image_mode=False,
                model_complexity=complexity,
                enable_segmentation=False,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            )
            return context, f"upper body / complexity {complexity}"
        except Exception as exc:
            failures.append(f"complexity {complexity}: {exc}")
            print(f"[Pose] model complexity {complexity} failed: {exc}", file=sys.stderr)

    print(
        "[Pose] upper-body tracking is unavailable; continuing in face + head mode.\n"
        "[Pose] Re-run install_player_windows.bat to repair MediaPipe. Details: "
        + " | ".join(failures),
        file=sys.stderr,
    )
    return None, "face + head (Pose unavailable)"


def extract_upper_body(pose_result: Any, head: list[float] | None) -> dict[str, Any]:
    if not pose_result.pose_landmarks:
        return {"tracking": False, **({"head": head} if head else {})}

    landmarks = pose_result.pose_world_landmarks or pose_result.pose_landmarks
    image_landmarks = pose_result.pose_landmarks.landmark
    points = landmarks.landmark
    left_shoulder, right_shoulder = vector(points[11]), vector(points[12])
    left_elbow, right_elbow = vector(points[13]), vector(points[14])
    left_wrist, right_wrist = vector(points[15]), vector(points[16])
    left_index, right_index = vector(points[19]), vector(points[20])
    left_pinky, right_pinky = vector(points[17]), vector(points[18])
    left_hip, right_hip = vector(points[23]), vector(points[24])

    # Visibility is read from the unmirrored image so anatomical left/right
    # labels remain stable across preview mirroring.
    def visible(*indices: int) -> bool:
        return all(float(image_landmarks[index].visibility) >= 0.2 for index in indices)

    # Each channel is checked independently: a temporarily hidden wrist or
    # hip must not prevent a visible arm from updating.
    result: dict[str, Any] = {"tracking": False, "tracked_parts": []}
    tracked_parts: list[str] = result["tracked_parts"]

    if visible(11, 12, 23, 24):
        arm_axes = body_axes(left_shoulder, right_shoulder, left_hip, right_hip)
    elif visible(11, 12):
        arm_axes = body_axes(left_shoulder, right_shoulder)
    else:
        arm_axes = None

    spine = None
    waist = None
    if visible(11, 12, 23, 24):
        shoulder_mid = (left_shoulder + right_shoulder) * 0.5
        hip_mid = (left_hip + right_hip) * 0.5
        pelvis_to_shoulder = safe_normalize(shoulder_mid - hip_mid)
        hip_line = safe_normalize(right_hip - left_hip)
        torso_sway = math.degrees(
            math.atan2(pelvis_to_shoulder[0], max(-pelvis_to_shoulder[1], 0.12))
        )
        waist = [
            clamp(math.degrees(math.atan2(-pelvis_to_shoulder[2], max(-pelvis_to_shoulder[1], 0.12))), -35.0, 35.0),
            clamp(math.degrees(math.atan2(-hip_line[2], max(abs(hip_line[0]), 0.12))), -35.0, 35.0),
            clamp(torso_sway, -30.0, 30.0),
        ]
        result["waist"] = waist
        tracked_parts.append("waist")
    elif visible(11, 12):
        # A desk camera often loses the hips. Shoulder slope still gives a
        # useful, calibrated left/right waist sway instead of disabling the
        # waist channel completely.
        image_left_shoulder = vector(image_landmarks[11])
        image_right_shoulder = vector(image_landmarks[12])
        image_shoulder_line = safe_normalize(image_right_shoulder - image_left_shoulder)
        shoulder_roll = math.degrees(
            math.atan2(image_shoulder_line[1], max(abs(image_shoulder_line[0]), 0.12))
        )
        waist = [0.0, 0.0, clamp(shoulder_roll * 1.35, -30.0, 30.0)]
        result["waist"] = waist
        tracked_parts.append("waist")

    if visible(11, 12, 23, 24):
        shoulder_mid = (left_shoulder + right_shoulder) * 0.5
        hip_mid = (left_hip + right_hip) * 0.5
        torso = safe_normalize(shoulder_mid - hip_mid)
        shoulder_line = safe_normalize(right_shoulder - left_shoulder)
        spine_pitch = math.degrees(math.atan2(-torso[2], max(-torso[1], 1e-5)))
        spine_yaw = math.degrees(
            math.atan2(-shoulder_line[2], max(abs(shoulder_line[0]), 1e-5))
        )
        spine_roll = math.degrees(math.atan2(torso[0], max(-torso[1], 1e-5)))
        spine = [spine_pitch, spine_yaw, spine_roll]
        result["spine"] = spine
        tracked_parts.append("spine")

    if visible(11, 13):
        left_upper = limb_angles(left_shoulder, left_elbow, -1.0, arm_axes)
        result["left_clavicle"] = [
            clamp(left_upper[0] * 0.16, -20.0, 20.0),
            clamp(left_upper[1] * 0.22, -28.0, 28.0),
            0.0,
        ]
        result["left_upper_arm"] = left_upper
        tracked_parts.append("left_clavicle")
        tracked_parts.append("left_upper_arm")
    if visible(11, 13, 15):
        result["left_forearm"] = forearm_angles(
            left_shoulder, left_elbow, left_wrist, -1.0, arm_axes
        )
        tracked_parts.append("left_forearm")
    if visible(13, 15, 19, 17):
        result["left_wrist"] = wrist_angles(left_elbow, left_wrist, left_index, left_pinky, -1.0)
        tracked_parts.append("left_wrist")

    if visible(12, 14):
        right_upper = limb_angles(right_shoulder, right_elbow, 1.0, arm_axes)
        result["right_clavicle"] = [
            clamp(right_upper[0] * 0.16, -20.0, 20.0),
            clamp(right_upper[1] * 0.22, -28.0, 28.0),
            0.0,
        ]
        result["right_upper_arm"] = right_upper
        tracked_parts.append("right_clavicle")
        tracked_parts.append("right_upper_arm")
    if visible(12, 14, 16):
        result["right_forearm"] = forearm_angles(
            right_shoulder, right_elbow, right_wrist, 1.0, arm_axes
        )
        tracked_parts.append("right_forearm")
    if visible(14, 16, 20, 18):
        result["right_wrist"] = wrist_angles(right_elbow, right_wrist, right_index, right_pinky, 1.0)
        tracked_parts.append("right_wrist")

    result["tracking"] = bool(tracked_parts)
    if head:
        result["head"] = head
        result["neck"] = [head[0] * 0.25, head[1] * 0.25, head[2] * 0.2]
    elif spine:
        result["neck"] = [spine[0] * 0.2, spine[1] * 0.2, spine[2] * 0.2]
    return result


class PlayerTrackerServer:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.clients: set[ServerConnection] = set()
        self.last_values = [0.0] * len(BLENDSHAPES)
        self.last_payload: dict[str, Any] = {
            "version": 3,
            "blendshapes": self.last_values,
            "face_tracking": False,
            "pose": {"tracking": False},
        }
        self.pose_smoother = PoseSmoother()

    async def client_handler(self, websocket: ServerConnection) -> None:
        self.clients.add(websocket)
        address = websocket.remote_address
        print(f"[GMod] connected: {address} ({len(self.clients)} client(s))")
        try:
            await websocket.send(json.dumps(self.last_payload, separators=(",", ":")))
            async for _ in websocket:
                pass
        except ConnectionClosed:
            pass
        finally:
            self.clients.discard(websocket)
            print(f"[GMod] disconnected: {address} ({len(self.clients)} client(s))")

    async def broadcast(self, payload: dict[str, Any]) -> None:
        self.last_payload = payload
        if not self.clients:
            return
        encoded = json.dumps(payload, separators=(",", ":"))
        clients = tuple(self.clients)
        results = await asyncio.gather(
            *(client.send(encoded) for client in clients), return_exceptions=True
        )
        for client, result in zip(clients, results):
            if isinstance(result, Exception):
                self.clients.discard(client)

    async def capture_loop(self) -> None:
        # Passing a drive-letter path to MediaPipe 0.10.x can make its native
        # Windows resource loader prepend site-packages (".../site-packages/D:\\...").
        # Supplying the task as bytes avoids that path handling bug entirely.
        model_buffer = self.args.model.read_bytes()
        face_options = mp.tasks.vision.FaceLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_buffer=model_buffer),
            running_mode=mp.tasks.vision.RunningMode.VIDEO,
            num_faces=1,
            output_face_blendshapes=True,
            output_facial_transformation_matrixes=True,
        )
        interval = 1.0 / max(self.args.fps, 1.0)
        timestamp_ms = 0
        measured_fps = 0.0
        previous_frame_at: float | None = None
        pose_context, pose_mode = create_pose_tracker(self.args)
        camera = None
        try:
            camera, pending_frame, backend_name = open_camera(self.args)
            print(
                f"[Camera] opened camera {self.args.camera} with {backend_name} "
                f"at up to {self.args.fps:g} FPS"
            )
            actual_width = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
            actual_height = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
            if actual_width and actual_height:
                print(f"[Camera] active capture size: {actual_width}x{actual_height}")
            print(f"[Tracking] face + head + {pose_mode}")
            print("[Camera] keep head, shoulders, elbows and wrists visible; press Q or Ctrl+C to stop")

            with mp.tasks.vision.FaceLandmarker.create_from_options(face_options) as landmarker:
                if self.args.preview:
                    window_flags = cv2.WINDOW_NORMAL
                    if hasattr(cv2, "WINDOW_KEEPRATIO"):
                        window_flags |= cv2.WINDOW_KEEPRATIO
                    cv2.namedWindow(WINDOW_TITLE, window_flags)
                    source_width = actual_width or pending_frame.shape[1]
                    source_height = actual_height or pending_frame.shape[0]
                    preview_width = min(source_width, 1280)
                    preview_height = max(360, round(preview_width * source_height / source_width))
                    cv2.resizeWindow(
                        WINDOW_TITLE,
                        preview_width,
                        preview_height,
                    )
                inference_workers = 2 if pose_context else 1
                with ThreadPoolExecutor(
                    max_workers=inference_workers,
                    thread_name_prefix="facetracker-inference",
                ) as inference_pool:
                  while True:
                    started = time.perf_counter()
                    if pending_frame is not None:
                        frame = pending_frame
                        pending_frame = None
                        ok = True
                    else:
                        ok, frame = camera.read()
                    if not ok:
                        print("[Camera] failed to read a frame; retrying")
                        await asyncio.sleep(0.1)
                        continue

                    # Keep Pose on the original camera image so MediaPipe's
                    # anatomical left/right labels stay stable. Mirror only
                    # the face input and final preview window.
                    raw_frame = frame
                    tracking_frame = resize_for_tracking(raw_frame, self.args.processing_width)
                    # One conversion is shared by both models. Mirroring the
                    # already-converted RGB array avoids a second full-frame
                    # BGR->RGB pass on every camera frame.
                    pose_rgb = cv2.cvtColor(tracking_frame, cv2.COLOR_BGR2RGB)
                    rgb = cv2.flip(pose_rgb, 1) if not self.args.no_mirror else pose_rgb
                    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                    timestamp_ms = max(timestamp_ms + 1, int(time.monotonic() * 1000))
                    # Face and body models are independent. Run them in
                    # parallel so total frame time is approximately the
                    # slower model, rather than face time + pose time.
                    face_future = inference_pool.submit(
                        landmarker.detect_for_video, image, timestamp_ms
                    )
                    pose_future = (
                        inference_pool.submit(pose_context.process, pose_rgb)
                        if pose_context
                        else None
                    )
                    face_result = face_future.result()
                    pose_result = None
                    if pose_future:
                        try:
                            pose_result = pose_future.result()
                        except Exception as exc:
                            print(
                                f"[Pose] processing failed; continuing in face + head mode: {exc}",
                                file=sys.stderr,
                            )
                            if pose_context:
                                pose_context.close()
                            pose_context = None
                            pose_mode = "face + head (Pose unavailable)"

                    face_tracking = bool(face_result.face_blendshapes)
                    if face_tracking:
                        scores = {
                            category.category_name: float(category.score)
                            for category in face_result.face_blendshapes[0]
                        }
                        self.last_values = [scores.get(name, 0.0) for name in BLENDSHAPES]
                    else:
                        self.last_values = [0.0] * len(BLENDSHAPES)

                    head = None
                    if face_result.facial_transformation_matrixes:
                        head = matrix_euler_degrees(face_result.facial_transformation_matrixes[0])
                    if pose_result:
                        pose = extract_upper_body(pose_result, head)
                    else:
                        pose = {"tracking": bool(head), **({"head": head} if head else {})}
                    pose = self.pose_smoother.apply(pose)

                    await self.broadcast(
                        {
                            "version": 3,
                            "blendshapes": self.last_values,
                            "face_tracking": face_tracking,
                            "pose": pose,
                        }
                    )

                    if self.args.preview:
                        preview_frame = resize_for_tracking(raw_frame, 960)
                        if pose_result and pose_result.pose_landmarks:
                            preview_frame = preview_frame.copy()
                            mp.solutions.drawing_utils.draw_landmarks(
                                preview_frame,
                                pose_result.pose_landmarks,
                                mp.solutions.pose.POSE_CONNECTIONS,
                            )
                            frame = cv2.flip(preview_frame, 1) if not self.args.no_mirror else preview_frame
                        else:
                            frame = cv2.flip(preview_frame, 1) if not self.args.no_mirror else preview_frame
                        frame_at = time.perf_counter()
                        frame_interval = max(frame_at - previous_frame_at, 1e-6) if previous_frame_at else interval
                        previous_frame_at = frame_at
                        instant_fps = 1.0 / frame_interval
                        measured_fps = instant_fps if measured_fps <= 0 else measured_fps * 0.9 + instant_fps * 0.1
                        face_label = "face" if face_tracking else "no face"
                        if pose_context:
                            body_count = sum(key in pose for key in UPPER_BODY_KEYS)
                            pose_label = (
                                f"body {body_count}/{len(UPPER_BODY_KEYS)}"
                                if body_count
                                else "show shoulders + arms"
                            )
                        else:
                            pose_label = "face + head"
                        color = (60, 220, 60) if face_tracking else (40, 40, 230)
                        cv2.putText(
                            frame,
                            f"Chacha Capture | {face_label} | {pose_label} | {measured_fps:.1f} FPS",
                            (15, 35),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.7,
                            color,
                            2,
                        )
                        cv2.imshow(WINDOW_TITLE, frame)
                        if cv2.waitKey(1) & 0xFF in (ord("q"), ord("Q")):
                            return

                    remaining = interval - (time.perf_counter() - started)
                    await asyncio.sleep(max(remaining, 0.0))
                  # The executor is scoped to the capture loop so it shuts
                  # down cleanly when Q/Ctrl+C stops the tracker.
        finally:
            if pose_context:
                pose_context.close()
            if camera:
                camera.release()
            cv2.destroyAllWindows()

    async def run(self) -> None:
        if not self.args.model.is_file():
            raise FileNotFoundError(f"MediaPipe model not found: {self.args.model}")
        async with serve(
            self.client_handler,
            "127.0.0.1",
            self.args.port,
            max_queue=1,
            compression=None,
        ):
            print(f"[Server] ws://127.0.0.1:{self.args.port} (Chacha Capture protocol)")
            print("[Privacy] bound to this PC only; camera images are never transmitted")
            await self.capture_loop()


def main() -> int:
    args = parse_args()
    if args.list_cameras:
        return list_cameras(args.camera_scan_count)
    try:
        asyncio.run(PlayerTrackerServer(args).run())
    except KeyboardInterrupt:
        print("\n[Server] stopped")
    except Exception as exc:
        if isinstance(exc, OSError) and (
            getattr(exc, "winerror", None) == 10048
            or getattr(exc, "errno", None) in (48, 98)
        ):
            print(
                "\n[Error] WebSocket port 8667 is already in use. Close every other "
                "Chacha Capture windows, then restart this program.",
                file=sys.stderr,
            )
        else:
            print(f"\n[Error] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
