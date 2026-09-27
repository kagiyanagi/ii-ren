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

function arrangedClients(hyprlandClients, maxRowWidth, maxWindowWidth, maxWindowHeight) {
    if (!hyprlandClients || !Array.isArray(hyprlandClients)) return [];
    const count = hyprlandClients.length;
    const resultLayout = [];

    var i = 0;
    while (i < count) {
        var row = [];
        var rowWidth = 0;
        var j = i;

        while (j < count) {
            const client = hyprlandClients[j];
            const scaledSize = scaleWindow(client, maxWindowWidth, maxWindowHeight);

            if (rowWidth + scaledSize.width <= maxRowWidth || row.length === 0) {
                row.push(client);
                rowWidth += scaledSize.width;
                j++;
            } else {
                break;
            }
        }

        resultLayout.push(row);
        i = j;
    }

    return resultLayout;
}
