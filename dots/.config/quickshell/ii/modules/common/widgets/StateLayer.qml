import QtQuick

// A translucent film laid over content to show it is interactive. Unlike swapping
// a background colour, this composites, so it reads the same over a flat button,
// a photo or a video frame.
// https://m3.material.io/foundations/interaction/states/state-layers
Rectangle {
    id: root

    enum State {
        Hover,
        Focus,
        Press,
        Drag
    }

    // Not named "state": Item already has one (the QML states machine), and
    // shadowing it silently breaks States on anything that uses this.
    property int layerState: StateLayer.State.Hover

    // The Material 3 state layer opacity tokens.
    opacity: switch (root.layerState) {
    case StateLayer.State.Hover:
        return 0.08;
    case StateLayer.State.Focus:
        return 0.1;
    case StateLayer.State.Press:
        return 0.1;
    case StateLayer.State.Drag:
        return 0.16;
    default:
        return 0;
    }
}
