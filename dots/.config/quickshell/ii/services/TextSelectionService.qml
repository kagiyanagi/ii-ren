pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Which text view in the shell currently holds a mouse selection.
 *
 * A selection lives inside one TextArea, and a reply is rendered as many of them
 * -- one per paragraph while text fades in, plus a separate one per code block --
 * so nothing above the delegates knows the user has highlighted anything. Each
 * view reports here and whatever wants to act on a selection reads it from one
 * place, instead of reaching down into a Repeater's children to find it.
 *
 * One selection is tracked at a time: the last view to report a non-empty one
 * wins. That matches what the user sees, since starting a drag in another view is
 * what clears the first.
 */
Singleton {
    id: root

    /** The view the selection lives in, or null when nothing is selected. */
    property Item source: null
    property string text: ""

    readonly property bool active: root.source !== null && root.text.length > 0

    /**
     * Called by a text view whenever its selection changes.
     *
     * An emptied selection only clears the service when it comes from the view
     * being tracked: delegates are recycled and destroyed as the transcript
     * scrolls, dropping their own selections on the way out, and one of those must
     * not take a live selection made somewhere else with it.
     */
    function report(item: var): void {
        if (!item)
            return;
        const selected = item.selectedText ?? "";
        if (selected.length > 0) {
            root.source = item;
            root.text = selected;
        } else if (root.source === item) {
            root.clear();
        }
    }

    /** Forget the selection without touching the view it came from. */
    function clear(): void {
        root.source = null;
        root.text = "";
    }

    /** Forget it *and* unhighlight it, for an explicit dismissal. */
    function dismiss(): void {
        const item = root.source;
        root.clear();
        if (item?.deselect)
            item.deselect();
    }

    /** A view going away takes its own selection with it. */
    function release(item: var): void {
        if (root.source === item)
            root.clear();
    }
}
