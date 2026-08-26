pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Simple moving average over ±window samples, clamping at both ends so the
     * result is the same length as the input.
     * @param { list } points
     * @param { int } window
     * @returns { list }
     */
    function smooth(points, window) {
        const n = points.length;
        let out = [];
        for (let i = 0; i < n; ++i) {
            let sum = 0, count = 0;
            for (let j = -window; j <= window; ++j) {
                sum += points[Math.max(0, Math.min(n - 1, i + j))];
                count++;
            }
            out.push(sum / count);
        }
        return out;
    }
}
