pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common.functions
import QtCore
import QtQuick
import Quickshell

Singleton {
    // XDG Dirs, with "file://"
    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0]
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0]
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0]
    readonly property string genericCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]
    readonly property string documents: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
    readonly property string downloads: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
    readonly property string music: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
    readonly property string videos: StandardPaths.standardLocations(StandardPaths.MoviesLocation)[0]

    readonly property string cliPath: FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/iiren`)

    // Config paths

    property string generalConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/GeneralConfig.qml`)
    property string barConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/BarConfig.qml`)
    property string backgroundConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/BackgroundConfig.qml`)
    property string interfaceConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/InterfaceConfig.qml`)
    property string servicesConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/ServicesConfig.qml`)
    property string advancedConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/AdvancedConfig.qml`)

    // Other dirs used by the shell, without "file://"
    property string assetsPath: Quickshell.shellPath("assets")
    property string scriptPath: Quickshell.shellPath("scripts")
    property string favicons: FileUtils.trimFileProtocol(`${Directories.cache}/media/favicons`)
    property string coverArt: FileUtils.trimFileProtocol(`${Directories.cache}/media/coverart`)
    property string tempImages: "/tmp/quickshell/media/images"
    property string booruPreviews: FileUtils.trimFileProtocol(`${Directories.cache}/media/boorus`)
    property string booruDownloads: FileUtils.trimFileProtocol(Directories.pictures  + "/homework")
    property string booruDownloadsNsfw: FileUtils.trimFileProtocol(Directories.pictures + "/homework/🌶️")
    property string latexOutput: FileUtils.trimFileProtocol(`${Directories.cache}/media/latex`)
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse`)
    property string shellConfigName: "config.json"
    property string shellConfigPath: `${Directories.shellConfig}/${Directories.shellConfigName}`
	property string todoPath: FileUtils.trimFileProtocol(`${Directories.state}/user/todo.md`)
	property string notesPath: FileUtils.trimFileProtocol(`${Directories.state}/user/notes.json`)
	// finger slot -> custom name. Its own file rather than a config key:
	// the config schema has no shape for a map with arbitrary keys.
	property string fingerprintLabelsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/fingerprint_labels.json`)
	property string conflictCachePath: FileUtils.trimFileProtocol(`${Directories.cache}/conflict-killer`)
    property string notificationsPath: FileUtils.trimFileProtocol(`${Directories.cache}/notifications/notifications.json`)
    property string lyricsPath: FileUtils.trimFileProtocol(`${Directories.cache}/lyrics/lyrics.json`)
    property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/colors.json`)
    property string generatedWallpaperCategoryPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/wallpaper/category.txt`)
    property string cliphistDecode: FileUtils.trimFileProtocol(`/tmp/quickshell/media/cliphist`)
    property string screenshotTemp: "/tmp/quickshell/media/screenshot"
    property string wallpaperSwitchScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/switchwall.sh`)
    property string defaultAiPrompts: Quickshell.shellPath("defaults/ai/prompts")
    property string defaultThemes: Quickshell.shellPath("defaults/themes")
    property string customThemes: `${Directories.shellConfig}/themes`
    property string userAiPrompts: FileUtils.trimFileProtocol(`${Directories.shellConfig}/ai/prompts`)
    property string userActions: FileUtils.trimFileProtocol(`${Directories.shellConfig}/actions`)
    property string aiChats: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats`)
    property string aiTranslationScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/gemini-translate.sh`)
    property string recordScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/record.sh`)
    property string extractColorsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/wallpapers/extract-colors.sh`)
    property string colorCachePath: FileUtils.trimFileProtocol(`${Directories.cache}/wallpapers/colors.json`)
    // Subject-depth cutouts, one PNG per wallpaper. Survives restarts on
    // purpose: regenerating one costs a couple of seconds of CPU.
    property string wallpaperSubjects: FileUtils.trimFileProtocol(`${Directories.cache}/wallpapers/subjects`)
    property string subjectCutoutScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/images/subject-cutout-venv.sh`)
    // switchwall.sh regenerates this whenever a video wallpaper is applied; it
    // is how mpvpaper gets put back after the shell has taken playback over.
    property string videoWallpaperRestoreScript: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/scripts/__restore_video_wallpaper.sh`)
    property string userAvatarPathAccountsService: FileUtils.trimFileProtocol(`/var/lib/AccountsService/icons/${SystemInfo.username}`)
    property string userAvatarPathRicersAndWeirdSystems: FileUtils.trimFileProtocol(`${Directories.home}.face`)
    property string userAvatarPathRicersAndWeirdSystems2: FileUtils.trimFileProtocol(`${Directories.home}.face.icon`)
    property string screenshareStateScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/screenShare/screensharestate.sh`)
    property string screenshareStatePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/screenshare/apps.txt`)
    property string privacyStateScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/privacy/privacystate.py`)
    property string locationServiceScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/privacy/locationservice.sh`)
    property string geniusLyricsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/lyrics/genius-lyrics.js`)
    property string localSendDownloadPath: FileUtils.trimFileProtocol(`${Directories.home}/Downloads/localsend`)

    // Extension system paths
    property string extensionsPath: FileUtils.trimFileProtocol(`${Directories.shellConfig}/extensions`)
    property string extensionsCachePath: `${Directories.extensionsPath}/cache`
    property string extensionsInstalledPath: `${Directories.extensionsPath}/installed`
    property string pluginsJsonPath: `${Directories.extensionsPath}/plugins.json`

    // Third-party desktop widget packs (WidgetExtensionManager)
    property string userWidgetsPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/user_widgets`)
    property string widgetExtensionsPath: `${Directories.shellConfig}/widget_extensions.json`
    property string widgetBackupsPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/user_widgets/.backups`)

    // Cleanup on init
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`])
        Quickshell.execDetached(["mkdir", "-p", `${wallpaperSubjects}`])
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${coverArt}'; find '${coverArt}' -type f -mtime +30 -delete`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${booruPreviews}'; mkdir -p '${booruPreviews}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${latexOutput}'; mkdir -p '${latexOutput}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${cliphistDecode}'; mkdir -p '${cliphistDecode}'`])
        Quickshell.execDetached(["mkdir", "-p", `${aiChats}`])
        Quickshell.execDetached(["mkdir", "-p", `${userActions}`])
        Quickshell.execDetached(["mkdir", "-p", `${Directories.extensionsCachePath}`])
        Quickshell.execDetached(["mkdir", "-p", `${Directories.extensionsInstalledPath}`])
        Quickshell.execDetached(["mkdir", "-p", `${Directories.userWidgetsPath}`])
        Quickshell.execDetached(["rm", "-rf", `${tempImages}`])
    }
}
