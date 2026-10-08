pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LocalSend service for receiving/sending files.
 *
 * The protocol lives in `scripts/localsend/localsend.py` — stdlib Python
 * speaking LocalSend v2 (multicast announce + the HTTP endpoints) and
 * streaming one JSON event per line. The old `localsend-cli` pip package it
 * replaced is abandoned, and calling the helper by absolute path also drops
 * the `bash -lc` PATH dance that finding it on $PATH used to need.
 */
Singleton {
    id: root

    readonly property string helperPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/localsend/localsend.py"))
    property bool available: false
    // Set from shell.qml only: the settings app loads this singleton too, and a
    // second receiver there would announce this machine to phones twice.
    property bool live: false
    property bool serverRunning: receiveProc.running
    // The on/off switch itself, so the receiver comes back after a restart in
    // whatever state it was left.
    readonly property bool enabled: Config.ready && Config.options.localsend.autoStart
    property string downloadPath: Config.options?.localsend?.downloadPath
    property bool showNotifications: Config.options?.localsend?.showNotifications ?? true

    // Receive state
    property var currentTransfer: null
    property list<var> pendingTransfers: []

    // Send state
    property list<var> droppedFiles: []
    property list<var> discoveredDevices: []
    property bool sending: false

    signal transferRequested(var transfer)
    signal transferStarted(var transfer)
    signal transferCompleted(var transfer)
    signal transferCancelled(var transfer)
    signal sendCompleted()
    signal sendFailed(string message)

    function addDroppedFile(fileUrl: string): void {
        const cleanPath = fileUrl.toString().replace(/^file:\/\//, "")
        const name = cleanPath.split("/").pop() || "unknown"
        for (let i = 0; i < root.droppedFiles.length; i++) {
            if (root.droppedFiles[i].path === cleanPath) return
        }
        const newList = root.droppedFiles.slice()
        newList.push({ path: cleanPath, name: name, size: 0 })
        root.droppedFiles = newList
    }

    function removeDroppedFile(index: int): void {
        const newList = root.droppedFiles.slice()
        newList.splice(index, 1)
        root.droppedFiles = newList
    }

    function clearDroppedFiles(): void {
        root.droppedFiles = []
    }

    function formatFileSize(bytes: int): string {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    }

    function sendToDevice(deviceIp: string): void {
        if (!root.available || root.sending || root.droppedFiles.length === 0) return
        root.sending = true
        const filePaths = root.droppedFiles.map(f => f.path)
        sendProc.command = ["python3", root.helperPath, "send", deviceIp].concat(filePaths)
        sendProc.running = true
    }

    // Check that the helper can run at all
    Process {
        id: checkAvailabilityProc
        running: true
        command: ["python3", root.helperPath, "check"]
        onExited: (exitCode, exitStatus) => root.available = (exitCode === 0)
    }

    // Notification process for incoming transfers
    Process {
        id: notificationProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text === "") return
                const action = this.text.trim()
                console.log("[LocalSend] Notification action received:", action)
                if (action === "accept") {
                    root.acceptTransfer()
                } else if (action === "deny") {
                    root.denyTransfer()
                }
            }
        }
    }

    function showIncomingNotification(transfer: var): void {
        const fileNames = transfer.files.map(f => f.name).join(", ")
        const fileSizes = transfer.files.map(f => {
            const size = f.size || 0
            if (size < 1024) return size + " B"
            if (size < 1024 * 1024) return (size / 1024).toFixed(1) + " KB"
            return (size / (1024 * 1024)).toFixed(1) + " MB"
        }).join(", ")

        notificationProc.command = [
            "notify-send",
            Translation.tr("LocalSend: Incoming Transfer"),
            Translation.tr("From: %1\n%2 (%3)").arg(transfer.sender).arg(fileNames).arg(fileSizes),
            "-A", `accept=${Translation.tr("Accept")}`,
            "-A", `deny=${Translation.tr("Deny")}`,
            "-a", "LocalSend",
        ]
        notificationProc.running = true
    }

    // Main receive server process. KeepAliveProcess runs it under
    // --pdeathsig, so it dies with the shell instead of outliving it.
    KeepAliveProcess {
        id: receiveProc
        wanted: root.live && root.available && root.enabled
        args: ["python3", root.helperPath, "receive", "--output", root.downloadPath]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                if (!line || line.trim().length === 0) return
                try {
                    const event = JSON.parse(line)
                    root.handleLocalSendEvent(event)
                } catch (e) {
                    console.error("[LocalSend] Failed to parse JSON:", line, e)
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                console.log("[LocalSend] stderr:", line)
            }
        }
    }

    // Send process for sending files to a device
    Process {
        id: sendProc
        running: false

        stdout: SplitParser {
            onRead: line => {
                if (!line || line.trim().length === 0) return
                console.log("[LocalSend] Send progress:", line)
                try {
                    const event = JSON.parse(line)
                    if (event.event === "completed" || event.event === "saved" || event.event === "done") {
                        root.clearDroppedFiles()
                        root.sendCompleted()
                    } else if (event.event === "cancelled" || event.error) {
                        root.sendFailed(event.error || "Transfer cancelled")
                    }
                } catch (e) {
                    console.log("[LocalSend] Failed to parse send line:", line, e)
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                console.log("[LocalSend] Send stderr:", line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.sending = false
            if (exitCode !== 0) {
                root.sendFailed("Send process exited with code: " + exitCode)
            }
        }
    }

    function handleLocalSendEvent(event: var): void {
        if (!event) return
        if (event.error) {
            console.warn("[LocalSend]", event.error)
            Quickshell.execDetached(["notify-send", Translation.tr("LocalSend error"), event.error, "-a", "LocalSend"])
            // Something else holds the port (the LocalSend app); retrying would
            // repeat this notification every minute.
            if (event.error.startsWith("cannot bind")) root.stopServer()
            return
        }
        if (!event.event) return
        console.log("[LocalSend] Event:", JSON.stringify(event))

        switch (event.event) {
            case "device":
                console.log("[LocalSend] Device registered:", event.alias, event.ip)
                if (event.ip) {
                    const newList = root.discoveredDevices.slice()
                    let found = false
                    for (let i = 0; i < newList.length; i++) {
                        if (newList[i].ip === event.ip) { found = true; break }
                    }
                    if (!found) {
                        newList.push({
                            ip: event.ip,
                            name: event.alias || event.name || "Unknown",
                            port: event.port || 53317
                        })
                        root.discoveredDevices = newList
                    }
                }
                break

            case "incoming":
                const transfer = {
                    sender: event.sender || "Unknown",
                    senderIp: event.ip || "",
                    files: event.files || [],
                    isText: event.is_text || false,
                    sessionId: ""
                }
                root.currentTransfer = transfer
                root.pendingTransfers.push(transfer)
                root.transferRequested(transfer)
                break

            case "prompt":
                console.log("[LocalSend] Prompt received, showing notification")
                if (root.currentTransfer) {
                    root.showIncomingNotification(root.currentTransfer)
                }
                break

            case "text":
                const textTransfer = {
                    sender: event.sender || "Unknown",
                    text: event.text || "",
                    timestamp: Date.now()
                }
                root.transferCompleted(textTransfer)
                if (root.showNotifications) {
                    Quickshell.execDetached([
                        "notify-send",
                        Translation.tr("LocalSend: Text Received"),
                        Translation.tr("From: %1\n%2").arg(event.sender || "Unknown").arg(event.text || ""),
                        "-a", "LocalSend",
                    ])
                }
                root.currentTransfer = null
                break

            case "saved":
                console.log("[LocalSend] File saved:", event.path || "unknown path")
                const fileTransfer = {
                    sender: event.sender || "Unknown",
                    fileName: event.name || "",
                    filePath: event.path || root.downloadPath + "/" + (event.name || ""),
                    fileSize: event.size || 0,
                    timestamp: Date.now()
                }
                root.transferCompleted(fileTransfer)
                if (root.showNotifications) {
                    Quickshell.execDetached([
                        "notify-send",
                        Translation.tr("LocalSend: File Received"),
                        Translation.tr("From: %1\nOutput path: %2").arg(event.sender || "Unknown").arg(event.path || "unknown path"),
                        "-a", "LocalSend",
                    ])
                }
                root.currentTransfer = null
                break

            case "cancelled":
                root.transferCancelled(event)
                root.currentTransfer = null
                break
        }
    }
    
    function startServer(): void {
        if (!root.available) {
            Quickshell.execDetached(["notify-send", Translation.tr("LocalSend error"), Translation.tr("The LocalSend helper could not run. It needs <tt>python3</tt>."), "-a", "LocalSend"])
            return
        }
        Config.options.localsend.autoStart = true
    }

    function stopServer(): void {
        Config.options.localsend.autoStart = false
    }

    function acceptTransfer(): void {
        console.log("[LocalSend] Accepting transfer...")
        receiveProc.write("y\n")
        root.currentTransfer = null
    }

    function denyTransfer(): void {
        console.log("[LocalSend] Denying transfer...")
        root.currentTransfer = null
        receiveProc.write("n\n")
    }

    // The new path is already in args; KeepAliveProcess starts it again.
    onDownloadPathChanged: if (receiveProc.running) receiveProc.running = false

    IpcHandler {
        target: "localsend"

        function start(): void {
            root.startServer()
        }

        function stop(): void {
            root.stopServer()
        }

        function status(): string {
            return JSON.stringify({
                available: root.available,
                running: root.serverRunning,
                downloadPath: root.downloadPath
            })
        }
    }
}
