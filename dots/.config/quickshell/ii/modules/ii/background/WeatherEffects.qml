pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick

// Android's live weather wallpaper effects, drawn over the finished desktop.
//
// This is AOSP's `weathereffects` library (frameworks/libs/systemui) ported to
// Qt: the same AGSL, the same textures, the same LUTs. The shaders live in
// modules/common/widgets/shaders/weather*.frag and each one names the AOSP file
// it came from.
//
// Where the ROM composites the effect between the wallpaper and its cut-out
// subject, this sits at the very top of the desktop plane - over the wallpaper
// effects, over the widgets, over subject depth. So the scene underneath is
// what the shaders take as their "background", their "foreground" is empty, and
// the two subject-shaped pieces of the ROM's version (rain splashes off the
// subject's outline, snow piling on its shoulders) have nothing to key off and
// are left out. Everything else is theirs, number for number.
//
// It renders the desktop through a shader every frame, which is the price of a
// live effect; nothing here runs unless the user turns it on.
Item {
    id: root

    // Everything that should end up underneath the weather.
    required property Item scene

    // Desktop and lock screen target independently, lock mirroring desktop
    // unless told not to - same split as the wallpaper effects above it.
    readonly property var opt: GlobalStates.screenLocked
        ? (Config.options.background.weatherEffects.lock.sync
            ? Config.options.background.weatherEffects.desktop : Config.options.background.weatherEffects.lock)
        : Config.options.background.weatherEffects.desktop

    // "rain", "fog", "snow", "sun", or empty for nothing.
    readonly property string effect: {
        if (!Config.ready || !root.opt.enable)
            return "";
        if (root.opt.followWeather)
            return Weather.liveEffect;
        return root.opt.effect;
    }

    // While following the weather the conditions set this outright, and the
    // settings slider becomes a readout of it rather than a ceiling over it -
    // a slider that never moved while the sky changed read as broken.
    readonly property real intensity: Math.max(0, Math.min(1, root.opt.followWeather
        ? Weather.liveIntensity
        : root.opt.intensity / 100))

    // True while the effect is drawing the scene itself, so the desktop knows
    // to stop drawing it and a video wallpaper knows to play in-process.
    readonly property bool takesOver: root.effect.length > 0

    // AOSP's GraphicsUtils.computeDefaultGridSize, with Android's own xxhdpi
    // density as the reference: at that density a 1080px-wide strip of screen
    // gets exactly the drop count a Pixel gets, and a wider panel gets
    // proportionally more, which is what their bucketing is for. A monitor is
    // viewed from further away than a phone, so the scale option is the knob
    // for taste.
    readonly property real gridScale: {
        const widthDp = Math.max(1, root.width) / 2.625;
        const bucket = widthDp < 600 ? 1.0 : (widthDp < 840 ? 0.9 : 0.8);
        return bucket * widthDp / (1080 / 2.625) * (root.opt.scale / 100);
    }

    readonly property real aspect: root.width / Math.max(1, root.height)
    readonly property vector2d resolution: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))

    // AOSP's per-effect colour grading strengths, scaled by intensity exactly
    // as WeatherEffectBase.setIntensity does.
    // COLOR_GRADING_INTENSITY from each of AOSP's *EffectConfig companions.
    readonly property var lutStrengths: ({ rain: 0.3, fog: 0.3, snow: 0.25, sun: 0.18 })
    readonly property real lutIntensity: !root.opt.colorGrading ? 0
        : (root.lutStrengths[root.effect] ?? 0) * root.intensity

    /* Clock. AOSP integrates its own elapsed time per effect rather than using
     * the frame clock directly, because two of the three warp it. */
    property real elapsed: 0

    // SnowEffect.setIntensity: the flakes speed up as they thin out, or the
    // few that are left look like they are floating.
    readonly property real speed: root.effect === "snow"
        ? 2.5 + (1.7 - 2.5) * root.intensity
        : 1

    // FogEffect.update, which drives four scrolling offsets off one wandering
    // accumulator.
    readonly property vector4d fogTime: {
        const e = root.elapsed;
        const s = e * 0.248;
        return Qt.vector4d(
            0.4 * e * 5 + 0.256 * Math.sin(s),
            0.1 * e * 5 + 0.156 * Math.sin(s) * Math.sin(s),
            0.8 * e * 5 + 0.156 * Math.sin(s + Math.PI / 2),
            0.2 * e * 5 + 0.0156 * Math.sin(s + Math.PI / 3) * Math.sin(s));
    }

    // WeatherEffectBase.reset(): start somewhere random so two monitors, or two
    // sessions, are not raining in lockstep.
    onTakesOverChanged: if (root.takesOver) root.elapsed = Math.random() * 90

    FrameAnimation {
        running: root.takesOver && root.visible
        onTriggered: {
            // A stalled frame must not teleport the rain across the screen.
            const dt = Math.min(frameTime, 0.1);
            if (root.effect === "fog") {
                // Variation range [0.4, 1]; AOSP does not want it to reach 0.
                const t = elapsedTime;
                root.elapsed += (Math.sin(0.06 * t + Math.sin(0.18 * t)) * 0.3 + 0.7) * dt;
            } else {
                root.elapsed += root.speed * dt;
            }
            // ponytail: the shaders multiply this by up to 27 and then take
            // fract() of it, so a float32 uniform runs out of mantissa after a
            // few hours and the motion starts to step. Wrapping costs one
            // scrambled frame an hour; a phone never hits this because the
            // wallpaper engine is torn down constantly. Split the time into a
            // coarse and a fine uniform if the wrap ever gets noticed.
            if (root.elapsed > 3600)
                root.elapsed -= 3600;
        }
    }

    // The desktop, as the shaders' background. Hidden from the screen only once
    // the effect is fully faded in - during the fade both are on screen, and
    // since the shader output *contains* the scene, that reads as a cross-fade
    // between the plain desktop and the weathered one.
    ShaderEffectSource {
        id: sceneTexture
        anchors.fill: parent
        visible: false
        live: true
        hideSource: chain.opacity >= 1
        sourceItem: chain.active ? root.scene : null
    }

    // AOSP's tileable noise, straight from weathereffects/graphics/assets.
    // Loaded through a Repeat-wrapped source because an Image clamps.
    Loader {
        id: fogTextures
        active: chain.active && root.effect === "fog"
        sourceComponent: Item {
            readonly property alias fog: fogSource
            readonly property alias clouds: cloudsSource
            ShaderEffectSource {
                id: fogSource
                width: 512
                height: 512
                live: false
                hideSource: true
                wrapMode: ShaderEffectSource.Repeat
                sourceItem: Image {
                    width: 512
                    height: 512
                    source: Qt.resolvedUrl("../../../assets/images/weather/fog.png")
                }
            }
            ShaderEffectSource {
                id: cloudsSource
                width: 512
                height: 512
                live: false
                hideSource: true
                wrapMode: ShaderEffectSource.Repeat
                sourceItem: Image {
                    width: 512
                    height: 512
                    source: Qt.resolvedUrl("../../../assets/images/weather/clouds.png")
                }
            }
        }
    }

    Image {
        id: lutTexture
        visible: false
        source: root.effect.length > 0
            ? Qt.resolvedUrl(`../../../assets/images/weather/${root.effect}_lut.png`)
            : ""
    }

    Loader {
        id: chain
        anchors.fill: parent
        active: opacity > 0
        visible: opacity > 0
        opacity: root.takesOver ? 1 : 0
        sourceComponent: root.effect === "fog" ? fogComponent
            : root.effect === "snow" ? snowComponent
            : root.effect === "sun" ? sunComponent
            : rainComponent

        // Opacity is an effect, so neither direction may overshoot. A
        // screen-sized surface arriving is slow effects; leaving is fast.
        Behavior on opacity {
            NumberAnimation {
                duration: root.takesOver
                    ? Appearance.animationCurves.expressiveSlowEffectsDuration
                    : Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
    }

    // Rain is two passes, as it is on Android: the shower through the scene,
    // then the drops on the glass refracting what the first pass produced.
    Component {
        id: rainComponent
        Item {
            ShaderEffect {
                id: shower
                anchors.fill: parent
                property variant src: sceneTexture
                property vector2d screenSize: root.resolution
                property real time: root.elapsed
                property real screenAspectRatio: root.aspect
                property real gridScale: root.gridScale
                property real intensity: root.intensity
                fragmentShader: Qt.resolvedUrl("../../common/widgets/shaders/weatherRain.frag.qsb")
            }

            ShaderEffect {
                anchors.fill: parent
                property variant src: showerTexture
                property variant lut: lutTexture
                property vector2d screenSize: root.resolution
                property real time: root.elapsed
                property real screenAspectRatio: root.aspect
                property real gridScale: root.gridScale
                property real intensity: root.intensity
                property real lutIntensity: root.lutIntensity
                fragmentShader: Qt.resolvedUrl("../../common/widgets/shaders/weatherRainGlass.frag.qsb")

                ShaderEffectSource {
                    id: showerTexture
                    anchors.fill: parent
                    visible: false
                    live: true
                    hideSource: true
                    sourceItem: shower
                }
            }
        }
    }

    Component {
        id: snowComponent
        ShaderEffect {
            anchors.fill: parent
            property variant src: sceneTexture
            property variant lut: lutTexture
            property vector2d screenSize: root.resolution
            // SnowEffect.updateGridSize.
            property vector2d gridSize: Qt.vector2d(7 * root.gridScale, 2 * root.gridScale)
            property real time: root.elapsed
            property real screenAspectRatio: root.aspect
            property real intensity: root.intensity
            property real lutIntensity: root.lutIntensity
            fragmentShader: Qt.resolvedUrl("../../common/widgets/shaders/weatherSnow.frag.qsb")
        }
    }

    Component {
        id: sunComponent
        ShaderEffect {
            anchors.fill: parent
            property variant src: sceneTexture
            property variant lut: lutTexture
            property vector2d screenSize: root.resolution
            property real time: root.elapsed
            // No screenAspectRatio: the sun shader derives its own units from
            // screenSize, for the reason its header sets out.
            property real intensity: root.intensity
            property real lutIntensity: root.lutIntensity
            fragmentShader: Qt.resolvedUrl("../../common/widgets/shaders/weatherSun.frag.qsb")
        }
    }

    Component {
        id: fogComponent
        ShaderEffect {
            anchors.fill: parent
            property variant src: sceneTexture
            property variant fogTex: fogTextures.item?.fog ?? null
            property variant cloudsTex: fogTextures.item?.clouds ?? null
            property variant lut: lutTexture
            property vector4d time: root.fogTime
            property vector2d screenSize: root.resolution
            // FogEffect.updateGridSize: the grid scale in texels of a 512px tile.
            property vector2d fogSize: Qt.vector2d(root.gridScale * 512, root.gridScale * 512)
            property vector2d cloudsSize: Qt.vector2d(root.gridScale * 512, root.gridScale * 512)
            property real screenAspectRatio: root.aspect
            // The density AOSP calibrated its dither against.
            property real pixelDensity: 2.625
            property real intensity: root.intensity
            property real lutIntensity: root.lutIntensity
            fragmentShader: Qt.resolvedUrl("../../common/widgets/shaders/weatherFog.frag.qsb")
        }
    }
}
