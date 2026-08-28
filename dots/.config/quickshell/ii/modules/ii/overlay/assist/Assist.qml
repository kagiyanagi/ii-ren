import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: "Assist"
    minimumWidth: 380
    minimumHeight: 240
    showCenterButton: true

    contentItem: AssistContent {
        radius: root.contentRadius
    }
}
