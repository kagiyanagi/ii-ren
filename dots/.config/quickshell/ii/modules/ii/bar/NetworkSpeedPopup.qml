import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "./cards"
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    /*
     * Contract 1's one entrance rule (DESIGN.md 2.8), the same shape every popup
     * in this cluster uses: opacity on an effects spec, one transform on the
     * enter spatial spec, siblings offset by their place in the visible order.
     * `running` is bound to the popup's open state, so a close stops it
     * mid-flight and the `from:` values restore the start state on the next open.
     *
     * Exit is the surface's own arrowPopup close, inherited from StyledPopup;
     * the content does not animate out separately.
     */
    component EnterAnim: SequentialAnimation {
        id: enterAnim

        property Item item
        property Translate slide
        property int delay: 0
        readonly property int offset: 12

        PauseAnimation {
            duration: enterAnim.delay
        }
        ParallelAnimation {
            NumberAnimation {
                target: enterAnim.item
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: enterAnim.slide
                property: "y"
                from: enterAnim.offset
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }

    function formatSpeed(bytesPerSecond) {
        var bits = bytesPerSecond * 8;
        var suffix = "bps";

        if (bits < 1000) {
            return bits.toFixed(0) + " " + suffix;
        } else if (bits < 1000000) {
            return (bits / 1000).toFixed(1) + " K" + suffix;
        } else if (bits < 1000000000) {
            return (bits / 1000000).toFixed(1) + " M" + suffix;
        } else {
            return (bits / 1000000000).toFixed(1) + " G" + suffix;
        }
    }

    function formatTotal(bytes) {
        var bits = bytes * 8;

        if (bits < 1000000) {
            return (bits / 1000).toFixed(1) + " Kb";
        } else if (bits < 1000000000) {
            return (bits / 1000000).toFixed(1) + " Mb";
        } else {
            return (bits / 1000000000).toFixed(1) + " Gb";
        }
    }

    ColumnLayout {
        id: contentLayout
        anchors.centerIn: parent
        spacing: 12

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        function getDelay(index) {
            return Appearance.animation.staggerStep * Math.min(index, Appearance.animation.staggerCap);
        }

        HeroCard {
            id: networkHero
            startAnim: contentLayout.startAnim
            icon: Network.ethernet ? "lan" : "wifi"
            title: Network.ethernet ? Translation.tr("Ethernet") : Translation.tr("Wi-Fi")
            subtitle: Network.networkName || Translation.tr("Connected")
            
            compactMode: true
            adaptiveWidth: true
            
            // Show signal strength in the pill if wifi
            pillText: !Network.ethernet ? (Network.networkStrength + "%") : ""
            pillIcon: !Network.ethernet ? "wifi" : ""

            opacity: 0
            transform: Translate {
                id: networkHeroSlide
            }

            EnterAnim {
                item: networkHero
                slide: networkHeroSlide
                delay: contentLayout.getDelay(0)
                running: contentLayout.startAnim
            }
        }

        ColumnLayout {
            id: pillColumn
            Layout.fillWidth: true
            spacing: 8

            opacity: 0
            transform: Translate {
                id: pillColumnSlide
            }

            EnterAnim {
                item: pillColumn
                slide: pillColumnSlide
                delay: contentLayout.getDelay(1)
                running: contentLayout.startAnim
            }

            InfoPill {
                startAnim: contentLayout.startAnim
                icon: "download"
                text: Translation.tr("Download: ") + formatSpeed(NetworkUsage.networkDownloadSpeed)
                containerColor: Appearance.colors.colPrimaryContainer
                shapeColor: Appearance.colors.colPrimary
                symbolColor: Appearance.colors.colOnPrimary
                textColor: Appearance.colors.colOnPrimaryContainer
            }

            InfoPill {
                startAnim: contentLayout.startAnim
                icon: "upload"
                text: Translation.tr("Upload: ") + formatSpeed(NetworkUsage.networkUploadSpeed)
                containerColor: Appearance.colors.colSecondaryContainer
                shapeColor: Appearance.colors.colSecondary
                symbolColor: Appearance.colors.colOnSecondary
                textColor: Appearance.colors.colOnSecondaryContainer
            }

            InfoPill {
                visible: !Config.options.bar.tooltips.compactPopups
                startAnim: contentLayout.startAnim
                icon: "data_usage"
                text: Translation.tr("Usage: ") + formatTotal(NetworkUsage.networkDownloadTotal + NetworkUsage.networkUploadTotal)
                containerColor: Appearance.colors.colTertiaryContainer
                shapeColor: Appearance.colors.colTertiary
                symbolColor: Appearance.colors.colOnTertiary
                textColor: Appearance.colors.colOnTertiaryContainer
            }
        }
    }
}
