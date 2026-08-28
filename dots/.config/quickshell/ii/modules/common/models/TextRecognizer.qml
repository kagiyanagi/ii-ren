pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common.functions
import qs.modules.common.utils
import qs.services

/**
 * On-device OCR with `tesseract`. No API key, no billing.
 * Produces `paragraphs`, each `{ text, boundingBox: { vertices: [4 x {x, y}] } }`,
 * matching the shape the screen translator overlay draws from.
 */
AsyncTask {
    id: root

    property real confidenceThreshold: 50 // tesseract reports 0-100 per word
    property var paragraphs: []

    // Every installed traineddata except osd, which detects orientation rather than text.
    // Empty (no langpacks) means let tesseract pick its own default.
    readonly property string langSetup: `L=$(tesseract --list-langs 2>/dev/null | awk 'NR>1 && $1 != "osd" {print $1}' | tr '\\n' '+' | sed 's/+$//')`

    function recognize(imageUri: string) {
        resetState();
        root.paragraphs = [];
        root.state = AsyncTask.State.Processing;
        const path = StringUtils.shellSingleQuoteEscape(FileUtils.trimFileProtocol(imageUri));
        proc.runSequence([
            ["bash", "-c", `${root.langSetup}; tesseract '${path}' stdout \${L:+-l "$L"} tsv 2>/dev/null`],
            (out) => root.handleTsv(out)
        ]);
    }

    // Columns: level page block par line word left top width height conf text
    function handleTsv(tsv: string) {
        const rows = (tsv ?? "").split("\n");
        if (rows.length === 0 || !rows[0].startsWith("level\t")) {
            root.fail(Translation.tr("Could not run tesseract. Is it installed?"));
            return;
        }

        const found = [];
        let current = null;
        for (let i = 1; i < rows.length; i++) {
            const c = rows[i].split("\t");
            if (c.length < 12) continue;
            const level = parseInt(c[0]);
            if (level === 3) { // paragraph: box comes straight from tesseract
                const x = parseInt(c[6]), y = parseInt(c[7]), w = parseInt(c[8]), h = parseInt(c[9]);
                current = {
                    words: [],
                    confidences: [],
                    boundingBox: {
                        vertices: [{ x: x, y: y }, { x: x + w, y: y }, { x: x + w, y: y + h }, { x: x, y: y + h }]
                    }
                };
                found.push(current);
            } else if (level === 5 && current) { // word
                const text = c.slice(11).join("\t").trim();
                if (text.length === 0) continue;
                current.words.push(text);
                current.confidences.push(parseFloat(c[10]));
            }
        }

        root.paragraphs = found.filter(p => {
            if (p.confidences.length === 0) return false;
            const mean = p.confidences.reduce((a, b) => a + b, 0) / p.confidences.length;
            if (mean < root.confidenceThreshold) return false;
            p.text = root.joinWords(p.words);
            return p.text.length > 0;
        });

        if (root.paragraphs.length === 0) {
            root.fail(Translation.tr("No readable text found on screen."));
            return;
        }
        root.succeed();
    }

    // One line per paragraph: `trans` collapses newlines anyway, and keeping the
    // source single-line is what lets the overlay tell a real translation from a
    // no-op. CJK doesn't take spaces between words.
    function joinWords(words: list<string>): string {
        const cjk = /[\u3000-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff01-\uff9f]/;
        return words.reduce((acc, w) => {
            if (acc.length === 0) return w;
            const glued = cjk.test(acc[acc.length - 1]) && cjk.test(w[0]);
            return acc + (glued ? "" : " ") + w;
        }, "").trim();
    }

    MultiTurnProcess {
        id: proc
    }
}
