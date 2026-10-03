import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root
    readonly property string builtInThemeDirectory: Directories.defaultThemes
    readonly property string customThemeDirectory: Directories.customThemes

    property string colorScheme: "scheme-auto"
    property string colorSchemeDisplayName: ""

    property bool builtInTheme: false
    readonly property string builtInThemeFilePath: builtInThemeDirectory + "/" + colorScheme + ".json"
    readonly property string builtInThemeCommand: `jq -r '.primary, .primary_container, .secondary' '${StringUtils.shellSingleQuoteEscape(builtInThemeFilePath)}'`

    property bool customTheme: false
    readonly property string customThemeFilePath: customThemeDirectory + "/" + colorScheme + ".json"
    readonly property string customThemeCommand: `jq -r '.primary, .primary_container, .secondary' '${StringUtils.shellSingleQuoteEscape(customThemeFilePath)}'`  

    // A wallpaper scheme's three colours, handed in by ColorPreviewGrid, which reads them
    // for every scheme in one run instead of a python per button.
    property var wallpaperPreview: null
    onWallpaperPreviewChanged: {
        if (!root.wallpaperPreview)
            return;
        root.primaryColor = root.wallpaperPreview.primary || "transparent";
        root.secondaryColor = root.wallpaperPreview.primary_container || "transparent";
        root.tertiaryColor = root.wallpaperPreview.secondary || "transparent";
        root.loaded = true;
        myCanvas.requestPaint();
    }

    // these are not actually primary, secondary and tertiary, they are just the three colors we get from the script
    property color primaryColor: "transparent"
    property color secondaryColor: "transparent"
    property color tertiaryColor: "transparent"

    property bool loaded: false
    property bool shouldLoad: false

    readonly property bool toggled: Config.options.appearance.palette.type === root.colorScheme
    readonly property bool sharpMode: Config.options.appearance.sharpMode

    colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: toggled ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
    colRipple: toggled ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active

    buttonRadius: Appearance.rounding.small

    Layout.fillWidth: true
    implicitHeight: 64

    onClicked: {
        if (customTheme) {
            Config.options.appearance.palette.type = root.colorScheme;
            Quickshell.execDetached(["cp", root.customThemeFilePath, Directories.generatedMaterialThemePath]);
        } else if (builtInTheme) {
            Config.options.appearance.palette.type = root.colorScheme;
            Quickshell.execDetached(["cp", root.builtInThemeFilePath, Directories.generatedMaterialThemePath]);
        } else {
            Config.options.appearance.palette.type = root.colorScheme;
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
        }
    }

    property var effectiveCommand: root.customTheme ? root.customThemeCommand : root.builtInThemeCommand

    onShouldLoadChanged: {
        if (shouldLoad && !loaded && (customTheme || builtInTheme)) {
            colorFetchProcess.running = true
        }
    }

    Process {
        id: colorFetchProcess
        running: false
        command: ["bash", "-c", root.effectiveCommand]

        stdout: StdioCollector {
            onStreamFinished: {
                // Nothing on stdout is a command that had nothing to say -- every
                // settings launch logged a parse error for it.
                if (this.text.trim().length === 0) return;
                const colors = this.text.trim().split("\n")
                root.primaryColor   = colors[0] || "transparent"
                root.secondaryColor = colors[1] || "transparent"
                root.tertiaryColor  = colors[2] || "transparent"
                root.loaded = true
                myCanvas.requestPaint()
            }
        }
    }

    StyledToolTip {
        text: root.colorSchemeDisplayName
    }

    Item {
        anchors.fill: parent

        StyledText {
            anchors.fill: parent
            visible: !root.loaded
            elide: Text.ElideRight
            text: root.colorSchemeDisplayName
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnPrimaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
        }

        Canvas {
            id: myCanvas
            anchors.centerIn: parent
            anchors.margins: 8

            implicitWidth: root.implicitHeight - 16
            implicitHeight: root.implicitHeight - 16

            antialiasing: true

            onPaint: {
                var ctx = getContext("2d");
                var centerX = width / 2;
                var centerY = height / 2;
                var radius = width / 2;

                ctx.reset();

                if (root.sharpMode) {
                    ctx.fillStyle = root.primaryColor;
                    ctx.fillRect(0, 0, width, centerY);

                    ctx.fillStyle = root.secondaryColor;
                    ctx.fillRect(centerX, centerY, centerX, centerY);

                    ctx.fillStyle = root.tertiaryColor;
                    ctx.fillRect(0, centerY, centerX, centerY);
                } else {
                    ctx.beginPath();
                    ctx.fillStyle = root.primaryColor;
                    ctx.moveTo(centerX, centerY);
                    ctx.arc(centerX, centerY, radius, Math.PI, 0, false);
                    ctx.fill();

                    ctx.beginPath();
                    ctx.fillStyle = root.secondaryColor;
                    ctx.moveTo(centerX, centerY);
                    ctx.arc(centerX, centerY, radius, 0, Math.PI / 2, false);
                    ctx.fill();

                    ctx.beginPath();
                    ctx.fillStyle = root.tertiaryColor;
                    ctx.moveTo(centerX, centerY);
                    ctx.arc(centerX, centerY, radius, Math.PI / 2, Math.PI, false);
                    ctx.fill();
                }
            }
        }
    }
}