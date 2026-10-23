// node services/settingsSearch.test.js
const assert = require("assert");
const S = require("./settingsSearch.js");

// The reader: rows know their section, and nothing inside a string, a comment,
// a regex or a JS block unbalances the tree.
const page = `
import QtQuick
import qs.modules.common.widgets

ContentPage {
    id: page
    readonly property var pattern: /[{"']/g // a brace, a quote: "the carousel's" }
    function helper(a) { if (a) { return "}" } return '{' }

    ContentSection {
        icon: "mouse"
        title: Translation.tr("Pointer")
        stringMap: [Translation.tr("Mouse"), Translation.tr("Trackpad")]

        ConfigSwitch {
            text: Translation.tr("Shake to find the pointer")
            checked: Config.options.interactions.shakeToFind.enable
            onCheckedChanged: {
                const s = \`\${checked ? "}" : "{"}\`;
                Config.options.interactions.shakeToFind.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shake the mouse to make the pointer big")
            }
        }
        ContentSubsection {
            title: Translation.tr("Size")
            ConfigSpinBox {
                text: Translation.tr("Cursor size")
                value: cond
                    ? 1
                    : 2
            }
            ConfigSwitch {
                text: Translation.tr("Show %1").arg(name)
            }
        }
        ConfigSelectionRow {
            text: "Style"
            options: [
                { displayName: Translation.tr("Outline"), value: 0 },
                { displayName: Translation.tr('Filled'), value: 1 }
            ]
        }
        Behavior on opacity { NumberAnimation { duration: 1 } }
    }

    ContentSection {
        title: Translation.tr("Second")
        contentItem: RowLayout {
            ConfigNavRow {
                text: Translation.tr("Nested")
                keywords: Translation.tr("Alpha, Beta")
            }
        }
    }
}
`;

const entries = S.indexFile(page, "");
const byLabel = {};
for (const e of entries)
    byLabel[e.label] = e;

assert.deepStrictEqual(entries.map(e => e.label),
    ["Pointer", "Shake to find the pointer", "Size", "Cursor size", "Style", "Second", "Nested"],
    "every static label, in order; a label built at runtime is left out");
assert.strictEqual(byLabel["Shake to find the pointer"].section, "Pointer");
assert.strictEqual(byLabel["Cursor size"].subsection, "Size");
assert.strictEqual(byLabel["Cursor size"].section, "Pointer");
assert.strictEqual(byLabel["Nested"].section, "Second", "an object bound to a property is still in the tree");
assert.deepStrictEqual(byLabel["Pointer"].keywords, ["Mouse", "Trackpad"]);
assert.deepStrictEqual(byLabel["Nested"].keywords, ["Alpha", "Beta"]);
assert.ok(byLabel["Shake to find the pointer"].details.includes("Shake the mouse to make the pointer big"), "a tooltip describes its row");
assert.deepStrictEqual(byLabel["Style"].details, ["Outline", "Filled"], "a choice row's chips describe it");

// A sub-page takes its title from its ContentPage.
const sub = S.indexFile(`Item { ContentPage { title: Translation.tr("Cursor configuration")
    ContentSection { title: Translation.tr("Cursor & pointer") } } }`, "widgets/CustomCursorConfig.qml");
assert.strictEqual(sub[0].subPage, "widgets/CustomCursorConfig.qml");
assert.strictEqual(sub[0].subPageTitle, "Cursor configuration");

assert.deepStrictEqual(S.subPagesOf(`onClicked: root.activeSubPage = Qt.resolvedUrl("widgets/A.qml")
    "configPage": "widgets/B.qml", x: "widgets/A.qml"`), ["widgets/A.qml", "widgets/B.qml"]);

// Matching.
assert.strictEqual(S.normalize("Wi-Fi  power-saving!"), "wi fi power saving");
assert.strictEqual(S.normalize("Écran"), "ecran", "accents do not have to be typed");
assert.strictEqual(S.editDistance("cursiror", "cursor", 2), 2);
assert.strictEqual(S.editDistance("shkae", "shake", 1), 1, "a swapped pair is one slip");
assert.ok(S.wordQuality("shak", "shake") > S.wordQuality("shkae", "shake"), "typed beats guessed");
assert.strictEqual(S.wordQuality("ab", "abacus") > 0, true, "two letters still find a word they start");
assert.strictEqual(S.wordQuality("ab", "cabin"), 0, "but not one they sit inside");

const pages = [{ name: "Advanced" }, { name: "Interface" }];
const all = []
    .concat(S.indexFile(`ContentPage {
        ContentSection { title: Translation.tr("Icons & cursor")
            ConfigNavRow { text: Translation.tr("Cursor"); keywords: Translation.tr("Shake to find") } }
        ContentSection { title: Translation.tr("Background")
            ConfigSwitch { text: Translation.tr("Shape") }
            ConfigSwitch { text: Translation.tr("Wi-Fi power saving") } } }`, "").map(e => Object.assign(e, { page: 0 })))
    .concat(sub.map(e => Object.assign(e, { page: 0 })))
    .concat(S.indexFile(`Item { ContentPage { title: Translation.tr("Cursor configuration")
        ContentSection { title: Translation.tr("Cursor & pointer")
            ConfigSwitch { text: Translation.tr("Shake to find the pointer") } } } }`, "widgets/CustomCursorConfig.qml").map(e => Object.assign(e, { page: 0 })))
    .concat(S.indexFile(`ContentPage { ContentSection { title: Translation.tr("Dock")
        ConfigSwitch { text: Translation.tr("Enable") }
        ConfigSpinBox { text: Translation.tr("Dock height") } } }`, "").map(e => Object.assign(e, { page: 1 })));
const index = S.buildIndex(all, pages);
const top = q => (S.search(index, q)[0] || {}).label;

assert.strictEqual(top("shake to find cursiror"), "Shake to find the pointer", "the owner's own query, typo and all");
assert.strictEqual(top("turn off shake to find"), "Shake to find the pointer", "filler words are not required");
assert.strictEqual(top("shake"), "Shake to find the pointer");
assert.ok(!S.search(index, "shake").some(r => r.label === "Shape"), "a real word is not read as a typo of another");
assert.strictEqual(top("pointer size"), "Cursor & pointer");
assert.strictEqual(top("wifi"), "Wi-Fi power saving", "a hyphenated word is found whole");
assert.strictEqual(top("mouse"), "Cursor", "a synonym finds what the shell calls it");
assert.strictEqual(top("dock"), "Dock", "an exact title first");
assert.deepStrictEqual(S.search(index, "dock").map(r => r.where), ["Interface", "Interface › Dock"],
    "a result says where it lives");
assert.strictEqual(S.search(index, "shake to find cursiror")[0].where, "Advanced › Cursor configuration",
    "a sub-page names itself, not its section");
assert.deepStrictEqual(S.search(index, "zzzz"), [], "nothing matches nothing");
assert.deepStrictEqual(S.search(index, "   "), []);
assert.strictEqual(S.search(index, "s", 2).length, 2, "the limit holds");

// Translated: both the source and the translation find it, and it reads translated.
const fr = S.buildIndex(all, pages, s => ({ "Shake to find the pointer": "Secouer pour trouver le pointeur" })[s] || s);
assert.strictEqual(S.search(fr, "secouer")[0].label, "Secouer pour trouver le pointeur");
assert.strictEqual(S.search(fr, "shake")[0].label, "Secouer pour trouver le pointeur");

console.log("ok");
