pragma Singleton
import Quickshell
import "fuzzysort.js" as FuzzySort

/**
 * Wrapper for FuzzySort to play nicely with Quickshell's imports
 */

Singleton {
    function go(...args) {
        return FuzzySort.go(...args)
    }

    function prepare(...args) {
        return FuzzySort.prepare(...args)
    }

    /**
     * Searches a list of `{ name: prepare(...), entry }` objects, returning the matching entries.
     */
    function queryEntries(search, preppedList) {
        return FuzzySort.go(search, preppedList, {
            all: true,
            key: "name"
        }).map(r => r.obj.entry)
    }
}

