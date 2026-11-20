pragma ComponentBehavior: Bound

import "periodic_table.js" as PTable
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.animations
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * One element, read the way Pixel Weather reads a day -- and the way the
 * cheatsheet's own Weather tab does, so the two pages read as one family
 * (TASTE 2.11): a hero, then a grid of titled tiles, each a big value with a
 * small picture under it.
 *
 * The hero is the tile that was clicked, blown up: the element's family colour,
 * its number in the corner and its symbol as the one loud thing on the card.
 * The tiles run in the order a student revises: the configuration and its shell
 * diagram, then the trends that follow from it (ionisation, radii), then the
 * single numbers, then the oxidation states. "About" is reading, so it sits
 * under the hero, out of the way of the numbers.
 *
 * A reference card: nothing on it takes a click except the close button.
 */
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
    readonly property bool open: root.element !== null
    // The colour is latched with the element. The table drops `fill` to its
    // grey the moment the selection clears, which is the first frame of the
    // exit, so following it turned the hero and every bar grey while the card
    // was still scaling out.
    property color accent: root.fill
    Binding on accent {
        when: root.open
        value: root.fill
        restoreMode: Binding.RestoreNone
    }
    readonly property color ink: ColorUtils.getContrastingTextColor(root.accent)

    onElementChanged: if (root.element !== null) root.shown = root.element
    visible: root.open || card.reveal > 0
    // Nothing behind the card is reachable while it is up.
    enabled: root.open
    // Escape closes the card, not the whole cheatsheet. `focus: true` cannot do
    // this: the sheet's close button holds the window's focus and a nested item
    // does not take it just by asking. A window-context Shortcut is delivered
    // before key events reach any item, and disabling it hands Escape straight
    // back to the sheet's own handler.
    Shortcut {
        sequences: ["Escape"]
        enabled: root.open
        onActivated: root.closed()
    }

    // --- scales ---------------------------------------------------------------
    //
    // The bars are drawn against the whole table, not against this element, so
    // a short bar means a small atom and two cards can be compared by eye.
    readonly property real radiusMax: {
        let max = 0;
        for (const e of PTable.elements)
            for (const key of ["radiusEmpirical", "radiusCovalent", "radiusMetallic", "radiusVdw"])
                if ((e[key] ?? 0) > max)
                    max = e[key];
        return max;
    }
    readonly property real electronegativityMax: {
        let max = 0;
        for (const e of PTable.elements)
            max = Math.max(max, e.electronegativity ?? 0);
        return max;
    }

    // --- formatting ------------------------------------------------------------

    function present(value) {
        return value !== null && value !== undefined && value !== "";
    }

    // A typographic minus: "-48" sets its hyphen short and high next to digits.
    function number(value) {
        return root.present(value) ? String(value).replace("-", "−") : "—";
    }

    // A quantity whose sign is the point -- an enthalpy -- says "+" too.
    function signed(value) {
        return `${value > 0 ? "+" : ""}${root.number(value)}`;
    }

    function celsius(k) {
        if (!root.present(k))
            return "—";
        return `${root.number(Math.round((k - 273.15) * 10) / 10)} °C`;
    }

    function capitalised(text) {
        return root.present(text) ? text.charAt(0).toUpperCase() + text.slice(1) : "";
    }

    // "4f14" is "4f¹⁴" in every textbook: the count after each subshell letter
    // is an exponent, and the principal number before it is not.
    function superscript(config) {
        const digits = "⁰¹²³⁴⁵⁶⁷⁸⁹";
        return (config ?? "").replace(/([spdfg])(\d+)/g,
            (match, letter, count) => letter + count.split("").map(d => digits[Number(d)]).join(""));
    }

    // The source marks the superheavy configurations nobody has measured with a
    // leading "*".
    readonly property bool predicted: (root.shown?.configShort ?? "").startsWith("*")
    readonly property string coreConfig: (root.shown?.configShort ?? "").replace(/^\*/, "")

    readonly property bool anyRadius: root.ionic !== null
        || ["radiusEmpirical", "radiusCovalent", "radiusMetallic", "radiusVdw"].some(key => root.present((root.shown ?? {})[key]))

    // "119 (+1)": the radius, and the ion it was measured on.
    readonly property var ionic: {
        const match = /^([\d.]+)\s*\((.+)\)$/.exec(root.shown?.ionRadius ?? "");
        return match ? { value: Number(match[1]), charge: match[2] } : null;
    }

    function discovery(element) {
        if (!element)
            return "";
        if (element.year === "Ancient")
            return root.present(element.discoveredBy) && element.discoveredBy !== "Ancient"
                ? Translation.tr("Known since antiquity (%1)").arg(element.discoveredBy)
                : Translation.tr("Known since antiquity");
        return root.present(element.discoveredBy)
            ? Translation.tr("Discovered in %1 by %2").arg(element.year).arg(element.discoveredBy)
            : Translation.tr("Discovered in %1").arg(element.year);
    }

    // --- entrance ----------------------------------------------------------------
    //
    // The card scales out of the tile and the hero comes with it: the hero *is*
    // that tile, so it does not move on its own. The tiles follow it in on the
    // shared stagger (CardEnter), and the pictures in them -- the electrons
    // fanning round their shells, the columns and bars growing out of their
    // baselines -- ride `progress` out to their values. Decelerating and never
    // past 1: a bar that swings past its value reports a number that never
    // happened. No exit inside the card: it leaves as one surface, and a second
    // fade inside it reads as a stutter (CardEnter's own reasoning).
    property real progress: 1
    readonly property int travel: 16

    // Only from fully closed. Reopened while it is still leaving, the card turns
    // round with its tiles already in place; restarting would blank them on a
    // card that is half on screen.
    onOpenChanged: if (root.open && card.reveal === 0) entrance.restart()

    ParallelAnimation {
        id: entrance
        CardEnter { card: aboutTile; shift: aboutTile.shift; slot: 1; travel: root.travel }
        CardEnter { card: configTile; shift: configTile.shift; slot: 1; travel: root.travel }
        CardEnter { card: ionisationTile; shift: ionisationTile.shift; slot: 2; travel: root.travel }
        CardEnter { card: radiiTile; shift: radiiTile.shift; slot: 3; travel: root.travel }
        CardEnter { card: electronegativityTile; shift: electronegativityTile.shift; slot: 3; travel: root.travel }
        CardEnter { card: electronGainTile; shift: electronGainTile.shift; slot: 4; travel: root.travel }
        CardEnter { card: meltingTile; shift: meltingTile.shift; slot: 5; travel: root.travel }
        CardEnter { card: boilingTile; shift: boilingTile.shift; slot: 6; travel: root.travel }
        CardEnter { card: densityTile; shift: densityTile.shift; slot: 4; travel: root.travel }
        CardEnter { card: heatTile; shift: heatTile.shift; slot: 5; travel: root.travel }
        CardEnter { card: oxidationTile; shift: oxidationTile.shift; slot: 6; travel: root.travel }
        SequentialAnimation {
            PropertyAction { target: root; property: "progress"; value: 0 }
            PauseAnimation { duration: Appearance.animation.staggerStep * 3 }
            NumberAnimation {
                target: root
                property: "progress"
                to: 1
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
    }

    // The card is the page the tab would be if it were this element's: the
    // sheet's own surface tone, so its tiles take colLayer1 exactly as the
    // Weather tab's do, solved against the tone they actually sit on. Opaque
    // rather than colLayer0, which is solved against the transparency setting
    // and let the whole periodic table show through and fight every number on
    // the card; 0.98 keeps a hint of the surface without the card ever being
    // read *through*.
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer0Base, 0.98)
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

        // Everything fits on the sheet at 1080p; on a smaller screen the page
        // scrolls as one rather than squeezing a tile past legibility.
        StyledFlickable {
            id: page
            anchors.fill: parent
            anchors.margins: 16
            contentWidth: width
            contentHeight: Math.max(height, layout.implicitHeight)
            clip: true

            RowLayout {
                id: layout
                // The viewport, not `parent.width` -- a Flickable reparents its
                // children into a contentItem whose width is not the width you
                // can see.
                width: page.width
                height: page.contentHeight
                spacing: 12

                // --- identity -----------------------------------------------------
                ColumnLayout {
                    // A nested layout fills by default, and then the two halves
                    // split the width by their text's implicit widths.
                    Layout.fillWidth: false
                    Layout.preferredWidth: Math.round(Math.max(280, Math.min(380, page.width * 0.26)))
                    Layout.fillHeight: true
                    spacing: 12

                    Rectangle {
                        id: hero
                        Layout.fillWidth: true
                        implicitHeight: heroBody.implicitHeight + 40
                        radius: Appearance.rounding.normal
                        color: root.accent

                        ColumnLayout {
                            id: heroBody
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.fillWidth: true
                                    font.family: Appearance.font.family.numbers
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    font.variableAxes: Appearance.font.variableAxes.title
                                    color: root.ink
                                    text: root.shown?.number ?? ""
                                }

                                RippleButton {
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    buttonRadius: Appearance.rounding.full
                                    // The hero is the element's own colour, which no
                                    // layer token was solved against, so the films are
                                    // its ink at M3's state-layer opacities
                                    // (StateTokens: hover 0.08, pressed 0.10).
                                    colBackground: ColorUtils.transparentize(root.ink, 1)
                                    colBackgroundHover: ColorUtils.transparentize(root.ink, 0.92)
                                    colRipple: ColorUtils.transparentize(root.ink, 0.90)
                                    colStateLayer: root.ink
                                    onClicked: root.closed()
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.title
                                        color: root.ink
                                        text: "close"
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Close")
                                    }
                                }
                            }

                            // The symbol: the one loud thing on the card, and so the
                            // largest (M3 Expressive's size tactic, M3.md 2). Twice the
                            // hero-number size, because it is two letters where a hero
                            // number is a figure, and at 57 it sat small in a tile
                            // this size.
                            StyledText {
                                Layout.fillWidth: true
                                font.family: Appearance.font.family.title
                                font.pixelSize: Appearance.font.pixelSize.displayLarge * 2
                                // Full roundness, as the desktop's clock and date
                                // widgets set this face for their hero numerals.
                                font.variableAxes: ({ "wght": Appearance.font.variableAxes.title.wght, "ROND": 100 })
                                color: root.ink
                                text: root.shown?.symbol ?? ""
                            }

                            StyledText {
                                Layout.fillWidth: true
                                font.family: Appearance.font.family.title
                                font.pixelSize: Appearance.font.pixelSize.hugeass
                                font.variableAxes: Appearance.font.variableAxes.title
                                color: root.ink
                                text: root.shown?.name ?? ""
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.ink
                                opacity: 0.8
                                text: root.capitalised(root.shown?.category)
                            }

                            Item {
                                Layout.fillHeight: true
                                Layout.minimumHeight: 24
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 12
                                columnSpacing: 16
                                uniformCellWidths: true

                                HeroFact { label: Translation.tr("Group"); value: root.number(root.shown?.group) }
                                HeroFact { label: Translation.tr("Period"); value: root.number(root.shown?.period) }
                                HeroFact { label: Translation.tr("Block"); value: root.shown?.block ?? "—" }
                                HeroFact { label: Translation.tr("State at 298 K"); value: root.shown?.phase ?? "—" }
                                HeroFact { label: Translation.tr("Atomic mass"); value: root.present(root.shown?.mass) ? `${root.shown.mass} u` : "—" }
                                HeroFact { label: Translation.tr("Bonding"); value: root.capitalised(root.shown?.bonding) || "—" }
                            }
                        }
                    }

                    Tile {
                        id: aboutTile
                        // Reading, not a number: it takes what the hero leaves
                        // and scrolls its own text rather than stretch the page.
                        icon: "info"
                        title: Translation.tr("About")

                        StyledFlickable {
                            id: aboutFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            implicitHeight: Math.min(aboutText.implicitHeight, 120)
                            // Text that fits leaves the wheel to the page.
                            interactive: contentHeight > height
                            contentWidth: width
                            contentHeight: aboutText.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: aboutText
                                width: aboutFlick.width
                                spacing: 8

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.variableAxes: Appearance.font.variableAxes.title
                                    color: Appearance.colors.colOnLayer2
                                    text: root.capitalised(root.shown?.appearance)
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: Appearance.colors.colOnLayer1
                                    text: root.shown?.summary ?? ""
                                }
                                Note {
                                    wrapMode: Text.WordWrap
                                    text: root.discovery(root.shown)
                                }
                            }
                        }
                    }
                }

                // --- the numbers --------------------------------------------------
                GridLayout {
                    id: grid
                    // Narrow enough that a temperature no longer fits a quarter
                    // of the row, the small tiles pair up instead of eliding.
                    readonly property int minimumTileWidth: 200
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // What is left after the hero, not what the longest line of
                    // text would like.
                    Layout.preferredWidth: 0
                    columns: width >= grid.minimumTileWidth * 4 + columnSpacing * 3 ? 4 : 2
                    rowSpacing: 12
                    columnSpacing: 12
                    uniformCellWidths: true

                    Tile {
                        id: configTile
                        Layout.columnSpan: grid.columns
                        icon: "orbit"
                        title: Translation.tr("Electronic configuration")

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 24

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Value {
                                        Layout.fillWidth: false
                                        text: root.superscript(root.coreConfig)
                                    }
                                    Note {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: root.predicted
                                        text: Translation.tr("Predicted")
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    // Light elements have no core to abbreviate, and
                                    // the same line twice says nothing.
                                    visible: (root.shown?.config ?? "") !== root.coreConfig
                                    wrapMode: Text.WordWrap
                                    font.family: Appearance.font.family.numbers
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    text: root.superscript(root.shown?.config)
                                }
                                Flow { // electrons per shell, by the shell's letter
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 16
                                    Repeater {
                                        model: root.shown?.shells ?? []
                                        delegate: Row {
                                            id: shellCount
                                            required property int index
                                            required property int modelData
                                            spacing: 6
                                            StyledText {
                                                anchors.baseline: count.baseline
                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                color: Appearance.colors.colOnSurfaceVariant
                                                text: "KLMNOPQ".charAt(shellCount.index)
                                            }
                                            StyledText {
                                                id: count
                                                font.family: Appearance.font.family.numbers
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                font.variableAxes: Appearance.font.variableAxes.title
                                                color: Appearance.colors.colOnLayer2
                                                text: shellCount.modelData
                                            }
                                        }
                                    }
                                }
                            }

                            ElementShells {
                                Layout.alignment: Qt.AlignVCenter
                                size: 144
                                shells: root.shown?.shells ?? []
                                accent: root.accent
                                progress: root.progress
                            }
                        }
                    }

                    Tile {
                        id: ionisationTile
                        Layout.columnSpan: grid.columns / 2
                        icon: "bolt"
                        title: Translation.tr("Ionisation enthalpy")

                        Note {
                            wrapMode: Text.WordWrap
                            text: Translation.tr("Successive values, kJ/mol. The jump is where a noble gas core is broken into.")
                        }
                        IonisationChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 4
                            values: root.shown?.ionisation ?? []
                            accent: root.accent
                            progress: root.progress
                        }
                    }

                    Tile {
                        id: radiiTile
                        Layout.columnSpan: grid.columns / 2
                        icon: "straighten"
                        title: Translation.tr("Atomic radii")

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.anyRadius
                            spacing: 8

                            RadiusRow { label: Translation.tr("Empirical"); value: root.shown?.radiusEmpirical ?? null }
                            RadiusRow { label: Translation.tr("Covalent"); value: root.shown?.radiusCovalent ?? null }
                            RadiusRow { label: Translation.tr("Metallic"); value: root.shown?.radiusMetallic ?? null }
                            RadiusRow { label: Translation.tr("van der Waals"); value: root.shown?.radiusVdw ?? null }
                            RadiusRow {
                                label: root.ionic ? Translation.tr("Ionic (%1)").arg(root.ionic.charge) : Translation.tr("Ionic")
                                value: root.ionic?.value ?? null
                            }
                        }
                        Absent {
                            visible: !root.anyRadius
                            text: Translation.tr("Not measured")
                        }
                    }

                    StatTile {
                        id: electronegativityTile
                        icon: "join"
                        title: Translation.tr("Electronegativity")
                        value: root.present(root.shown?.electronegativity) ? Number(root.shown.electronegativity).toFixed(2) : "—"
                        note: root.present(root.shown?.electronegativity) ? Translation.tr("Pauling scale") : Translation.tr("Not measured")
                        gauge: root.present(root.shown?.electronegativity) && root.electronegativityMax > 0
                            ? root.shown.electronegativity / root.electronegativityMax : -1
                    }

                    StatTile {
                        id: electronGainTile
                        icon: "add_circle"
                        title: Translation.tr("Electron gain enthalpy")
                        // The data is electron affinity, energy released; the
                        // enthalpy is the same number with its sign turned round,
                        // so chlorine reads -349 as it does in the textbook.
                        value: root.present(root.shown?.electronAffinity) ? root.signed(-root.shown.electronAffinity) : "—"
                        note: root.present(root.shown?.electronAffinity) ? "kJ/mol" : Translation.tr("Not measured")
                    }

                    StatTile {
                        id: meltingTile
                        icon: "water_drop"
                        title: Translation.tr("Melting point")
                        value: root.celsius(root.shown?.melt)
                        note: root.present(root.shown?.melt) ? `${root.number(root.shown.melt)} K` : Translation.tr("Not measured")
                    }

                    StatTile {
                        id: boilingTile
                        icon: "local_fire_department"
                        title: Translation.tr("Boiling point")
                        value: root.celsius(root.shown?.boil)
                        note: root.present(root.shown?.boil) ? `${root.number(root.shown.boil)} K` : Translation.tr("Not measured")
                    }

                    StatTile {
                        id: densityTile
                        icon: "weight"
                        title: Translation.tr("Density")
                        value: root.number(root.shown?.density)
                        note: root.present(root.shown?.density)
                            ? (root.shown?.densityUnit ?? "").replace(/cm3$/, "cm³") : Translation.tr("Not measured")
                    }

                    StatTile {
                        id: heatTile
                        icon: "heat"
                        title: Translation.tr("Molar heat capacity")
                        value: root.number(root.shown?.molarHeat)
                        note: root.present(root.shown?.molarHeat) ? "J/(mol·K)" : Translation.tr("Not measured")
                    }

                    Tile {
                        id: oxidationTile
                        // The number line needs the room in either layout.
                        Layout.columnSpan: 2
                        icon: "exposure"
                        title: Translation.tr("Oxidation states")

                        Item { Layout.fillHeight: true }

                        // A number line from -4 to +8, the whole range any element
                        // reaches, so the states sit where they belong and the
                        // gaps between them show.
                        Rectangle {
                            id: numberLine
                            readonly property var charges: root.shown?.oxidationStates ?? []
                            Layout.fillWidth: true
                            implicitHeight: 32
                            visible: numberLine.charges.length > 0
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Repeater {
                                    model: 13
                                    delegate: Rectangle {
                                        id: slot
                                        required property int index
                                        readonly property int charge: slot.index - 4
                                        readonly property bool held: numberLine.charges.indexOf(slot.charge) >= 0
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Appearance.rounding.full
                                        color: slot.held ? root.accent : "transparent"

                                        StyledText {
                                            anchors.centerIn: parent
                                            font.family: Appearance.font.family.numbers
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                            // Held states are filled *and* heavier, so
                                            // the line still reads without the colour.
                                            font.variableAxes: slot.held ? Appearance.font.variableAxes.title : Appearance.font.variableAxes.numbers
                                            color: slot.held ? root.ink : Appearance.colors.colOnLayer1Inactive
                                            text: slot.charge > 0 ? `+${slot.charge}` : root.number(slot.charge)
                                        }
                                    }
                                }
                            }
                        }

                        Absent {
                            visible: numberLine.charges.length === 0
                            text: Translation.tr("Not recorded")
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // --- parts -------------------------------------------------------------------
    //
    // The Weather tab's tile vocabulary, on the same tones: a titled colLayer1
    // card at `normal`, an icon-and-label header, a big tabular value and a note.

    component CardHeader: RowLayout {
        id: header
        property string icon
        property string title
        Layout.fillWidth: true
        spacing: 8
        MaterialSymbol {
            text: header.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            text: header.title
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    component Tile: Rectangle {
        id: tile
        property string icon
        property string title
        default property alias content: tileBody.data
        readonly property Translate shift: Translate {}
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: tileBody.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        transform: tile.shift

        ColumnLayout {
            id: tileBody
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            CardHeader {
                icon: tile.icon
                title: tile.title
            }
        }
    }

    component StatTile: Tile {
        id: stat
        property string value
        property string note
        property real gauge: -1 // 0..1 draws a bar under the value
        Value {
            text: stat.value
        }
        Note {
            text: stat.note
        }
        Item {
            Layout.fillHeight: true
        }
        Meter {
            Layout.fillWidth: true
            visible: stat.gauge >= 0
            fraction: stat.gauge
        }
    }

    component Value: StyledText {
        Layout.fillWidth: true
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.hugeass * 1.25
        font.variableAxes: Appearance.font.variableAxes.title
        color: Appearance.colors.colOnLayer2
    }

    component Note: StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colOnSurfaceVariant
    }

    // A tile whose picture has nothing to draw says so where the picture would
    // be, the way the ionisation chart does.
    component Absent: StyledText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnSurfaceVariant
    }

    component HeroFact: ColumnLayout {
        id: heroFact
        required property string label
        required property string value
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: root.ink
            opacity: 0.75
            text: heroFact.label
        }
        StyledText {
            Layout.fillWidth: true
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.large
            font.variableAxes: Appearance.font.variableAxes.title
            color: root.ink
            text: heroFact.value
        }
    }

    // A value on a scale: the one bar on the card, so the radii and the
    // electronegativity gauge read as the same kind of thing. Not
    // StyledProgressBar -- these are readings, not progress, and its stop dot
    // marks an end the bar is heading for. Grows out on `progress`; nothing is
    // drawn for an unknown (negative) fraction, so the empty track says so.
    component Meter: Item {
        id: meter
        property real fraction: -1
        implicitHeight: 8

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
        }
        Rectangle {
            visible: meter.fraction >= 0
            height: parent.height
            width: Math.max(height, parent.width * Math.min(1, Math.max(0, meter.fraction)) * root.progress)
            radius: Appearance.rounding.full
            color: root.accent
        }
    }

    // One radius against the table's largest, labelled at both ends so the bar
    // never has to be read on its own.
    component RadiusRow: RowLayout {
        id: radiusRow
        required property string label
        required property var value
        readonly property bool known: radiusRow.value !== null && radiusRow.value !== undefined
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        StyledText {
            Layout.preferredWidth: 104
            Layout.minimumWidth: 0
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSurfaceVariant
            text: radiusRow.label
        }
        Meter {
            Layout.fillWidth: true
            fraction: radiusRow.known && root.radiusMax > 0 ? radiusRow.value / root.radiusMax : -1
        }
        StyledText {
            Layout.preferredWidth: 56
            horizontalAlignment: Text.AlignRight
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: radiusRow.known ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSurfaceVariant
            text: radiusRow.known ? `${radiusRow.value} pm` : "—"
        }
    }
}
