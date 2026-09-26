import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import org.kde.syntaxhighlighting

/**
 * Tool text in the monospace face, highlighted as `language` when it has one.
 *
 * A read-only TextEdit rather than a StyledText, so a command or a file body can be
 * selected and the transcript's selection actions reach it. Not a TextArea, which
 * is a Control: it would take the wheel from the transcript behind it, and brings
 * Qt's stock editing menu to a read-only box.
 */
TextEdit {
    id: root

    /** A KSyntaxHighlighting definition name ("Bash", "C", "JSON"), or "" for plain. */
    property string language: ""

    Layout.fillWidth: true
    // Its implicit width is the longest line unwrapped, and one long path is enough
    // to widen the card past the sidebar unless the layout may go narrower.
    Layout.minimumWidth: 0
    readOnly: true
    selectByMouse: true
    wrapMode: TextEdit.WrapAnywhere
    textFormat: TextEdit.PlainText
    renderType: Text.NativeRendering
    font.family: Appearance.font.family.monospace
    font.hintingPreference: Font.PreferNoHinting
    font.pixelSize: Appearance.font.pixelSize.smaller
    color: Appearance.colors.colOnLayer4
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer

    onSelectedTextChanged: TextSelectionService.report(root)
    Component.onDestruction: TextSelectionService.release(root)

    SyntaxHighlighter {
        textEdit: root
        repository: Repository
        definition: Repository.definitionForName(root.language)
        theme: Appearance.syntaxHighlightingTheme
    }
}
