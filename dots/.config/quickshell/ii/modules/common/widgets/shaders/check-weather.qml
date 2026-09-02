import QtQuick

// Runnable check for the weather shaders - rain (two passes), fog, snow and
// sun. Renders each effect over a synthetic high-frequency pattern and saves a
// PNG into ./shader-check/.
//
// check.sh then asserts three things. Each effect at full intensity differs
// from the unweathered baseline, and the two rain frames differ from each
// other - which catches a stale bake, a renamed uniform, a texture that failed
// to load, or a `time` that stopped reaching the GPU. And each effect at
// intensity 0 is *identical* to the baseline: the intensity ramp fades the
// effect out by driving that uniform to zero, so anything a shader does that
// intensity does not reach would be left stranded on screen and then pop when
// the pass is torn down. Snow's background tint was exactly that.
//
// Needs a real GPU: the offscreen QPA plugin cannot run ShaderEffect.
Window {
    id: win
    width: 480
    height: 270
    visible: true

    // Two rain frames far enough apart that no drop is where it was, then the
    // same four effects wound down to intensity 0, which must render nothing.
    readonly property var cases: [
        { name: "weather-00-baseline", effect: "none", time: 0 },
        { name: "weather-01-rain",     effect: "rain", time: 3.0 },
        { name: "weather-02-rain-later", effect: "rain", time: 9.0 },
        { name: "weather-03-fog",      effect: "fog",  time: 12.0 },
        { name: "weather-04-snow",     effect: "snow", time: 6.0 },
        { name: "weather-05-sun",      effect: "sun",  time: 4.0 },
        { name: "weather-zero-rain",   effect: "rain", time: 3.0, intensity: 0 },
        { name: "weather-zero-fog",    effect: "fog",  time: 12.0, intensity: 0 },
        { name: "weather-zero-snow",   effect: "snow", time: 6.0, intensity: 0 },
        { name: "weather-zero-sun",    effect: "sun",  time: 4.0, intensity: 0 }
    ]

    property int index: 0
    readonly property var current: win.cases[win.index]
    property int failures: 0

    readonly property real intensity: win.current.intensity ?? 1.0
    // COLOR_GRADING_INTENSITY per effect, scaled by intensity as
    // WeatherEffectBase.setIntensity does.
    readonly property var lutStrengths: ({ rain: 0.3, fog: 0.3, snow: 0.25, sun: 0.18 })
    readonly property real lutIntensity: (win.lutStrengths[win.current.effect] ?? 0) * win.intensity
    readonly property real gridScale: 1.0
    readonly property real aspect: win.width / win.height
    readonly property vector2d resolution: Qt.vector2d(win.width, win.height)

    // FogEffect.update, with the accumulator handed to us rather than integrated.
    readonly property vector4d fogTime: {
        const e = win.current.time;
        const s = e * 0.248;
        return Qt.vector4d(
            0.4 * e * 5 + 0.256 * Math.sin(s),
            0.1 * e * 5 + 0.156 * Math.sin(s) * Math.sin(s),
            0.8 * e * 5 + 0.156 * Math.sin(s + Math.PI / 2),
            0.2 * e * 5 + 0.0156 * Math.sin(s + Math.PI / 3) * Math.sin(s));
    }

    // Deterministic, high frequency and colourful, so every effect has
    // something it can measurably change. Visible and layered on purpose, for
    // the reasons check.qml spells out.
    Item {
        id: pattern
        anchors.fill: parent
        layer.enabled: true

        Grid {
            anchors.fill: parent
            columns: 16
            rows: 9
            Repeater {
                model: 144
                Rectangle {
                    required property int index
                    width: pattern.width / 16
                    height: pattern.height / 9
                    color: Qt.hsva(((index * 37) % 360) / 360, 0.85,
                                   0.25 + ((index * 53) % 60) / 100, 1)
                }
            }
        }
    }

    // AOSP's tileable fog and cloud noise, wrapped so it repeats.
    ShaderEffectSource {
        id: fogSource
        visible: false
        width: 512
        height: 512
        live: false
        hideSource: true
        wrapMode: ShaderEffectSource.Repeat
        sourceItem: Image {
            width: 512
            height: 512
            source: Qt.resolvedUrl("../../../../assets/images/weather/fog.png")
            onStatusChanged: if (status === Image.Error) {
                console.error("fog.png FAILED TO LOAD");
                win.failures++;
            }
        }
    }

    ShaderEffectSource {
        id: cloudsSource
        visible: false
        width: 512
        height: 512
        live: false
        hideSource: true
        wrapMode: ShaderEffectSource.Repeat
        sourceItem: Image {
            width: 512
            height: 512
            source: Qt.resolvedUrl("../../../../assets/images/weather/clouds.png")
            onStatusChanged: if (status === Image.Error) {
                console.error("clouds.png FAILED TO LOAD");
                win.failures++;
            }
        }
    }

    Image {
        id: lutTexture
        visible: false
        source: win.current.effect === "none"
            ? Qt.resolvedUrl("../../../../assets/images/weather/rain_lut.png")
            : Qt.resolvedUrl(`../../../../assets/images/weather/${win.current.effect}_lut.png`)
        onStatusChanged: if (status === Image.Error) {
            console.error("LUT FAILED TO LOAD:", source);
            win.failures++;
        }
    }

    ShaderEffect {
        id: rainShower
        anchors.fill: parent
        visible: win.current.effect === "rain"
        layer.enabled: true
        property variant src: pattern
        property vector2d screenSize: win.resolution
        property real time: win.current.time
        property real screenAspectRatio: win.aspect
        property real gridScale: win.gridScale
        property real intensity: win.intensity
        fragmentShader: Qt.resolvedUrl("weatherRain.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("weatherRain FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: win.current.effect === "rain"
        property variant src: rainShower
        property variant lut: lutTexture
        property vector2d screenSize: win.resolution
        property real time: win.current.time
        property real screenAspectRatio: win.aspect
        property real gridScale: win.gridScale
        property real intensity: win.intensity
        property real lutIntensity: win.lutIntensity
        fragmentShader: Qt.resolvedUrl("weatherRainGlass.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("weatherRainGlass FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: win.current.effect === "snow"
        property variant src: pattern
        property variant lut: lutTexture
        property vector2d screenSize: win.resolution
        property vector2d gridSize: Qt.vector2d(7 * win.gridScale, 2 * win.gridScale)
        property real time: win.current.time
        property real screenAspectRatio: win.aspect
        property real intensity: win.intensity
        property real lutIntensity: win.lutIntensity
        fragmentShader: Qt.resolvedUrl("weatherSnow.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("weatherSnow FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: win.current.effect === "sun"
        property variant src: pattern
        property variant lut: lutTexture
        property vector2d screenSize: win.resolution
        property real time: win.current.time
        property real intensity: win.intensity
        property real lutIntensity: win.lutIntensity
        fragmentShader: Qt.resolvedUrl("weatherSun.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("weatherSun FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: win.current.effect === "fog"
        property variant src: pattern
        property variant fogTex: fogSource
        property variant cloudsTex: cloudsSource
        property variant lut: lutTexture
        property vector4d time: win.fogTime
        property vector2d screenSize: win.resolution
        property vector2d fogSize: Qt.vector2d(win.gridScale * 512, win.gridScale * 512)
        property vector2d cloudsSize: Qt.vector2d(win.gridScale * 512, win.gridScale * 512)
        property real screenAspectRatio: win.aspect
        property real pixelDensity: 2.625
        property real intensity: win.intensity
        property real lutIntensity: win.lutIntensity
        fragmentShader: Qt.resolvedUrl("weatherFog.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("weatherFog FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    // One grab per case, then advance. 250ms is slack for the bake + upload.
    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            const name = win.current.name;
            win.contentItem.grabToImage(result => {
                if (!result.saveToFile("shader-check/" + name + ".png")) {
                    console.error("could not save", name);
                    win.failures++;
                }
                if (win.index + 1 >= win.cases.length) {
                    console.log(win.failures === 0
                        ? "rendered " + win.cases.length + " weather cases"
                        : win.failures + " FAILURES");
                    Qt.exit(win.failures === 0 ? 0 : 1);
                } else {
                    win.index++;
                }
            });
        }
    }

    Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.error("timed out at case", win.index);
            Qt.exit(1);
        }
    }
}
