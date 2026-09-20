import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common

GridLayout {
    id: root

    // Internal animation control
    property bool startAnim: false

    // Siblings entering together are staggerStep apart (DESIGN.md 2.8). The
    // delays are constant per tile, so each card just binds them -- the reset
    // ladder that used to set them by hand on every open drove nothing the
    // cards' own onStartAnimChanged does not already do.
    MetricCard {
        title: Translation.tr("Sunrise")
        symbol: "wb_twilight"
        value: Weather.data.sunrise
        accentColor: Appearance.colors.colTertiaryContainer
        symbolColor: Appearance.colors.colOnTertiaryContainer
        startAnim: root.startAnim
        animDelay: 0
    }
    MetricCard {
        title: Translation.tr("Sunset")
        symbol: "bedtime"
        value: Weather.data.sunset
        accentColor: Appearance.colors.colSecondaryContainer
        symbolColor: Appearance.colors.colOnSecondaryContainer
        startAnim: root.startAnim
        animDelay: Appearance.animation.staggerStep
    }
    MetricCard {
        title: Translation.tr("Precipitation")
        symbol: "rainy_light"
        value: Weather.data.precip
        accentColor: Appearance.colors.colPrimaryContainer
        symbolColor: Appearance.colors.colOnPrimaryContainer
        startAnim: root.startAnim
        animDelay: Appearance.animation.staggerStep * 2
    }
    MetricCard {
        title: Translation.tr("Humidity")
        symbol: "humidity_low"
        value: Weather.data.humidity
        accentColor: Appearance.colors.colTertiaryContainer
        symbolColor: Appearance.colors.colOnTertiaryContainer
        startAnim: root.startAnim
        animDelay: Appearance.animation.staggerStep * 3
    }
}
