pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // null while nothing is selected. The card animates out from whatever was
    // last shown, so the element it is drawing is latched separately.
    property var element: null
    property color fill: Appearance.colors.colLayer2
    // Where on this item the tile that opened the card sits, so the card grows
    // out of it (2.6) rather than out of the middle of the screen.
    property real originX: width / 2
    property real originY: height / 2

    signal closed

    property var shown: null
    readonly property color ink: ColorUtils.getContrastingTextColor(root.fill)
    readonly property bool open: root.element !== null

    onElementChanged: if (root.element !== null) root.shown = root.element
    visible: root.open || card.reveal > 0
    // Nothing behind the card is reachable while it is up.
    enabled: root.open

    function kelvinToCelsius(k) {
        return k === null || k === undefined ? null : Math.round((k - 273.15) * 10) / 10;
    }

    function temperature(k) {
        const c = root.kelvinToCelsius(k);
        return c === null ? "—" : `${c} °C  ·  ${k} K`;
    }

    function orNone(value, unit) {
        if (value === null || value === undefined || value === "")
            return "—";
        return unit ? `${value} ${unit}` : String(value);
    }

    // Scrim: the table underneath stays legible but stops competing.
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3scrim
        opacity: card.reveal * 0.55
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.closed()
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 8
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        // One driver for scale and opacity, with the spec assigned from inside
        // the binding that writes it (2.9). Enter decelerating over the default
        // spatial spec, exit accelerating at half of it (2.5).
        property int revealDuration: Appearance.animation.elementMove.duration
        property list<real> revealCurve: Appearance.animationCurves.emphasizedDecel
        property real reveal: {
            card.revealDuration = root.open ? Appearance.animation.elementMove.duration
                : Math.round(Appearance.animation.elementMove.duration / 2);
            card.revealCurve = root.open ? Appearance.animationCurves.emphasizedDecel
                : Appearance.animationCurves.emphasizedAccel;
            return root.open ? 1 : 0;
        }
        Behavior on reveal {
            NumberAnimation {
                duration: card.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: card.revealCurve
            }
        }
        opacity: card.reveal

        // An enum origin cannot point at an arbitrary tile, so the pivot is a
        // Scale transform -- the same thing ArrowPopup does for a click corner.
        transform: Scale {
            origin.x: root.originX
            origin.y: root.originY
            xScale: 0.85 + 0.15 * card.reveal
            yScale: 0.85 + 0.15 * card.reveal
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // --- header ------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle { // the tile, blown up
                    implicitWidth: 112
                    implicitHeight: 112
                    radius: Appearance.rounding.normal
                    color: root.fill

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            color: root.ink
                            opacity: 0.75
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: root.shown?.number ?? ""
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            color: root.ink
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.hugeass * 2
                            text: root.shown?.symbol ?? ""
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        text: root.shown?.name ?? ""
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: root.shown ? `${root.shown.mass} u  ·  ${root.shown.category}` : ""
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6
                        Chip { label: Translation.tr("Group %1").arg(root.shown?.group ?? "—") }
                        Chip { label: Translation.tr("Period %1").arg(root.shown?.period ?? "—") }
                        Chip { label: Translation.tr("%1-block").arg(root.shown?.block ?? "—") }
                        Chip { label: root.shown?.phase ?? "—" }
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.closed()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.title
                        text: "close"
                    }
                }
            }

            // --- body --------------------------------------------------------
            StyledFlickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: body.implicitHeight
                clip: true

                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 16

                    // Electron configuration and the shell diagram read together.
                    ContentSubsection {
                        title: Translation.tr("Electronic configuration")
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            ElementShells {
                                Layout.alignment: Qt.AlignVCenter
                                shells: root.shown?.shells ?? []
                                accent: root.fill
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 6
                                Fact {
                                    label: Translation.tr("Noble gas core")
                                    value: root.shown?.configShort ?? "—"
                                    emphasised: true
                                }
                                Fact {
                                    label: Translation.tr("Full")
                                    value: root.shown?.config ?? "—"
                                }
                                Fact {
                                    label: Translation.tr("Shells")
                                    value: (root.shown?.shells ?? []).join(", ") || "—"
                                }
                            }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Ionisation enthalpy")
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Successive values, kJ/mol. The jump is where a noble gas core is broken into.")
                        }
                        IonisationChart {
                            Layout.fillWidth: true
                            values: root.shown?.ionisation ?? []
                            accent: root.fill
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Atomic properties")
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 24
                            rowSpacing: 6

                            Fact { label: Translation.tr("Atomic radius (empirical)"); value: root.orNone(root.shown?.radiusEmpirical, "pm") }
                            Fact { label: Translation.tr("Covalent radius"); value: root.orNone(root.shown?.radiusCovalent, "pm") }
                            Fact { label: Translation.tr("Metallic radius"); value: root.orNone(root.shown?.radiusMetallic, "pm") }
                            Fact { label: Translation.tr("van der Waals radius"); value: root.orNone(root.shown?.radiusVdw, "pm") }
                            Fact { label: Translation.tr("Ionic radius"); value: root.orNone(root.shown?.ionRadius, "pm") }
                            Fact { label: Translation.tr("Electronegativity (Pauling)"); value: root.orNone(root.shown?.electronegativity, "") }
                            Fact { label: Translation.tr("Electron gain enthalpy"); value: root.orNone(root.shown?.electronAffinity, "kJ/mol") }
                            Fact { label: Translation.tr("Molar heat capacity"); value: root.orNone(root.shown?.molarHeat, "J/mol·K") }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Oxidation states")
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.shown?.oxidationStates ?? []
                                delegate: Chip {
                                    required property int modelData
                                    label: modelData > 0 ? `+${modelData}` : String(modelData)
                                }
                            }
                            StyledText {
                                visible: (root.shown?.oxidationStates ?? []).length === 0
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Not recorded")
                            }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Physical")
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 24
                            rowSpacing: 6

                            Fact { label: Translation.tr("State at 298 K"); value: root.shown?.phase ?? "—" }
                            Fact { label: Translation.tr("Density"); value: root.orNone(root.shown?.density, root.shown?.densityUnit ?? "") }
                            Fact { label: Translation.tr("Melting point"); value: root.temperature(root.shown?.melt ?? null) }
                            Fact { label: Translation.tr("Boiling point"); value: root.temperature(root.shown?.boil ?? null) }
                            Fact { label: Translation.tr("Bonding"); value: root.shown?.bonding ?? "—" }
                            Fact { label: Translation.tr("Appearance"); value: root.shown?.appearance ?? "—" }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Discovery")
                        Fact {
                            Layout.fillWidth: true
                            label: root.shown?.year ?? "—"
                            value: root.shown?.discoveredBy ?? "—"
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("About")
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            text: root.shown?.summary ?? ""
                        }
                    }
                }
            }
        }
    }

    component Chip: Rectangle {
        required property string label
        implicitWidth: chipText.implicitWidth + 20
        implicitHeight: 28
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer2
        StyledText {
            id: chipText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer2
            text: parent.label
        }
    }

    component Fact: ColumnLayout {
        required property string label
        required property string value
        property bool emphasised: false
        spacing: 0
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: parent.label
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: parent.emphasised ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small
            font.weight: parent.emphasised ? Font.DemiBold : Font.Normal
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer1
            text: parent.value
        }
    }

}
