pragma Singleton
import Quickshell

Singleton {
    id: root

    property var popups: []

    function setOpen(popup, owner, open) {
        const next = root.popups.filter(entry => entry.popup !== popup);
        // A tray menu can be anchored in the overflow popup. Resolve its bar
        // now, so it keeps the hold even if that parent popup finishes closing.
        const seen = new Set([popup]);
        let parent = root.popups.find(entry => entry.popup === owner);
        while (parent && !seen.has(owner)) {
            seen.add(owner);
            owner = parent.owner;
            parent = root.popups.find(entry => entry.popup === owner);
        }
        if (open && popup && owner && !seen.has(owner))
            next.push({ popup, owner });
        root.popups = next;
    }

    function hasOpenPopup(owner) {
        return !!owner && root.popups.some(entry => entry.owner === owner);
    }
}
