#!/usr/bin/env python3
"""Settings -> About names the hardware it reads, and sizes it right.

`cpuName`/`gpuName` turn /proc/cpuinfo and lspci/nvidia-smi strings into what a
spec sheet says, and `bytes` formats RAM and disk. A wrong regex here has no
symptom beyond a tile that reads oddly on someone else's machine, so they are
lifted out of About.qml and run under node against real strings.
"""
import json, pathlib, re, subprocess, sys

qml = (pathlib.Path(__file__).resolve().parent.parent
       / "dots/.config/quickshell/ii/modules/settings/About.qml").read_text()
body = re.search(r"\n    function cpuName.*?\n    }\n    function gpuName.*?\n    }\n    function bytes.*?\n    }\n", qml, re.S)
assert body, "cpuName/gpuName/bytes not found in About.qml"

cases = {
    "cpuName": [
        ("11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz", "11th Gen Intel Core i7-1185G7"),
        ("AMD Ryzen 7 7840HS w/ Radeon 780M Graphics", "AMD Ryzen 7 7840HS w/ Radeon 780M Graphics"),
        ("AMD Ryzen 9 5900X 12-Core Processor", "AMD Ryzen 9 5900X"),
        ("Intel(R) Core(TM) Ultra 7 155H", "Intel Core Ultra 7 155H"),
        ("--", "Unknown"),
    ],
    "gpuName": [
        ("Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] (rev 01)", "Intel Iris Xe Graphics"),
        ("NVIDIA GeForce RTX 4060 Laptop GPU", "NVIDIA GeForce RTX 4060 Laptop GPU"),
        ("NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q / Mobile] (rev a1)", "NVIDIA GeForce RTX 4060 Max-Q / Mobile"),
        ("Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1 (rev c4)", "AMD Phoenix1"),
        ("Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XT/7900 XTX] (rev c8)", "AMD Radeon RX 7900 XT/7900 XTX"),
        ("--", "Unknown"),
        ("", "Unknown"),
    ],
    "bytes": [
        (16 * 1024 ** 3, "16.0 GB"),
        (15.3 * 1024 ** 3, "15.3 GB"),
        (476.9 * 1024 ** 3, "477 GB"),
        (1.8 * 1024 ** 4, "1.8 TB"),
    ],
}
js = ("const Translation = { tr: s => s };\n" + body.group(0) +
      f"\nconst cases = {json.dumps(cases)};\n"
      "const out = {};\n"
      "for (const [fn, list] of Object.entries(cases)) out[fn] = list.map(([i]) => eval(fn)(i));\n"
      "console.log(JSON.stringify(out));")
got = json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)

bad = [f"{fn}({i!r}) = {g!r}, want {w!r}"
       for fn, list_ in cases.items() for (i, w), g in zip(list_, got[fn]) if g != w]
if bad:
    print("check-about: FAIL\n  " + "\n  ".join(bad))
    sys.exit(1)
print("check-about: ok")
