pragma Singleton

import Quickshell
import QtQuick
import qs.modules.common

Singleton {
    id: root

    readonly property bool fetchRandom: Config.options?.background?.widgets?.quote?.fetchRandom ?? false
    readonly property bool animeOnly: Config.options?.background?.widgets?.quote?.animeOnly ?? false
    readonly property int updateIntervalHours: Config.options?.background?.widgets?.quote?.updateIntervalHours ?? 4

    property string currentQuote: Config.options?.background?.widgets?.quote?.cachedRandomQuote ?? ""
    property string currentAuthor: Config.options?.background?.widgets?.quote?.cachedRandomAuthor ?? ""
    property bool loading: false
    property string lastError: ""

    Timer {
        id: refreshTimer
        interval: Math.max(1, root.updateIntervalHours) * 3600 * 1000
        running: root.fetchRandom
        repeat: true
        onTriggered: root.fetchRandomQuote()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root.fetchRandom && (!root.currentQuote || root.currentQuote.length === 0)) {
                root.fetchRandomQuote();
            }
        }
    }

    // Re-fetch when switching between anime and general mode
    onAnimeOnlyChanged: {
        if (root.fetchRandom) root.fetchRandomQuote();
    }

    Component.onCompleted: {
        if (Config.ready && root.fetchRandom && (!root.currentQuote || root.currentQuote.length === 0)) {
            root.fetchRandomQuote();
        }
    }

    function fetchRandomQuote() {
        if (root.loading) return;
        root.loading = true;
        root.lastError = "";

        if (root.animeOnly) {
            fetchAnimeQuote();
        } else {
            fetchGeneralQuote();
        }
    }

    function fetchAnimeQuote() {
        const url = "https://api.animechan.io/v1/quotes/random";
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 6000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText);
                    const d = res?.data;
                    if (d && d.content) {
                        const char = d.character?.name || "";
                        const anime = d.anime?.name || "";
                        const attribution = char && anime ? `${char} · ${anime}` :
                                           char || anime;
                        applyQuote(d.content, attribution);
                        return;
                    }
                } catch (e) {
                    console.warn("[QuoteService] Failed to parse anime quote response:", e);
                }
            }

            root.loading = false;
            root.lastError = "Failed to fetch anime quote";
            console.warn("[QuoteService] Anime quote fetch failed, status:", xhr.status);
        };
        xhr.ontimeout = () => {
            root.loading = false;
            root.lastError = "Connection timed out";
        };
        xhr.onerror = () => {
            root.loading = false;
            root.lastError = "Network error";
        };
        xhr.send();
    }

    function fetchGeneralQuote() {
        const primaryUrl = "https://dummyjson.com/quotes/random";
        const fallbackUrl = "https://zenquotes.io/api/random";

        const xhr = new XMLHttpRequest();
        xhr.open("GET", primaryUrl);
        xhr.timeout = 6000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status === 200) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    if (data && data.quote) {
                        applyQuote(data.quote, data.author || "");
                        return;
                    }
                } catch (e) {
                    console.warn("[QuoteService] Failed to parse primary quote response:", e);
                }
            }

            fetchFallbackQuote(fallbackUrl);
        };
        xhr.ontimeout = () => {
            fetchFallbackQuote(fallbackUrl);
        };
        xhr.onerror = () => {
            fetchFallbackQuote(fallbackUrl);
        };
        xhr.send();
    }

    function fetchFallbackQuote(url) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 6000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status === 200) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    if (Array.isArray(data) && data.length > 0 && data[0].q) {
                        applyQuote(data[0].q, data[0].a || "");
                        return;
                    }
                } catch (e) {
                    console.warn("[QuoteService] Failed to parse fallback quote response:", e);
                }
            }

            root.loading = false;
            root.lastError = "Failed to fetch quote from internet";
        };
        xhr.ontimeout = () => {
            root.loading = false;
            root.lastError = "Connection timed out";
        };
        xhr.onerror = () => {
            root.loading = false;
            root.lastError = "Network error";
        };
        xhr.send();
    }

    function applyQuote(quoteText, author) {
        const trimmedQuote = (quoteText || "").trim();
        const trimmedAuthor = (author || "").trim();

        root.currentQuote = trimmedQuote;
        root.currentAuthor = trimmedAuthor;
        root.loading = false;
        root.lastError = "";

        if (Config.options?.background?.widgets?.quote) {
            Config.options.background.widgets.quote.cachedRandomQuote = trimmedQuote;
            Config.options.background.widgets.quote.cachedRandomAuthor = trimmedAuthor;
        }
    }
}
