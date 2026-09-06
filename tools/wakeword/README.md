# Training the Scout wake words

The shell detects the wake phrase with three chained ONNX models. Two of them —
`melspectrogram.onnx` and `embedding_model.onnx` — are openWakeWord's shared
frontend and are downloaded automatically; they are never trained. Only the last
one, a ~1MB classifier, is per-phrase, and that is what this directory builds.

Three are built in one run: **"hey scout"**, **"okay scout"** and **"scout"**.
Doing them together is close to free — the expensive parts of training (fetching
the negative feature set, the impulse responses, the noise corpus) are shared,
and only the sample generation and the final fit are per-phrase.

## Where to run it

**Colab, free GPU tier.** This is not a preference, it is what the job needs:
generating tens of thousands of synthetic speech samples is GPU work, and on a
CPU-only machine the same run is an overnight job rather than a coffee break.
`train_scout.ipynb` is written for Colab and is run-all.

Expect roughly 75–90 minutes for all three phrases.

## Steps

1. Open `train_scout.ipynb` in Colab.
2. **Runtime → Change runtime type → T4 GPU.** Skipping this is the single most
   common way to end up with a run that never finishes.
3. Runtime → Run all.
4. At the end it zips the three `.onnx` files. Download and unpack them into
   `~/.local/share/vynx-conduit/wakeword/`.
5. Settings → Services → Conduit → Wake word, pick a phrase, turn it on.

The filenames matter: the shell looks for `hey_scout.onnx`, `okay_scout.onnx`
and `scout.onnx`, as listed in `phrases.json` and in `wakePhrasePresets` in
`services/ConduitService.qml`. Those two lists are not linked to each other, so
if you rename a phrase, rename it in both.

## If a training stage fails

The training cell captures stderr and prints it, then stops rather than letting
the later phrases fail the same way. Ones already hit and fixed:

| Symptom | Cause |
|---|---|
| `ModuleNotFoundError: No module named 'openwakeword'` | `speexdsp-ns` has no wheel past cp312, so the install silently failed. The 3.11 env fixes it |
| `ValueError: Key backend: 'module://matplotlib_inline...'` | Colab exports `MPLBACKEND` pointing at its own inline shim, which does not exist in the venv. `torchmetrics` imports matplotlib and dies. Fixed by `MPLBACKEND=Agg` |
| `tar: This does not look like a tar archive` | An HTTP 404 error page saved as a `.tar`. The AudioSet path moved; no longer used |
| A stage fails with no output at all | An earlier cell died. Check the voice model downloaded — the model cell now fails loudly if not |

To fix `MPLBACKEND` in an already-running session without losing the downloads,
run `import os; os.environ['MPLBACKEND'] = 'Agg'` in a new cell and re-run the
training cell — `subprocess` inherits the kernel environment.

## Then tune the threshold, with measurements

A wake word that has never been measured is a wake word that answers the
television. `wakeword.py` scores a recording offline so you can see the numbers
instead of guessing at them:

```sh
VENV=~/.local/state/quickshell/.venv/bin/python
SCRIPT=~/.config/quickshell/ii/scripts/wakeword/wakeword.py
MODELS=~/.local/share/vynx-conduit/wakeword

# Record yourself saying it a few times, with pauses.
pw-record --rate 16000 --channels 1 --format s16 me.wav   # Ctrl-C when done

# What does a real utterance score?
$VENV $SCRIPT --wav me.wav --model "hey_scout=$MODELS/hey_scout.onnx:0.1"

# And what does half an hour of speech that isn't the phrase score?
$VENV $SCRIPT --wav podcast.wav --model "hey_scout=$MODELS/hey_scout.onnx:0.1"
```

Set the threshold between the two peaks. If they overlap, the model needs more
training data rather than a cleverer threshold — raise `n_samples` and `steps`
in `phrases.json` and run the notebook again.

`--replay` runs the whole live loop against a WAV instead of the microphone, so
you can check detection, capture and endpointing together without speaking:

```sh
$VENV $SCRIPT --replay me.wav --model "hey_scout=$MODELS/hey_scout.onnx:0.5"
```

## Why the notebook builds its own Python

Not incidental — without this the run cannot work at all.

`piper-phonemize` (turns the phrase into phonemes so it can be spoken) and
`speexdsp-ns` (a hard dependency of `openwakeword` on Linux) publish wheels only
up to **cp312**. Colab now runs Python 3.13. On 3.13 `pip install openwakeword`
fails outright, and every training run then dies with:

```
ModuleNotFoundError: No module named 'openwakeword'
```

which is misleading — the package was never installed, so the nine identical
tracebacks are fallout, not nine problems.

Pinning versions does not help; the wheels do not exist for 3.13. So the
notebook builds a **Python 3.11 environment with `uv`** and runs everything
inside it, leaving Colab's own kernel alone. Verified locally: on 3.13 uv reports
`no wheels with a matching Python ABI tag (cp313)`; on 3.11 both packages install
and `import openwakeword` succeeds.

If Colab ever ships a Python that breaks this again, the fix is the same shape —
change `--python 3.11` in the setup cell to whatever the newest version is that
`piper-phonemize` publishes wheels for.

## Why the data prep does not use `datasets`

Upstream's notebook fetches its augmentation data through the `datasets`
library. All three of those paths have since broken, so this notebook uses plain
HTTP and `ffmpeg` instead:

| Upstream source | What happened |
|---|---|
| AudioSet `data/bal_train09.tar` | The repo was converted to parquet; the `.tar` URL 404s. `wget` saves the 15-byte error page and `tar` reports *"This does not look like a tar archive"* |
| FMA (`rudraml/fma`) | It is a loading script, and `datasets` 4+ removed script support |
| `datasets` audio decoding | 4/5 return an `AudioDecoder` object rather than a dict with `'array'`, and need `torchcodec` installed to decode at all |

So background noise now comes from **ESC-50** — one zip, 2000 plain wavs — and
the impulse responses are downloaded directly from the same MIT set upstream
uses, listed via the HF tree API. `openwakeword` itself never imports `datasets`
(checked in `data.py` and `train.py`), so dropping it costs nothing.

Both are converted to 16kHz mono 16-bit with `ffmpeg`, which is what training
expects — the MIT files are 24-bit and ESC-50 is 44.1kHz.

## Other things about the notebook

It follows openWakeWord's official training flow, adapted to build three phrases
in one pass and to export **ONNX only**. The shell has no use for the tflite
output, and skipping it avoids the `tensorflow==2.8.1` / `onnx_tf` pins, which are
the other fragile part of upstream's notebook. `train.py` imports those inside its
tflite path only, so leaving them out is safe as long as `--convert_to_tflite` is
never passed — it isn't.

Each training stage is checked before the next runs. Upstream's notebook lets a
failed stage fall through, which is how one broken install becomes nine
tracebacks and no models; this stops at the first real failure.

The training run itself has **not** been executed from this repo — there is no
GPU on the machine it was written on. The dependency resolution above was tested
locally; the training maths is upstream's.

## Testing before any of this

`hey_jarvis` is openWakeWord's own pretrained model and needs no training. It is
deliberately absent from the settings UI — the assistant is called Scout — but
setting `conduit.wakeWord.phrase` to `"hey_jarvis"` in
`~/.config/illogical-impulse/config.json` by hand will exercise the entire
pipeline, which is useful for confirming the microphone, the capture and the
spoken reply all work before committing to a training run.
