pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell

Singleton {
    id: root

    property StackView stackView

    function push(component) {
        if (root.stackView) {
            root.stackView.push(component);
        }
    }

    function back() {
        if (root.stackView && root.stackView.depth > 1) {
            root.stackView.pop();
        }
    }

    function reset() {
        if (root.stackView && root.stackView.depth > 1) {
            root.stackView.pop(null);
        }
    }
}
