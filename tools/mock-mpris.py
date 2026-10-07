#!/usr/bin/env python3
"""A fake MPRIS player, so a media surface can be screenshotted without music.

    tools/mock-mpris.py [seconds]

Runs until killed (or `seconds`). Advertises one seekable, playing track with
cover art, which is what the media surfaces branch on: `canSeek` picks the wavy
slider over the flat progress bar, and `mpris:artUrl` is what the album-art and
colour-quantiser paths need to be exercised at all.
"""
import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

# MOCK_NAME lets a second instance stand alongside the first, which is the
# only way to reach a media surface's more-than-one-player layout.
NAME = os.environ.get("MOCK_NAME", "mockplayer")
BUS = f"org.mpris.MediaPlayer2.{NAME}"
PATH = "/org/mpris/MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
# MOCK_ART swaps in a remote (or hostile) url to exercise services/CoverArt.qml.
ART = os.environ.get("MOCK_ART", "file://" + os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../dots/.config/quickshell/ii/assets/images/default_wallpaper.png")))

META = dbus.Dictionary({
    "mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/mock/track1"),
    "mpris:length": dbus.Int64(int(os.environ.get("MOCK_LENGTH", 272)) * 1_000_000),
    "mpris:artUrl": ART,
    "xesam:title": os.environ.get("MOCK_TITLE", "Weightless in the Long Hall"),
    "xesam:artist": dbus.Array([os.environ.get("MOCK_ARTIST", "Oliviera Vance")], signature="s"),
    "xesam:album": "Night Transit",
}, signature="sv")

PROPS = {
    "org.mpris.MediaPlayer2": {
        "Identity": f"Mock Player ({NAME})",
        "DesktopEntry": "mpv",
        "CanQuit": True,
        "CanRaise": False,
        "HasTrackList": False,
        "SupportedUriSchemes": dbus.Array([], signature="s"),
        "SupportedMimeTypes": dbus.Array([], signature="s"),
    },
    PLAYER: {
        "PlaybackStatus": "Playing",
        "Metadata": META,
        "Position": dbus.Int64(int(os.environ.get("MOCK_POSITION", 63)) * 1_000_000),
        "Rate": 1.0,
        "MinimumRate": 1.0,
        "MaximumRate": 1.0,
        "Volume": 1.0,
        "CanGoNext": True,
        "CanGoPrevious": True,
        "CanPlay": True,
        "CanPause": True,
        "CanSeek": True,
        "CanControl": True,
    },
}


class Mock(dbus.service.Object):
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return PROPS[iface][prop]

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return dbus.Dictionary(PROPS.get(iface, {}), signature="sv")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
    def Set(self, iface, prop, value):
        PROPS[iface][prop] = value

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    # The transport controls, so a click on the surface does something visible.
    @dbus.service.method(PLAYER)
    def PlayPause(self):
        status = PROPS[PLAYER]["PlaybackStatus"]
        PROPS[PLAYER]["PlaybackStatus"] = "Paused" if status == "Playing" else "Playing"
        self.PropertiesChanged(PLAYER, {"PlaybackStatus": PROPS[PLAYER]["PlaybackStatus"]}, [])

    @dbus.service.method(PLAYER)
    def Play(self):
        PROPS[PLAYER]["PlaybackStatus"] = "Playing"
        self.PropertiesChanged(PLAYER, {"PlaybackStatus": "Playing"}, [])

    @dbus.service.method(PLAYER)
    def Pause(self):
        PROPS[PLAYER]["PlaybackStatus"] = "Paused"
        self.PropertiesChanged(PLAYER, {"PlaybackStatus": "Paused"}, [])

    @dbus.service.method(PLAYER)
    def Next(self):
        pass

    @dbus.service.method(PLAYER)
    def Previous(self):
        pass

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track, pos):
        PROPS[PLAYER]["Position"] = dbus.Int64(pos)

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        PROPS[PLAYER]["Position"] = dbus.Int64(PROPS[PLAYER]["Position"] + offset)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(BUS, bus)
    obj = Mock(bus, PATH)

    def tick():
        if PROPS[PLAYER]["PlaybackStatus"] == "Playing":
            pos = PROPS[PLAYER]["Position"] + 1_000_000
            PROPS[PLAYER]["Position"] = dbus.Int64(pos % PROPS[PLAYER]["Metadata"]["mpris:length"])
        return True

    GLib.timeout_add_seconds(1, tick)
    loop = GLib.MainLoop()
    if len(sys.argv) > 1:
        GLib.timeout_add_seconds(int(sys.argv[1]), loop.quit)
    print(f"{BUS} up", flush=True)
    loop.run()
    del name, obj


if __name__ == "__main__":
    main()
