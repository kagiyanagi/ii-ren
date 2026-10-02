pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs.services

Singleton {
    id: root
    property alias agent: polkitAgent
    property alias active: polkitAgent.isActive
    property alias flow: polkitAgent.flow
    // Whether PAM is asking for something right now. It was kept by hand, set when
    // a request began and again after a failure, both of which come before the
    // session has asked for anything, so the field was live while PAM was still
    // starting up or waiting on a fingerprint.
    readonly property bool interactionAvailable: root.flow?.isResponseRequired ?? false
    property string cleanMessage: {
        if (!root.flow) return "";
        return root.flow.message.endsWith(".")
            ? root.flow.message.slice(0, -1)
            : root.flow.message
    }
    property string cleanPrompt: {
        const inputPrompt = PolkitService.flow?.inputPrompt.trim() ?? "";
        const cleanedInputPrompt = inputPrompt.endsWith(":") ? inputPrompt.slice(0, -1) : inputPrompt;
        const usePasswordChars = !PolkitService.flow?.responseVisible ?? true
        return cleanedInputPrompt || (usePasswordChars ? Translation.tr("Password") : Translation.tr("Input"))
    }

    // The flow is deleted the moment it completes, so either of these can land a
    // frame after there is nothing left to answer.
    function cancel() {
        root.flow?.cancelAuthenticationRequest()
    }

    function submit(string) {
        root.flow?.submit(string)
    }

    PolkitAgent {
        id: polkitAgent
    }

    Connections {
        target: root.flow ?? null
        function onAuthenticationFailed() {
            SoundService.playEvent("authFailed");
        }
    }
}
