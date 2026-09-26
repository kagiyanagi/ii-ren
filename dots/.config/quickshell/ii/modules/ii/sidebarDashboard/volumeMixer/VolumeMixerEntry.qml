import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

RowLayout {
    id: root
    required property PwNode node
    readonly property bool muted: node?.audio.muted ?? false
    spacing: 12

    PwObjectTracker {
        objects: [root.node]
    }

    // Was a bare MouseArea over a Desaturate: no states, and an offscreen pass
    // per row in a repeated delegate.
    RippleButton {
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer4)
        colBackgroundHover: Appearance.colors.colLayer4Hover
        colRipple: Appearance.colors.colLayer4Active
        colStateLayer: Appearance.colors.colOnLayer4
        onClicked: root.node.audio.muted = !root.muted

        StyledToolTip {
            text: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
        }

        contentItem: Item {
            Item {
                anchors.centerIn: parent
                width: 28
                height: 28
                opacity: root.muted ? 0 : 1
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                StyledImage {
                    anchors.fill: parent
                    source: {
                        let icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                        if (!AppSearch.iconExists(icon))
                            icon = AppSearch.guessIcon(root.node?.properties["node.name"] ?? "");
                        return Quickshell.iconPath(icon, "image-missing");
                    }
                }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                opacity: root.muted ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                text: root.node?.isSink ? "volume_off" : "mic_off"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: {
                const app = Audio.appNodeDisplayName(root.node);
                const media = root.node?.properties["media.name"];
                return media != undefined ? `${app} • ${media}` : app;
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.S
            value: root.node?.audio.volume ?? 0
            onMoved: root.node.audio.volume = value
        }
    }
}
