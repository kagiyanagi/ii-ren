function scaleWindow(hyprlandClient, maxWindowWidth, maxWindowHeight) {
    if (!hyprlandClient || !hyprlandClient.size || hyprlandClient.size.length < 2) {
        return Qt.size(maxWindowWidth || 200, maxWindowHeight || 150);
    }
    const width = hyprlandClient.size[0];
    const height = hyprlandClient.size[1];
    if (width <= 0 || height <= 0) {
        return Qt.size(maxWindowWidth || 200, maxWindowHeight || 150);
    }
    const xScale = maxWindowWidth / width;
    const yScale = maxWindowHeight / height;
    const scale = Math.min(xScale, yScale);
    return Qt.size(Math.round(width * scale), Math.round(height * scale));
}
