pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../common/functions/wallpaperFraming.js" as Framing

// A crop editor, as Android's wallpaper picker and Google Photos have it: the
// whole picture, dimmed wherever the screen does not reach, under a bright
// screen-shaped frame. Drag it under the frame, Ctrl+scroll or pinch to zoom,
// arrows and +/- from the keyboard; the toolbar holds the rest. It draws
// through the same maths as the desktop (wallpaperFraming.js), so what sits in
// the frame is what the desktop shows. Every edit is stored per wallpaper in
// Persistent; the shell reads it from there.
//
// ClippingRectangle costs two offscreen passes, a mask and the content. Kept:
// this is one control on a settings page, never repeated, and the rounded clip
// is the card it sits in (TASTE.md 7).
ClippingRectangle {
    id: root

    // What a drag moves: "wallpaper", or "subject" once there is a cutout of
    // your own to place.
    property string target: "wallpaper"

    readonly property string path: FileUtils.trimFileProtocol(Config.options.background.wallpaperPath ?? "")
    readonly property bool isVideo: Wallpapers.isVideoFile(root.path.toLowerCase())
    // A video is mpvpaper's to fit, so it is shown as the desktop shows it -
    // its thumbnail, at the defaults - and cannot be framed.
    readonly property bool usable: root.path.length > 0 && !root.isVideo
    readonly property string shownPath: root.isVideo
        ? FileUtils.trimFileProtocol(Config.options.background.thumbnailPath ?? "") : root.path
    readonly property var framing: Framing.entry(root.usable ? Persistent.states.wallpaperFraming : null, root.path)
    // Drawn only where the desktop draws it too.
    readonly property bool showSubject: root.framing.subject !== null && WallpaperSubject.ready
    readonly property bool editingSubject: root.target === "subject" && root.showSubject
    readonly property int subjectStatus: subjectImage.status
    readonly property bool canReset: root.usable && (root.editingSubject
        ? (root.framing.subject.x !== 0.5 || root.framing.subject.y !== 0.5 || root.framing.subject.zoom !== 1)
        : !Framing.isDefault(root.withSubject(null)))

    // This window's screen is the shape being framed for.
    readonly property real screenW: Math.max(1, Screen.width)
    readonly property real screenH: Math.max(1, Screen.height)

    // The frame takes the middle three quarters of the card's width, which
    // leaves an eighth either side to show what the screen crops away. Below
    // it, room for the toolbar.
    readonly property real side: root.width / 8
    readonly property real gap: 12
    readonly property real frameX: root.side
    readonly property real frameY: root.side
    readonly property real frameW: root.width - root.side * 2
    readonly property real frameH: root.frameW * root.screenH / root.screenW
    readonly property real k: root.frameW / root.screenW
    implicitHeight: root.frameY + root.frameH + toolbar.implicitHeight + root.gap * 2

    // The real pixel size, which baseZoom needs. Until magick answers - or if
    // it is not installed - the loaded image stands in: right shape, and
    // right size for anything up to the screen's.
    property int measuredW: 0
    property int measuredH: 0
    readonly property real imageW: root.measuredW || picture.implicitWidth
    readonly property real imageH: root.measuredH || picture.implicitHeight
    readonly property bool sized: root.imageW > 0 && root.imageH > 0 && picture.status === Image.Ready
    readonly property real baseZoom: Framing.baseZoom(root.imageW, root.imageH, root.screenW, root.screenH,
        Config.options.background.parallax.workspaceZoom,
        Config.options.background.parallax.enableWorkspace || Config.options.background.parallax.enableSidebar)
    readonly property var frame: Framing.rect(root.framing, root.imageW, root.imageH, root.screenW, root.screenH, root.baseZoom)
    // Pointer-driven moves land under the pointer at once; everything else - a
    // mode, the slider, a reset - travels on the desktop's own spec.
    readonly property bool direct: mouseArea.pressed || pinch.active

    function save(next) {
        if (!root.usable)
            return;
        // JsonAdapter only notices a new value, so the map is rebuilt.
        const all = Object.assign({}, Persistent.states.wallpaperFraming);
        if (Framing.isDefault(next))
            delete all[root.path];
        else
            all[root.path] = next;
        Persistent.states.wallpaperFraming = all;
    }

    function withSubject(subject) {
        return Object.assign({}, root.framing, { subject: subject });
    }

    // Both in card px.
    function panBy(dx, dy) {
        const f = root.framing;
        if (root.editingSubject)
            root.save(root.withSubject(Framing.subjectPan(f.subject, root.frame.width * root.k, root.frame.height * root.k, dx, dy)));
        else
            root.save(Framing.pan(f, root.frame, root.screenW, root.screenH, dx / root.k, dy / root.k));
    }

    // About (px, py) in card px.
    function zoomBy(factor, px, py) {
        const f = root.framing;
        const sx = (px - root.frameX) / root.k;
        const sy = (py - root.frameY) / root.k;
        if (root.editingSubject)
            root.save(root.withSubject(Framing.subjectZoomAt(f.subject, f.subject.zoom * factor,
                (sx - root.frame.x) / root.frame.width, (sy - root.frame.y) / root.frame.height)));
        else
            root.save(Framing.zoomAt(f, root.imageW, root.imageH, root.screenW, root.screenH, root.baseZoom,
                f.zoom * factor, sx, sy));
    }

    // The slider's and the keys' way in: the wallpaper zooms about the
    // screen's centre, a subject about its own, so it grows where it stands.
    readonly property real zoom: root.editingSubject ? root.framing.subject.zoom : root.framing.zoom
    function setZoom(zoom) {
        const f = root.framing;
        if (root.editingSubject)
            root.save(root.withSubject(Framing.subjectZoomAt(f.subject, zoom, f.subject.x, f.subject.y)));
        else
            root.zoomBy(zoom / f.zoom, root.frameX + root.frameW / 2, root.frameY + root.frameH / 2);
    }

    function setMode(mode) {
        root.save(Object.assign({}, root.framing, { mode: mode }));
    }

    function reset() {
        if (root.editingSubject)
            root.save(root.withSubject(Object.assign({}, root.framing.subject, Framing.SUBJECT_DEFAULTS)));
        else
            root.save(Object.assign({}, Framing.DEFAULTS, { subject: root.framing.subject }));
    }

    function setSubject(path) {
        root.save(root.withSubject(path ? Object.assign({ path: path }, Framing.SUBJECT_DEFAULTS) : null));
        root.target = path ? "subject" : "wallpaper";
    }

    onShownPathChanged: root.measure()
    Component.onCompleted: root.measure()
    function measure() {
        root.measuredW = 0;
        root.measuredH = 0;
        if (root.shownPath.length > 0)
            identify.exec(["magick", "identify", "-format", "%w %h", `${root.shownPath}[0]`]);
    }

    Process {
        id: identify
        stdout: StdioCollector {
            onStreamFinished: {
                const [w, h] = this.text.split(" ").map(Number);
                root.measuredW = w > 0 ? w : 0;
                root.measuredH = h > 0 ? h : 0;
            }
        }
    }

    // A carded row like its neighbours: same container, same outer radius.
    radius: Appearance.rounding.large
    color: Appearance.colors.colSurfaceContainerHigh
    activeFocusOnTab: root.usable

    component FrameBehavior: Behavior {
        enabled: !root.direct
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // Inside the frame, where the picture does not reach: the bars, in the
    // colour the desktop paints them.
    Rectangle {
        x: root.frameX
        y: root.frameY
        width: root.frameW
        height: root.frameH
        radius: Appearance.rounding.verysmall
        color: Appearance.colors.colLayer0Base
    }

    Image {
        id: picture
        x: root.frameX + root.frame.x * root.k
        y: root.frameY + root.frame.y * root.k
        width: root.frame.width * root.k
        height: root.frame.height * root.k
        FrameBehavior on x {}
        FrameBehavior on y {}
        FrameBehavior on width {}
        FrameBehavior on height {}

        source: root.shownPath.length > 0 ? `file://${root.shownPath}` : ""
        // Screen resolution, so zooming in stays sharp without holding an 8K
        // original in the settings app.
        sourceSize.width: root.screenW
        fillMode: root.framing.mode === "stretch" ? Image.Stretch : Image.PreserveAspectCrop
        asynchronous: true
        mipmap: true

        // Disabled, not hidden, for a video: it is the reason the toolbar
        // under it is off.
        opacity: !root.sized ? 0 : root.usable ? 1 : 0.4
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // While the subject is what moves, the wallpaper inside the frame steps
    // back too. In on default effects, out on fast effects, and reversible.
    Rectangle {
        id: subjectScrim
        x: root.frameX
        y: root.frameY
        width: root.frameW
        height: root.frameH
        radius: Appearance.rounding.verysmall
        color: Appearance.colors.colScrim
        visible: opacity > 0
        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        opacity: {
            subjectScrim.fadeSpec = root.editingSubject ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return root.editingSubject ? 1 : 0;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: subjectScrim.fadeSpec.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: subjectScrim.fadeSpec.bezierCurve
            }
        }
    }

    Image {
        id: subjectImage
        readonly property var box: root.framing.subject
            ? Framing.subjectRect(root.framing.subject, picture.width, picture.height)
            : Qt.rect(0, 0, 0, 0)
        x: picture.x + box.x
        y: picture.y + box.y
        width: box.width
        height: box.height
        source: root.framing.subject ? `file://${root.framing.subject.path}` : ""
        sourceSize.width: root.screenW
        fillMode: root.framing.mode === "stretch" ? Image.Stretch : Image.PreserveAspectFit
        asynchronous: true
        mipmap: true

        readonly property bool shown: root.showSubject && root.sized && status === Image.Ready
        visible: opacity > 0
        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        opacity: {
            subjectImage.fadeSpec = subjectImage.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return subjectImage.shown ? 1 : 0;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: subjectImage.fadeSpec.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: subjectImage.fadeSpec.bezierCurve
            }
        }
    }

    // Everything the screen crops away, dimmed. One rectangle whose border is
    // the scrim and whose inside is the hole: a mask would be another pass.
    Rectangle {
        readonly property real reach: Math.max(root.width, root.height)
        x: root.frameX - reach
        y: root.frameY - reach
        width: root.frameW + reach * 2
        height: root.frameH + reach * 2
        radius: Appearance.rounding.verysmall + reach
        color: "transparent"
        border.width: reach
        border.color: Appearance.colors.colScrim
    }

    // The screen's edge, which is also the focus ring.
    Rectangle {
        x: root.frameX
        y: root.frameY
        width: root.frameW
        height: root.frameH
        radius: Appearance.rounding.verysmall
        color: "transparent"
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutline
    }

    // Nothing to frame yet, or nothing readable at that path.
    MaterialSymbol {
        x: root.frameX + (root.frameW - width) / 2
        y: root.frameY + (root.frameH - height) / 2
        visible: root.shownPath.length === 0 || picture.status === Image.Error
        text: root.shownPath.length === 0 ? "wallpaper" : "broken_image"
        iconSize: Appearance.font.pixelSize.huge
        color: Appearance.colors.colSubtext
    }

    // The whole card drags, not only the frame: the cropped-away part is the
    // part you most often want to pull in.
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.usable && root.sized
        hoverEnabled: true
        // The page is a Flickable and would take a vertical drag for a scroll.
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property point last
        onPressed: mouse => {
            root.forceActiveFocus();
            mouseArea.last = Qt.point(mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (!mouseArea.pressed)
                return;
            root.panBy(mouse.x - mouseArea.last.x, mouse.y - mouseArea.last.y);
            mouseArea.last = Qt.point(mouse.x, mouse.y);
        }
        // Plain scroll still scrolls the page; zoom takes Ctrl, as on a map set
        // into a page, so passing over the card never hijacks the scroll.
        // A tenth per notch, the step image viewers take.
        onWheel: wheel => {
            if (!(wheel.modifiers & Qt.ControlModifier)) {
                wheel.accepted = false;
                return;
            }
            root.zoomBy(Math.pow(1.1, wheel.angleDelta.y / 120), wheel.x, wheel.y);
        }

        StyledToolTip {
            text: Translation.tr("Drag to move. Ctrl+scroll or pinch to zoom.")
            extraVisibleCondition: !mouseArea.pressed && !toolbarHover.hovered
        }
    }

    // Touchpad pinch arrives as a native gesture, which no MouseArea sees.
    PinchHandler {
        id: pinch
        target: null
        enabled: mouseArea.enabled
        property real last: 1
        onActiveChanged: pinch.last = 1
        onActiveScaleChanged: {
            root.zoomBy(pinch.activeScale / pinch.last, pinch.centroid.position.x, pinch.centroid.position.y);
            pinch.last = pinch.activeScale;
        }
    }

    // Arrows move it the way a drag would, a twentieth of the frame a press.
    Keys.onPressed: event => {
        const step = root.frameW / 20;
        const moves = {
            [Qt.Key_Left]: [-step, 0], [Qt.Key_Right]: [step, 0],
            [Qt.Key_Up]: [0, -step], [Qt.Key_Down]: [0, step]
        };
        if (moves[event.key]) {
            root.panBy(...moves[event.key]);
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            root.setZoom(root.zoom * 1.1);
        } else if (event.key === Qt.Key_Minus) {
            root.setZoom(root.zoom / 1.1);
        } else {
            return;
        }
        event.accepted = true;
    }

    component ToolButton: IconToolbarButton {
        id: toolButton
        required property string tip
        StyledToolTip {
            text: toolButton.tip
        }
    }

    // Every control in one floating M3 toolbar under the frame, over the
    // cropped-away part, so nothing it shows or hides moves the page.
    Toolbar {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.gap
        enabled: root.usable

        HoverHandler {
            id: toolbarHover
        }

        // Only once there is a cutout of your own to place: the model's is
        // welded to the pixels it was cut from and has nowhere to go.
        ToolButton {
            visible: root.showSubject
            text: "wallpaper"
            tip: Translation.tr("Move the wallpaper")
            toggled: !root.editingSubject
            onClicked: root.target = "wallpaper"
        }
        ToolButton {
            visible: root.showSubject
            text: "filter_center_focus"
            tip: Translation.tr("Move the subject")
            toggled: root.editingSubject
            onClicked: root.target = "subject"
        }
        Item {
            visible: root.showSubject
            implicitWidth: 8
        }

        Repeater {
            model: [
                { value: "fill", icon: "crop", name: Translation.tr("Fill the screen") },
                { value: "fit", icon: "fit_screen", name: Translation.tr("Fit the whole picture") },
                { value: "stretch", icon: "open_in_full", name: Translation.tr("Stretch to the screen") }
            ]
            delegate: ToolButton {
                required property var modelData
                // A mode is the wallpaper's; the subject only moves and resizes.
                enabled: !root.editingSubject
                text: modelData.icon
                tip: modelData.name
                toggled: root.framing.mode === modelData.value
                onClicked: root.setMode(modelData.value)
            }
        }
        Item {
            implicitWidth: 8
        }

        MaterialSymbol {
            text: "zoom_in"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledSlider {
            id: zoomSlider
            Layout.preferredWidth: root.width / 5
            Layout.alignment: Qt.AlignVCenter
            configuration: StyledSlider.Configuration.XS
            from: root.editingSubject ? Framing.MIN_SUBJECT_ZOOM * 100 : 100
            to: Framing.MAX_ZOOM * 100
            value: root.zoom * 100
            showTooltip: false
            // The default stop sits at 1, which here is off the start of the
            // track and drew a stray dot beside it.
            stopIndicatorValues: []
            onMoved: root.setZoom(Math.round(value) / 100)
        }
        // Held at the width of its widest reading, so the toolbar does not
        // twitch as the digits change under a drag.
        StyledText {
            id: zoomLabel
            Layout.preferredWidth: widest.width
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(root.zoom * 100)}%`
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnSurfaceVariant
            TextMetrics {
                id: widest
                text: `${Framing.MAX_ZOOM * 100}%`
                font: zoomLabel.font
            }
        }
        Item {
            implicitWidth: 8
        }

        // Resets whichever of the two a drag is moving.
        ToolButton {
            enabled: root.canReset
            text: "restart_alt"
            tip: root.editingSubject ? Translation.tr("Put the subject back") : Translation.tr("Reset to fill, at 100%")
            onClicked: root.reset()
        }
    }
}
