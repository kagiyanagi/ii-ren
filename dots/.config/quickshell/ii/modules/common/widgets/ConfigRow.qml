import QtQuick
import QtQuick.Layouts

RowLayout {
    property bool uniform: false
    // One card for the whole row, but only if the row is made of things that
    // wanted one - a row of text fields or subsections stays bare.
    readonly property bool wantsCard: {
        for (let i = 0; i < visibleChildren.length; i++)
            if (visibleChildren[i].wantsCard === true) return true;
        return false;
    }
    spacing: 4
    uniformCellSizes: uniform
}
