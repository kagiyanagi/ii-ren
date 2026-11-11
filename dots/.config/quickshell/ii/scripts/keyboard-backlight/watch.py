#!/usr/bin/env python3
"""Report LED brightness changes, including firmware/Fn changes without inotify."""
import os
import select
import sys
import time
from pathlib import Path


def watch(device):
    brightness = Path(device) / "brightness"
    descriptor = None
    poller = None
    try:
        # Dell exposes this sysfs notification file. sysfs_notify wakes POLLPRI
        # waiters, not QFileSystemWatcher's inotify watch on brightness.
        descriptor = os.open(Path(device) / "brightness_hw_changed", os.O_RDONLY | os.O_NONBLOCK)
        poller = select.poll()
        poller.register(descriptor, select.POLLPRI | select.POLLERR)
    except OSError:
        pass
    last = None
    try:
        while True:
            value = int(brightness.read_text().strip())
            if value != last:
                print(value, flush=True)
                last = value
            # A bounded read also covers other drivers and software writes that
            # do not signal brightness_hw_changed. It never spawns a process.
            if poller is None:
                time.sleep(1)
            elif poller.poll(1000):
                try:
                    os.lseek(descriptor, 0, os.SEEK_SET)
                    os.read(descriptor, 128)
                except OSError:
                    time.sleep(1)
    finally:
        if descriptor is not None:
            os.close(descriptor)


if __name__ == "__main__":
    watch(sys.argv[1])
