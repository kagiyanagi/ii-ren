pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import QtCore

Singleton {
    id: root

    // public state
    property bool authenticated: false
    readonly property bool loading: tokenRefresher.running || inboxFetcher.running || labelFetcher.running
    property string userEmail: ""
    property ListModel inboxMessages: ListModel {}
    property int inboxUnreadCount: 0

    property int maxEmails: 20
    property string historyId: ""
    property bool enableUpdates: false
    property bool enablePromotions: false
    property bool enableSocials: false
    property int refreshIntervalMinutes: 1
    property bool authenticating: false
    property bool credentialsConfigured: false

    // internal tokens
    property string _accessToken: ""
    property int _tokenExpiry: 0   // epoch seconds
    property string _refreshToken: ""

    Settings {
        id: emailSettings
        category: "EmailService"
        property alias maxEmails: root.maxEmails
        property alias enableUpdates: root.enableUpdates
        property alias enablePromotions: root.enablePromotions
        property alias enableSocials: root.enableSocials
        property alias refreshIntervalMinutes: root.refreshIntervalMinutes
        property alias historyId: root.historyId
        property alias credentialsConfigured: root.credentialsConfigured
    }

    function checkCredentials() {
        credentialsChecker.running = true;
    }

    function formatRelativeDate(timestamp) {
        if (!timestamp)
            return "";

        let date = new Date(timestamp * 1000);
        let today = new Date();
        let now = Math.floor(Date.now() / 1000);
        let diff = now - timestamp;

        if (diff < 60)
            return "Just now"; // Also covers clock skew (diff < 0)
        if (diff < 3600)
            return Math.floor(diff / 60) + "m ago";
        if (diff < 86400)
            return Math.floor(diff / 3600) + "h ago";
        if (diff < 172800)
            return "Yesterday";

        if (date.getFullYear() === today.getFullYear()) {
            return date.toLocaleDateString(Qt.locale(), "MMM d");
        }
        return date.toLocaleDateString(Qt.locale(), "MMM d, yyyy");
    }

    Process {
        id: credentialsChecker
        command: ["python3", Directories.scriptPath + "/email/check_credentials.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.credentialsConfigured = JSON.parse(text).configured;
                } catch (e) {
                    root.credentialsConfigured = false;
                }
            }
        }
    }

    onMaxEmailsChanged: _startDebouncedSync()
    onEnableUpdatesChanged: _startDebouncedSync()
    onEnablePromotionsChanged: _startDebouncedSync()
    onEnableSocialsChanged: _startDebouncedSync()
    onRefreshIntervalMinutesChanged: {
        _startDebouncedSync();
        if (autoRefreshTimer.running) {
            autoRefreshTimer.restart();
        }
    }

    function _startDebouncedSync() {
        if (!authenticated)
            return;
        debounceSyncTimer.restart();
    }

    Timer {
        id: debounceSyncTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.authenticated)
                root.syncAll();
        }
    }

    Timer {
        id: autoRefreshTimer
        interval: root.refreshIntervalMinutes * 60 * 1000
        running: root.authenticated && root.refreshIntervalMinutes > 0
        repeat: true
        onTriggered: root.syncAll()
    }

    Timer {
        id: retryRefreshTimer
        interval: 15000 // 15 seconds
        repeat: false
        onTriggered: {
            if (!root.authenticated && root._refreshToken !== "") {
                root._refreshAndFetch();
            }
        }
    }

    Connections {
        target: Network
        function onWifiStatusChanged() {
            if (Network.wifiStatus === "connected" && !root.authenticated && root._refreshToken !== "") {
                root._refreshAndFetch();
            }
        }
    }

    function _getBestToken() {
        let now = Math.floor(Date.now() / 1000);
        if (_accessToken !== "" && now < (_tokenExpiry - 30)) {
            return _accessToken;
        }
        return _refreshToken;
    }

    // IPC — called by scripts/email/oauth_server.py once the browser flow finishes
    IpcHandler {
        target: "gmail"
        function onAuthComplete(refreshToken: string, email: string, picture: string) {
            KeyringStorage.setNestedField(["gmail_accounts"], [
                {
                    email: email,
                    avatar: picture,
                    refreshToken: refreshToken
                }
            ]);
            KeyringStorage.setNestedField(["gmail_refresh_token"], refreshToken);
            KeyringStorage.setNestedField(["gmail_user_email"], email);

            root.inboxMessages.clear();
            root.inboxUnreadCount = 0;
            root._accessToken = "";
            root.historyId = "";
            root.userEmail = email;
            root._refreshToken = refreshToken;
            root._refreshAndFetch();
        }
        function onTokenRefreshed(accessToken: string, expiresIn: int) {
            root._accessToken = accessToken;
            root._tokenExpiry = Math.floor(Date.now() / 1000) + expiresIn - 60;
            root.authenticated = true;
            root.syncAll();
        }
    }

    // initialization — keyring might not have loaded yet
    Component.onCompleted: {
        root.checkCredentials();
        if (KeyringStorage.loaded) {
            _tryInit();
        }
    }

    Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (KeyringStorage.loaded && !root.authenticated)
                root._tryInit();
        }
    }

    function _tryInit() {
        const stored = KeyringStorage.keyringData["gmail_accounts"];
        const acc = (Array.isArray(stored) && stored.length > 0) ? stored[0] : {
            email: KeyringStorage.keyringData["gmail_user_email"] || "",
            refreshToken: KeyringStorage.keyringData["gmail_refresh_token"] || ""
        };

        if (!acc.refreshToken || acc.refreshToken === "")
            return;

        root.userEmail = acc.email || "";
        root._refreshToken = acc.refreshToken;
        _refreshAndFetch();
    }

    function startOAuth() {
        if (!credentialsConfigured)
            return;
        authProcess.running = false;
        root.authenticating = true;
        authProcess.running = true;
    }

    function syncAll() {
        if (root._refreshToken && root._refreshToken !== "") {
            root._refreshAndFetch();
        }
    }

    function _refreshAndFetch() {
        if (_refreshToken === "")
            return;

        // First refresh the token, then fetch the inbox
        tokenRefresher.command = ["python3", Directories.scriptPath + "/email/token_refresh.py", _refreshToken];
        tokenRefresher.running = true;
    }

    Process {
        id: tokenRefresher
        command: ["echo", ""]
        stdout: StdioCollector {
            id: tokenOutput
            onStreamFinished: {
                if (text.length === 0) {
                    // Don't immediately de-authenticate on empty response, could be network glitch
                    return;
                }
                try {
                    const data = JSON.parse(text);
                    root._accessToken = data.access_token;
                    root._tokenExpiry = Math.floor(Date.now() / 1000) + data.expires_in - 60;
                    root.authenticated = true;
                    root._startFetchAll();
                } catch (e) {
                    root.authenticated = false;
                    console.warn("[Gmail] Token parse error:", e);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                if (!root.authenticated) {
                    retryRefreshTimer.start();
                }
            }
        }
    }

    Process {
        id: authProcess
        command: ["python3", Directories.scriptPath + "/email/oauth_server.py"]
        onRunningChanged: {
            if (!running)
                root.authenticating = false;
        }
    }

    function _startFetchAll() {
        syncInbox();
        labelFetcher.command = ["python3", Directories.scriptPath + "/email/fetch_labels.py", _getBestToken(), ""];
        labelFetcher.running = true;
    }

    function syncInbox(force = false) {
        if (!authenticated || _refreshToken === "")
            return;

        if (force)
            inboxMessages.clear();

        let hId = (force || inboxMessages.count === 0) ? "" : historyId;
        let catFlags = (enableUpdates ? "1" : "0") + "," + (enablePromotions ? "1" : "0") + "," + (enableSocials ? "1" : "0");
        inboxFetcher.command = ["python3", Directories.scriptPath + "/email/fetch_emails.py", _getBestToken(), "INBOX", maxEmails.toString(), catFlags, "", hId];
        inboxFetcher.running = true;
    }

    Process {
        id: inboxFetcher
        command: ["echo", "[]"]
        stdout: StdioCollector {
            onStreamFinished: root._populateInbox(text)
        }
    }

    Process {
        id: labelFetcher
        command: ["echo", "{}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    (data.labels || []).forEach(l => {
                        if (l.id === "INBOX")
                            root.inboxUnreadCount = l.messagesUnread || 0;
                    });
                } catch (e) {
                    // console.warn("[Gmail] Labels parse error:", e);
                }
            }
        }
    }

    function _populateInbox(jsonText) {
        if (!jsonText || jsonText.trim().length === 0) {
            inboxMessages.clear();
            return;
        }
        try {
            const res = JSON.parse(jsonText);

            if (res.noChange)
                return;

            const msgs = res.messages || [];

            if (res.historyId)
                root.historyId = res.historyId;

            // Deep comparison — skip the model churn when nothing actually changed
            if (inboxMessages.count === msgs.length) {
                let identical = true;
                for (let i = 0; i < msgs.length; i++) {
                    let oldItem = inboxMessages.get(i);
                    let newItem = msgs[i];

                    if (oldItem.id !== newItem.id || oldItem.unread !== (newItem.unread || false) || oldItem.subject !== (newItem.subject || "(no subject)") || oldItem.snippet !== (newItem.snippet || "")) {
                        identical = false;
                        break;
                    }
                }
                if (identical)
                    return;
            }

            inboxMessages.clear();

            // One row per thread — Gmail returns every message of a thread
            var seenThreads = {};
            msgs.forEach(function (msg) {
                if (msg.threadId) {
                    if (seenThreads[msg.threadId])
                        return;
                    seenThreads[msg.threadId] = true;
                }

                inboxMessages.append({
                    id: msg.id,
                    subject: msg.subject || "(no subject)",
                    from: msg.from || "",
                    date: msg.date || "",
                    snippet: msg.snippet || "",
                    unread: msg.unread || false,
                    timestamp: msg.timestamp || 0
                });
            });
        } catch (e) {
            console.warn("[Gmail] Sync error:", e);
        }
    }
}
