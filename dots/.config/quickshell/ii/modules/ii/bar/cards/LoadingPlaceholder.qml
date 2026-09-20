import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    Layout.fillWidth: true
    implicitHeight: loadingColumn.implicitHeight + 16
    color: "transparent"

    property bool loading: false
    property string loadingText: ""
    property string emptyText: ""
    // A fetch that failed used to read as "loading forever". One honest line,
    // in the secondary text colour -- a card that has no data is not an error
    // worth colError shouting about.
    property string errorText: ""
    property double indicatorSize: 48

    Layout.preferredHeight: implicitHeight

    ColumnLayout {
        id: loadingColumn
        anchors.centerIn: parent
        spacing: 8

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            loading: root.loading
            visible: root.loading
            implicitSize: root.indicatorSize
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.loading ? root.loadingText : (root.errorText !== "" ? root.errorText : root.emptyText)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
