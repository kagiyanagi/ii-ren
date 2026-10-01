import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// Android's Caffeine tile as the sidebar's other dialogs: the switch row the
// Wi-Fi and hotspot dialogs share, then how long, as two views of one card
// behind a connected selector: a dial of durations, or the running apps it
// stays awake for. One card, so a switch moves nothing under the pointer.
WindowDialog {
    id: root
    // The sidebar dialogs' fixed height (TASTE 4.1).
    backgroundHeight: Math.round(root.height * 0.6)

    readonly property int picked: Persistent.states.idle.minutes ?? 0
    // minutes 0 is until turned off.
    readonly property var durations: [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440, 0]
    readonly property bool anchored: Idle.inhibit && Idle.anchors.length > 0
    // 0 the durations, 1 the apps. Opens on the one in use, then is the user's:
    // a binding would flip the card when the last picked app is dropped.
    property int view: 0
    Component.onCompleted: root.view = root.anchored ? 1 : 0

    function label(m: int): string {
        return m === 0 ? Translation.tr("Always") : m < 60 ? `${m}m` : `${m / 60}h`;
    }

    // One row per process, its windows folded in, most recently focused first.
    // Then any picked one whose windows are gone but whose process is not.
    readonly property var apps: {
        const byPid = new Map();
        for (const w of [...HyprlandData.windowList].sort((a, b) => a.focusHistoryID - b.focusHistoryID)) {
            if (!(w.pid > 0)) continue;
            const app = byPid.get(w.pid);
            if (app) app.windows++;
            else byPid.set(w.pid, { pid: w.pid, cls: w.class, title: w.title, windows: 1 });
        }
        for (const a of Idle.anchors) {
            if (!byPid.has(a.pid)) byPid.set(a.pid, { pid: a.pid, cls: a.cls, title: "", windows: 0 });
        }
        return [...byPid.values()];
    }

    readonly property string status: {
        if (!Idle.inhibit) return Translation.tr("Screen sleeps and locks as usual");
        if (root.anchored) return Idle.anchors.length === 1
            ? Translation.tr("Awake while %1 runs").arg(Idle.anchors[0].name)
            : Translation.tr("Awake while %1 apps run").arg(Idle.anchors.length);
        if (Idle.until === 0) return Translation.tr("Awake until you turn it off");
        return Translation.tr("Awake until %1 · %2 left")
            .arg(Qt.formatTime(new Date(Idle.until), Config.options.time.format))
            .arg(Idle.remainingText);
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        WindowDialogTitle {
            text: Translation.tr("Keep awake")
        }
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.status
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: switchRow.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        DialogListItem {
            id: switchRow
            anchors.fill: parent
            buttonRadius: Appearance.rounding.large
            onClicked: Idle.toggleInhibit()

            contentItem: RowLayout {
                spacing: 10
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.larger
                    text: Idle.inhibit ? "kettle" : "local_cafe"
                    color: Idle.inhibit ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                        text: Translation.tr("Keep awake")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        // The mode it is on, or that a tap turns on: the tile's tap
                        // does the same, and never picks apps.
                        text: root.anchored ? Translation.tr("While apps run")
                            : root.picked === 0 ? Translation.tr("Until turned off")
                            : Translation.tr("For %1").arg(root.label(root.picked))
                    }
                }
                StyledSwitch {
                    checkable: false
                    checked: Idle.inhibit
                    down: switchRow.down
                    focusPolicy: Qt.NoFocus
                    onClicked: switchRow.clicked()
                }
            }
        }
    }

    // The hotspot dialog's connected group, as equal halves so the longer label
    // cannot push the seam off centre.
    RowLayout {
        Layout.fillWidth: true
        spacing: 2 // M3 Expressive connected group gap
        Repeater {
            model: [
                { icon: "timer", text: Translation.tr("For a time") },
                { icon: "apps", text: Translation.tr("While apps run") }
            ]
            delegate: SelectionGroupButton {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: false // GroupButton fills the clicked one's height
                Layout.preferredWidth: 1
                leftmost: index === 0
                rightmost: index === 1
                buttonIcon: modelData.icon
                buttonText: modelData.text
                toggled: root.view === index
                onClicked: root.view = index
            }
        }
    }

    // ClippingRectangle, as the Wi-Fi dialog's: plain `clip` would square a
    // row's hover fill off at the card's corners.
    ClippingRectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        // The durations on a dial; it picks on release, never on the way past.
        View {
            index: 0

            DurationDial {
                anchors.fill: parent
                durations: root.durations
                currentIndex: Math.max(0, root.durations.indexOf(root.picked))
                onPicked: i => Idle.start(root.durations[i])
            }
        }

        // Or no duration at all: awake until the apps picked here quit. By PID,
        // so it is the process that counts. Several can be picked, so each row
        // says whether it is in, as the audio dialog's combined devices do.
        View {
            index: 1

            StyledListView {
                anchors.fill: parent
                topMargin: 8
                bottomMargin: 8
                spacing: 0
                animateAppearance: false

                model: ScriptModel {
                    values: root.apps
                    objectProp: "pid"
                }
                delegate: DialogListItem {
                    id: appRow
                    required property var modelData
                    readonly property bool picked: Idle.anchors.some(a => a.pid === modelData.pid)
                    // Looked up again when the database reloads: a launch rescans it,
                    // and a lookup mid-scan finds nothing.
                    readonly property var entry: {
                        DesktopEntries.applications.values;
                        return DesktopEntries.heuristicLookup(modelData.cls);
                    }
                    readonly property string name: entry?.name || modelData.cls
                    width: ListView.view.width
                    // 56 with the icon, the top of DESIGN.md's list row range.
                    verticalPadding: 8
                    onClicked: Idle.toggleAnchor(modelData.pid, name, modelData.cls)

                    contentItem: RowLayout {
                        spacing: 12
                        // DESIGN.md: 40-48 for an app icon. Held at size while it loads.
                        StyledImage {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            source: Quickshell.iconPath(appRow.entry?.icon || AppSearch.guessIcon(appRow.modelData.cls), "image-missing")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                color: appRow.picked ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: appRow.name
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: {
                                    const w = appRow.modelData.windows;
                                    const what = w === 0 ? Translation.tr("No window")
                                        : w > 1 ? Translation.tr("%1 windows").arg(w) : appRow.modelData.title;
                                    // The PID first: a long title would elide it.
                                    return `PID ${appRow.modelData.pid} · ${what}`;
                                }
                            }
                        }
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.larger
                            fill: appRow.picked ? 1 : 0
                            text: appRow.picked ? "check_circle" : "radio_button_unchecked"
                            color: appRow.picked ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            PagePlaceholder {
                shown: root.apps.length === 0
                icon: "apps"
                title: Translation.tr("No apps are open")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
    }

    WindowDialogButtonRow {
        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }

    // One view of the card. The incoming one fades in on the effects spec, the
    // outgoing one out on the faster exit spec (DESIGN.md 2.5). The spec is set
    // inside the opacity binding, as NotificationItem's: a Behavior bakes its
    // duration when the write happens.
    component View: Item {
        id: view
        required property int index
        readonly property bool current: root.view === index
        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        anchors.fill: parent
        opacity: {
            view.fadeSpec = view.current ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return view.current ? 1 : 0;
        }
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: view.fadeSpec.duration
                easing.type: view.fadeSpec.type
                easing.bezierCurve: view.fadeSpec.bezierCurve
            }
        }
    }
}
