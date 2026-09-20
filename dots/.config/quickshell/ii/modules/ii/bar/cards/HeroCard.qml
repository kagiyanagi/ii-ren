import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations

Rectangle {
    id: heroCardRoot

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    Layout.preferredWidth: implicitWidth
    implicitWidth: compactMode ? 320 : 380
    implicitHeight: compactMode ? 140 : 180

    property bool adaptiveWidth: false
    property bool compactMode: false
    
    // Internal animation control
    property bool startAnim: false

    // One transform per entering child, siblings staggerStep apart and capped
    // (DESIGN.md 2.8). The shape's old 1120ms scale was more than twice the
    // longest spec in the table, on something the size of a coaster.
    readonly property int enterTravel: 24

    onStartAnimChanged: {
        if (!heroCardRoot.startAnim) return;
        shapeItem.scale = 0.8;
        pill.opacity = 0.0;
        pillTranslate.x = heroCardRoot.enterTravel;
        mainText.opacity = 0.0;
        mainText.scale = 0.9;
        subtitleText.opacity = 0.0;
        Qt.callLater(() => {
            shapeAnim.restart();
            pillAnim.restart();
            titleAnim.restart();
            subtitleAnim.restart();
        });
    }

    component EnterFade: DelayedPropertyAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    component EnterMove: DelayedPropertyAnimation {
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    radius: Appearance.rounding.normal
    color: Appearance.colors.colPrimaryContainer

    property int margins: compactMode ? 16 : 24
    property int iconSize: compactMode ? 64 : 110
    property real iconFontSize: compactMode ? 32 : 48

    property string shapeString: "Cookie9Sided"
    property string icon: ""
    property url iconUrl: ""

    property string title: ""
    property var parsedTitle: {
        var t = title || "";
        var match = t.match(/^(.*?)\s*([ap]m|[AP]M)$/);
        if (match) {
            return { main: match[1], ampm: match[2] };
        }
        return { main: t, ampm: "" };
    }
    property string subtitle: ""
    property int titleSize: compactMode ? Appearance.font.pixelSize.hugeass * 1.5 : Appearance.font.pixelSize.hugeass * 2.5
    property int subtitleSize: compactMode ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.hugeass

    property string pillText: ""
    property string pillIcon: ""

    property color pillColor: Appearance.colors.colOnPrimary
    property color pillTextColor: Appearance.colors.colOnSecondaryContainer
    property color pillIconColor: Appearance.colors.colOnSecondaryContainer

    property color shapeColor: Appearance.colors.colPrimary
    property color symbolColor: Appearance.colors.colOnPrimary
    property color textColor: Appearance.colors.colOnPrimaryContainer

    property alias shapeContent: shapeItem.data
    property alias shapeRotation: shapeItem.rotation
    property int spacing: 16

    Item {
        width: heroCardRoot.iconSize
        height: heroCardRoot.iconSize
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            margins: heroCardRoot.margins
        }

        MaterialShape {
            id: shapeItem
            shapeString: heroCardRoot.shapeString
            implicitSize: heroCardRoot.iconSize
            color: heroCardRoot.shapeColor
            anchors.centerIn: parent

            EnterMove {
                id: shapeAnim
                target: shapeItem
                property: "scale"
                from: 0.8
                to: 1
            }
        }

        Image {
            id: iconImage
            visible: heroCardRoot.iconUrl.toString() !== "" && shapeItem.children.length === 0
            anchors.centerIn: parent
            source: heroCardRoot.iconUrl
            sourceSize: Qt.size(heroCardRoot.iconFontSize, heroCardRoot.iconFontSize)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }

        MaterialSymbol {
            id: iconSymbol
            visible: heroCardRoot.icon !== "" && heroCardRoot.iconUrl.toString() === "" && shapeItem.children.length === 0
            anchors.centerIn: parent
            text: heroCardRoot.icon
            iconSize: heroCardRoot.iconFontSize
            color: heroCardRoot.symbolColor
            fill: 1
        }
    }

    Rectangle {
        id: pill
        visible: heroCardRoot.pillText !== "" && heroCardRoot.pillIcon !== ""
        implicitHeight: cityRow.implicitHeight + 12
        implicitWidth: cityRow.implicitWidth + 20
        radius: Appearance.rounding.full
        color: heroCardRoot.pillColor
        anchors {
            right: parent.right
            top: parent.top
            margins: heroCardRoot.margins
        }
        
        transform: Translate {
            id: pillTranslate
        }

        ParallelAnimation {
            id: pillAnim

            EnterFade {
                target: pill
                delay: Appearance.animation.staggerStep
            }
            EnterMove {
                target: pillTranslate
                property: "x"
                from: heroCardRoot.enterTravel
                delay: Appearance.animation.staggerStep
            }
        }

        RowLayout {
            id: cityRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: heroCardRoot.pillIcon
                iconSize: Appearance.font.pixelSize.small
                color: heroCardRoot.pillIconColor
            }
            StyledText {
                renderType: Text.QtRendering
                antialiasing: true
                smooth: true
                text: heroCardRoot.pillText
                font {
                    weight: Font.Bold
                    pixelSize: Appearance.font.pixelSize.small
                }
                color: heroCardRoot.pillTextColor
                elide: Text.ElideRight
                Layout.maximumWidth: 120
            }
        }
    }

    Item {
        id: textContainer
        anchors {
            left: parent.left
            leftMargin: heroCardRoot.iconSize + heroCardRoot.margins * 2 + 16
            right: parent.right
            rightMargin: heroCardRoot.margins
            top: pill.visible ? pill.bottom : parent.top
            topMargin: pill.visible ? heroCardRoot.margins : heroCardRoot.margins
            bottom: parent.bottom
            bottomMargin: heroCardRoot.margins
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledText {
                    id: ampmText
                    text: heroCardRoot.parsedTitle.ampm
                    visible: text !== ""
                    font.pixelSize: heroCardRoot.titleSize * 0.45
                    renderType: Text.QtRendering
                    antialiasing: true
                    smooth: true
                    font.family: Appearance.font.family.title
                    font.weight: Font.Black
                    color: heroCardRoot.textColor
                    anchors {
                        right: parent.right
                        baseline: mainText.baseline
                    }
                }

                StyledText {
                    id: mainText
                    text: heroCardRoot.parsedTitle.main
                    font.pixelSize: heroCardRoot.titleSize
                    font.family: Appearance.font.family.title
                    renderType: Text.QtRendering
                    antialiasing: true
                    smooth: true
                    font.weight: Font.Black
                    color: heroCardRoot.textColor
                    anchors {
                        right: ampmText.visible ? ampmText.left : parent.right
                        rightMargin: ampmText.visible ? 4 : 0
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight

                    ParallelAnimation {
                        id: titleAnim

                        EnterFade {
                            target: mainText
                            delay: Appearance.animation.staggerStep * 2
                        }
                        EnterMove {
                            target: mainText
                            property: "scale"
                            from: 0.9
                            to: 1
                            delay: Appearance.animation.staggerStep * 2
                        }
                    }
                }
            }

            StyledText {
                id: subtitleText
                text: heroCardRoot.subtitle
                renderType: Text.QtRendering
                antialiasing: true
                smooth: true
                Layout.fillWidth: true
                font {
                    pixelSize: heroCardRoot.subtitleSize
                    family: Appearance.font.family.title
                    weight: Font.Black
                }
                color: heroCardRoot.textColor
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight

                EnterFade {
                    id: subtitleAnim
                    target: subtitleText
                    delay: Appearance.animation.staggerStep * 3
                }
            }
        }
    }
}
