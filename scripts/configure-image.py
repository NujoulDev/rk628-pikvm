#!/usr/bin/env python3
import re
import sys
from pathlib import Path

import yaml


def merge(base, update):
    for key, value in update.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value


root, config = map(Path, sys.argv[1:3])
board = sys.argv[3]
overlay, audio_device = {
    "pi4": ("rk628-pi4,audio", "/dev/kvmd-video"),
    "pi5": ("rk628-pi5,cam1,audio", "/dev/rk628-subdev"),
}[board]

boot = root / "boot/config.txt"
boot_settings = re.sub(
    r"^\s*(?:dtoverlay\s*=\s*(?:tc358743(?:-audio)?|rk628-pi[45])(?=[,\s#]|$)"
    r"|camera_auto_detect\s*=).*$\n?",
    "",
    boot.read_text(),
    flags=re.MULTILINE,
)
boot.write_text(f"{boot_settings.rstrip()}\n\n[all]\ncamera_auto_detect=0\ndtoverlay={overlay}\n")

janus = root / "etc/kvmd/janus/janus.plugin.ustreamer.jcfg"
replacement = f'acap: {{\n    device = "plughw:RK628HDMI,0"\n    v4l2 = "{audio_device}"\n}}'
text, count = re.subn(r"^[ \t]*acap[ \t]*:[ \t]*\{[^}]*\}", replacement, janus.read_text(), flags=re.MULTILINE)
if count != 1:
    raise SystemExit(f"Expected exactly one Janus acap block, found {count}")
janus.write_text(text)

if board == "pi5":
    override = root / "etc/kvmd/override.yaml"
    settings = yaml.safe_load(override.read_text()) or {}
    merge(settings, yaml.safe_load((config / "pi5.yaml").read_text()))
    override.write_text(yaml.safe_dump(settings, sort_keys=False))
