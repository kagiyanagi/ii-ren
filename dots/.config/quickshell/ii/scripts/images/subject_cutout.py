#!/usr/bin/env python3
"""Cut the salient subject out of a wallpaper.

A still wallpaper becomes an RGBA PNG. A video wallpaper becomes a *packed*
video: every frame is the original stacked on top of its own alpha matte, at
double height. One file, so the shell decodes it once and the matte can never
drift out of sync with the frame it belongs to - which is the whole reason this
is not simply a second video playing alongside the first.

This is the Linux stand-in for the ML Kit Subject Segmentation API that Iconify
and the depth-wallpaper ROMs call: same contract, same output. Give it an image,
get back a same-sized picture holding only the foreground subject with a soft
alpha edge, which the shell then draws on top of the desktop widgets so the
clock tucks in behind someone's shoulder.

ML Kit ships a trained model on device; there is no equivalent here, so the
model is ISNet (DIS general-use), fetched once and run through onnxruntime on
the CPU. Its raw mask is good but soft along hair and fur, so it gets refined
against the image itself with a guided filter before it becomes alpha - the
usual matting cleanup, and the reason edges hold up at wallpaper resolution.

Video runs the same model, which is not obvious: ISNet costs seconds a frame,
so matting a ten-second loop honestly would take twenty minutes. It does not,
because a wallpaper loop barely moves. The matte is only recut when the frame
has actually changed enough to deserve it, which on ambient footage is a few
percent of frames - measured, the model runs 38 times over 309 frames. A video
that genuinely moves pays full price, which is the right way round.

RobustVideoMatting was tried here first and dropped. It is twelve times faster
and purpose-built for video, but it is trained on real human footage: on
stylised art it locates the subject and then refuses to commit to it, returning
a median alpha of 0.54 where ISNet returns 1.0. A ghost, accurately placed.

A finished cutout is reused: re-running with the same pair is a no-op unless
the wallpaper is newer than it, or --force is passed. The shell leans on that
and simply asks for the cutout every time the wallpaper changes.

Usage:
    subject_cutout.py --image <path> --output <path.png> [--json] [--force]
    subject_cutout.py --image <path.mp4> --output <path.mp4> [--json] [--force]
    subject_cutout.py --self-check
"""

import argparse
import fcntl
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import cv2
import numpy as np

# ISNet general-use, the model rembg exposes under the same name. 176MB, 1024²
# input, and the most accurate salient-object net that still runs in a couple of
# seconds on a laptop CPU.
# ponytail: one model, no picker. BiRefNet scores higher on fine structures but
# is ~1GB and an order of magnitude slower on CPU; swap MODEL_URL/MODEL_SIZE if
# that trade ever looks worth it.
MODEL_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx"
MODEL_SHA256 = "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a"
MODEL_SIZE = 1024

VIDEO_SUFFIXES = {".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".ogv"}

# How far a frame has to drift from the last one that was actually cut before it
# earns a fresh cut of its own: mean absolute difference, 0-255, over a small
# grey proxy. At 0.5 an ambient loop recuts every dozen frames or so, and
# reusing a matte that long was measured to leave 0.2% of pixels off by more
# than a fifth - along edges, invisible. A video that really moves crosses the
# threshold every frame and simply pays, which is the right way round.
KEYFRAME_DIFF = 0.5
PROXY_SIZE = (256, 144)

# The mask is a confidence field, not a stencil. Everything below LO is
# background, everything above HI is subject, and the band between them is
# rescaled into a real gradient - which is what keeps a one-pixel soft edge
# instead of either a hard staircase or a wide grey halo.
ALPHA_LO = 0.30
ALPHA_HI = 0.70

# Kept blobs must clear both bars: a floor share of the frame, and a share of
# the biggest subject found. The relative one is what does the real work - on a
# busy wallpaper (chalk on a blackboard, leaves, text) the net lights up dozens
# of tiny high-confidence specks, and any absolute threshold either keeps them
# or eats a genuinely small second subject. Measured against the main subject
# they are obviously debris, and a distant second person still is not.
MIN_BLOB_FRACTION = 0.0008
MIN_BLOB_SHARE_OF_LARGEST = 0.05


def write_status(output: Path, payload: dict) -> None:
    """Publish progress next to the cutout, for anyone who wants to watch.

    Progress on stdout only reaches whoever spawned this run. The settings
    window is usually not that process - it asks for the same cutout, blocks on
    the lock, and would otherwise have nothing to show for the whole bake. A
    file beside the output is readable by every window at once.
    """
    path = output.with_suffix(output.suffix + ".status")
    partial = path.with_suffix(f".status.{os.getpid()}")
    payload = dict(payload, pid=os.getpid())
    try:
        partial.write_text(json.dumps(payload))
        partial.replace(path)
    except OSError:
        pass  # progress reporting must never take the bake down with it


def sweep_dead_partials(directory: Path) -> None:
    """Drop temp files whose writer is gone.

    A bake that is cancelled - by a wallpaper change, or by being killed -
    leaves megabytes of half-written video behind, and it is never for the
    wallpaper being made next, so cleaning only the current output would let
    them pile up. The pid is in the name, so a live writer is easy to spare.
    """
    def dead(pid) -> bool:
        try:
            os.kill(int(pid), 0)
        except (ValueError, TypeError, ProcessLookupError):
            return True
        except PermissionError:
            return False  # alive, just not ours to signal
        return False

    for stale in directory.glob("*.part*"):
        if dead(stale.name.rsplit(".part", 1)[-1].split(".")[0]):
            stale.unlink(missing_ok=True)

    # A status file left saying "working" by a bake that was killed would show
    # a progress bar for a bake nobody is running. Only that case: a finished
    # one is a result worth keeping.
    for stale in directory.glob("*.status"):
        try:
            state = json.loads(stale.read_text())
        except (OSError, ValueError):
            continue
        if state.get("state") == "working" and dead(state.get("pid")):
            stale.unlink(missing_ok=True)


class OutputLock:
    """One bake per output file, across every process that asks for it.

    The shell and the settings app are separate processes with a singleton
    each, so both kick off a bake on the same wallpaper - and a shell reload
    adds a third. They were writing the same temp file at once, which corrupts
    the result and triples the CPU for it. Whoever gets here second waits, then
    finds the cutout already made and returns it from cache.
    """

    def __init__(self, output: Path):
        self.path = output.with_suffix(output.suffix + ".lock")
        self.handle = None

    def __enter__(self, on_wait=None):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = open(self.path, "w")
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            # Someone else is already making this one. Say so before blocking:
            # the waiter is usually the settings window, which otherwise sits
            # on "reading the video" for the whole bake it is not doing.
            if on_wait is not None:
                on_wait()
            fcntl.flock(self.handle, fcntl.LOCK_EX)
        return self

    def __exit__(self, *_):
        fcntl.flock(self.handle, fcntl.LOCK_UN)
        self.handle.close()
        return False


def is_video(path: Path) -> bool:
    return path.suffix.lower() in VIDEO_SUFFIXES


def cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "quickshell" / "models"


def fetch_model(log) -> Path:
    path = cache_dir() / "isnet-general-use.onnx"
    if path.exists() and path.stat().st_size > 0:
        return path

    import requests

    log("downloading model")
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(".onnx.part")
    digest = hashlib.sha256()
    with requests.get(MODEL_URL, stream=True, timeout=60) as response:
        response.raise_for_status()
        with open(partial, "wb") as handle:
            for chunk in response.iter_content(chunk_size=1 << 20):
                digest.update(chunk)
                handle.write(chunk)

    if digest.hexdigest() != MODEL_SHA256:
        partial.unlink(missing_ok=True)
        raise RuntimeError("model download is corrupt (checksum mismatch)")

    partial.replace(path)
    return path


def run_model(model_path: Path, image: np.ndarray) -> np.ndarray:
    """Return a float mask in [0, 1] at the model's own resolution."""
    import onnxruntime

    options = onnxruntime.SessionOptions()
    options.log_severity_level = 3
    session = onnxruntime.InferenceSession(
        str(model_path), options, providers=["CPUExecutionProvider"]
    )

    resized = cv2.resize(image, (MODEL_SIZE, MODEL_SIZE), interpolation=cv2.INTER_AREA)
    # ISNet wants 0..1 scaled by its own mean/std, then CHW with a batch axis.
    tensor = resized.astype(np.float32) / 255.0
    tensor = (tensor - 0.5) / 1.0
    tensor = np.expand_dims(tensor.transpose(2, 0, 1), 0)

    name = session.get_inputs()[0].name
    prediction = session.run(None, {name: tensor})[0][0][0]

    # The net's output range drifts per image; normalising it is part of the
    # reference implementation, not a fudge.
    low, high = float(prediction.min()), float(prediction.max())
    if high - low < 1e-6:
        return np.zeros_like(prediction)
    return (prediction - low) / (high - low)


def refine(mask: np.ndarray, image: np.ndarray) -> np.ndarray:
    """Snap the mask onto the real edges of the image and clean up speckle."""
    height, width = image.shape[:2]
    mask = cv2.resize(mask, (width, height), interpolation=cv2.INTER_LINEAR)

    # Guided filter, guided by the wallpaper itself: the classic edge-aware
    # feathering step from He et al., which is what pulls the mask onto hair and
    # fur that the net only approximates. Radius scales with the image so a 4K
    # wallpaper gets the same treatment a 1080p one does.
    #
    # The guide has to be float in the same 0..1 range as the mask. Handing it
    # the uint8 image instead does not raise - it silently returns values in the
    # thousands, which then clip to a hard-edged stencil and quietly cost you
    # every soft edge the filter was added for.
    radius = max(4, int(round(min(height, width) * 0.006)))
    mask = cv2.ximgproc.guidedFilter(
        guide=(image.astype(np.float32) / 255.0),
        src=mask.astype(np.float32),
        radius=radius,
        eps=1e-6,
    )

    mask = np.clip((mask - ALPHA_LO) / (ALPHA_HI - ALPHA_LO), 0.0, 1.0)

    # ML Kit returns a set of subjects; anything tiny here is a misfire, and one
    # stray blob in a corner reads as dirt on the screen.
    solid = (mask > 0.5).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    if count > 1:
        areas = stats[1:, cv2.CC_STAT_AREA]
        minimum = max(
            MIN_BLOB_FRACTION * height * width,
            MIN_BLOB_SHARE_OF_LARGEST * float(areas.max()),
        )
        keep = np.concatenate([[False], areas >= minimum])
        if keep.any():
            mask *= keep[labels]

    return mask


def bake_video(source: Path, output: Path, log, progress) -> float:
    """Write a packed video: each frame over its own matte, at double height.

    Packing is what removes the sync problem rather than managing it. Two files
    playing side by side are two clocks, and a matte a few frames off its own
    frame shows up immediately as the subject sliding out of its silhouette.
    One file cannot drift from itself.
    """
    import subprocess

    capture = cv2.VideoCapture(str(source))
    if not capture.isOpened():
        raise RuntimeError(f"cannot open video: {source}")

    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    expected = int(capture.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
    if width <= 0 or height <= 0:
        raise RuntimeError(f"video has no usable frame size: {source}")

    model_path = fetch_model(log)
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_suffix(f".part{os.getpid()}" + output.suffix)
    encoder = subprocess.Popen(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "bgr24",
            "-s", f"{width}x{height * 2}", "-r", f"{fps}",
            "-i", "-",
            # yuv420p so the compositor can hardware-decode it. The matte lives
            # in luma, which 4:2:0 keeps at full resolution - it is only chroma
            # that gets halved, and a grey matte has none worth keeping. Full
            # range matters more: on limited range true black becomes 16, and
            # the whole frame would ghost over the desktop at alpha 6%.
            "-c:v", "libx264", "-crf", "16", "-preset", "veryfast",
            "-pix_fmt", "yuv420p", "-color_range", "pc", "-an",
            str(partial),
        ],
        stdin=subprocess.PIPE,
    )

    mask = None
    keyframe = None
    coverages = []
    frames = 0
    cuts = 0
    started = time.monotonic()
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break

            proxy = cv2.cvtColor(
                cv2.resize(frame, PROXY_SIZE, interpolation=cv2.INTER_AREA),
                cv2.COLOR_BGR2GRAY,
            ).astype(np.float32)

            if mask is None or float(np.abs(proxy - keyframe).mean()) > KEYFRAME_DIFF:
                mask = refine(run_model(model_path, frame), frame)
                keyframe = proxy
                cuts += 1
                coverages.append(coverage(mask))

            matte = np.repeat(
                np.rint(mask * 255).astype(np.uint8)[:, :, None], 3, axis=2
            )
            encoder.stdin.write(np.vstack([frame, matte]).tobytes())

            frames += 1
            # A video that really moves recuts every frame, and that is minutes
            # per hundred frames. Saying so beats leaving it looking hung.
            if frames % 15 == 0:
                elapsed = time.monotonic() - started
                remaining = (expected - frames) * (elapsed / frames) if expected > frames else 0
                progress(frames, expected, cuts, remaining)
    finally:
        capture.release()
        encoder.stdin.close()
        if encoder.wait() != 0:
            partial.unlink(missing_ok=True)
            raise RuntimeError("ffmpeg failed to encode the packed video")

    if frames == 0:
        partial.unlink(missing_ok=True)
        raise RuntimeError(f"video decoded no frames: {source}")

    log(f"cut {cuts} of {frames} frames")
    partial.replace(output)
    # The median, not the mean: one frame where the subject walks off frame
    # should not decide whether this wallpaper has a subject at all.
    return float(np.median(coverages))


def coverage(mask: np.ndarray) -> float:
    return float((mask > 0.5).mean())


def cached_coverage(output: Path, video: bool):
    """Re-measure a finished cutout, or None if it is not readable after all."""
    if video:
        capture = cv2.VideoCapture(str(output))
        ok, frame = capture.read()
        capture.release()
        if not ok or frame.shape[0] % 2 != 0:
            return None
        matte = frame[frame.shape[0] // 2:, :, 0].astype(np.float32) / 255.0
        return coverage(matte)

    cached = cv2.imread(str(output), cv2.IMREAD_UNCHANGED)
    if cached is None or cached.ndim != 3 or cached.shape[2] != 4:
        return None
    return coverage(cached[:, :, 3].astype(np.float32) / 255.0)


def self_check() -> int:
    """Exercise refine() on a synthetic frame. No model, no download."""
    rng = np.random.default_rng(0)
    height, width = 400, 600
    image = np.full((height, width, 3), 30, dtype=np.uint8)
    cv2.rectangle(image, (200, 100), (400, 300), (220, 220, 220), -1)  # the subject
    cv2.rectangle(image, (20, 20), (34, 34), (200, 200, 200), -1)      # a speck
    # Faint texture, the way a photo of a smooth wall is never quite flat. It is
    # what makes the local variance small-but-nonzero, which is where a guided
    # filter goes wrong if its guide is not on the mask's scale.
    image = np.clip(
        image.astype(np.int16) + rng.integers(-1, 2, (height, width, 3)), 0, 255
    ).astype(np.uint8)

    # Blurred, the way the net's own output is: confident in the middle, vague
    # for a dozen pixels either side of the edge. Pulling that vagueness back
    # onto the real edge is the whole job of refine().
    mask = np.zeros((height, width), dtype=np.float32)
    mask[100:300, 200:400] = 1.0
    mask[20:34, 20:34] = 1.0
    mask = cv2.GaussianBlur(mask, (0, 0), 6)

    refined = refine(mask.copy(), image)

    assert refined[200, 300] > 0.9, "subject interior must stay opaque"
    assert refined[350, 500] < 0.1, "background must stay clear"
    assert refined[26, 26] < 0.1, "speck should be dropped as debris"

    # A real gradient along the border, not a staircase. The guide has to be
    # scaled into the mask's 0..1 range for this: hand guidedFilter the raw
    # uint8 image instead and it silently returns values in the thousands,
    # which clip straight to a hard stencil - it still looks plausible, and
    # only the width of this band shows the feathering is gone.
    soft = float(((refined > 0.02) & (refined < 0.98)).mean())
    assert soft > 0.008, f"edge collapsed to a stencil ({soft:.4f} soft pixels)"

    # A subject filling the frame carries no depth, and coverage is how the
    # shell is told so.
    assert 0.1 < coverage(refined) < 0.2, f"coverage off: {coverage(refined)}"

    print("self-check ok")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image")
    parser.add_argument("--output")
    parser.add_argument("--json", action="store_true", help="report on stdout as JSON")
    parser.add_argument("--force", action="store_true", help="ignore a cached cutout")
    parser.add_argument("--self-check", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.self_check:
        return self_check()
    if not args.image or not args.output:
        parser.error("--image and --output are required")

    messages = []

    def log(message):
        messages.append(message)
        if not args.json:
            print(message, file=sys.stderr)

    def waiting():
        if args.json:
            print(json.dumps({"progress": {"waiting": True}}), flush=True)

    def progress(done, total, cuts, remaining):
        payload = {"state": "working", "frames": done, "total": total,
                   "cuts": cuts, "eta": round(remaining)}
        write_status(Path(args.output), payload)
        if not args.json:
            print(f"matted {done}/{total or '?'} frames, {cuts} cuts", file=sys.stderr)

    lock = OutputLock(Path(args.output))
    held = False
    try:
        source = Path(args.image)
        output = Path(args.output)
        if not source.exists():
            raise RuntimeError(f"no such image: {source}")

        video = is_video(source)

        # Everything past here is serialised per output file. The second caller
        # blocks, and by the time it gets in the cutout is made and the cache
        # check below simply hands it back.
        lock.__enter__(on_wait=waiting)
        held = True

        sweep_dead_partials(output.parent)

        fresh = output.exists() and output.stat().st_mtime >= source.stat().st_mtime

        if not args.force and fresh:
            found = cached_coverage(output, video)
            if found is not None:
                cached = {"ok": True, "output": str(output),
                          "coverage": round(found, 4), "cached": True}
                write_status(output, dict(cached, state="done"))
                if args.json:
                    print(json.dumps(cached))
                return 0

        if video:
            write_status(output, {"state": "working", "frames": 0, "total": 0,
                                  "cuts": 0, "eta": 0})
            found = bake_video(source, output, log, progress)
            result = {"ok": True, "output": str(output), "coverage": round(found, 4),
                      "cached": False}
            write_status(output, dict(result, state="done"))
            if args.json:
                print(json.dumps(result))
            return 0

        image = cv2.imread(str(source), cv2.IMREAD_COLOR)
        if image is None:
            raise RuntimeError(f"cannot read image: {source}")

        model_path = fetch_model(log)
        mask = refine(run_model(model_path, image), image)
        found = coverage(mask)

        cutout = np.dstack([image, np.rint(mask * 255).astype(np.uint8)])
        output.parent.mkdir(parents=True, exist_ok=True)
        # Written aside and moved into place, so a reader never catches a half
        # written PNG and caches a broken cutout.
        partial = output.with_suffix(f".part{os.getpid()}.png")
        cv2.imwrite(str(partial), cutout, [cv2.IMWRITE_PNG_COMPRESSION, 6])
        partial.replace(output)

        result = {"ok": True, "output": str(output), "coverage": round(found, 4),
                  "cached": False}
    except Exception as error:  # noqa: BLE001 - the caller only gets stdout
        result = {"ok": False, "error": str(error)}
    finally:
        if held:
            lock.__exit__()

    write_status(Path(args.output),
                 dict(result, state="done") if result["ok"]
                 else {"state": "error", "error": result["error"]})

    if args.json:
        print(json.dumps(result))
    elif not result["ok"]:
        print(result["error"], file=sys.stderr)

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
