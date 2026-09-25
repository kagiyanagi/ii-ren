# ii-sidebarDashboard-bluetoothDevices — brief

**Purpose.** Get a Bluetooth device talking to this machine: connect a saved one, drop
one, or pair a new one.

**Primary action.** Tap a row. A saved device connects or disconnects; a new one pairs and
then connects. One tap, as in Android 16's Bluetooth tile dialog. Before, a tap only
expanded the row, so every connect took two taps. Pairing never worked on a stock install
at all: BlueZ refuses to pair while no agent is registered, and nothing here registered
one.

**Hierarchy.** Title, then the discovery bar, then the list card: connected devices, then
saved ones, then new ones, in the order `BluetoothStatus` already sorts them. A connected
device's icon is in primary colour. Under each name is one status line that says what the
device is doing now. That line is missing only for a new device with nothing to report,
which is what tells saved devices apart from new ones without a divider (rule 11). Details
and Done sit in the button row, as in every `WindowDialog`.

**Reference.** Android 16 SystemUI `BluetoothTileDialog`: the row itself is the action, the
active device is marked in primary, and anything destructive is one level down. There,
that means the gear and the details page. Here, a chevron on saved devices opens the row
and shows **Forget**, in error colour.

**Interaction.** The row is `DialogListItem` and keeps its four states and its
`elementMove` height change. The chevron is its own round `RippleButton`, so it gets its
own hover, focus and press states, and it rotates on `elementMoveSmall` (spatial).
Rotation is a transform, and `elementMoveFast` is an effects spec. Status text is plain
text with no motion. A tap while the device is mid-transition does nothing. The empty
state is `PagePlaceholder`, which already owns its enter and exit.

**Edge states.**
- *Connecting / Disconnecting / Pairing*: said in the status line, at full opacity. Wi-Fi
  dims a busy row to 0.4, but 0.4 means disabled (rule 6), and this row is working.
- *Failed*: "Couldn't connect" / "Couldn't pair" in error colour, until the next tap. With
  no `bluetoothctl`, it says so, in Fast Pair's words.
- *Empty*: "Searching for devices" while the adapter is discovering, "No devices found"
  once it stops, and "Bluetooth unavailable" with no adapter. Before, the card was blank.
- *One device*: nothing special. The card keeps its height, as Wi-Fi's does.
- *Nameless devices*: gone, if they are not paired. A BLE advertiser with no name shows
  up as its MAC address, and a café has dozens. Android hides them by default too.

**Cost.** None. No effects, and the `ClippingRectangle` stays the one clip.

**Delete.** "Always connect", which was a mislabelled `pair()`. The two filled action
buttons. The row-tap-expands behaviour. The cryptic `p` property. The unused imports.

**Out of scope.** `DialogListItem`'s height motion, which is the same in both directions.
That belongs to `cw-dialogs`. Fast Pair's own agent: it keeps its copy, with its retry
timing. Turning the adapter on and off, which the quick toggle does, and which the dialog
still forces on when it opens. Waffle's `BluetoothControl` shares the row, so it gets the
tap-to-connect too. That matches Windows 11's quick settings list, so it stays.
