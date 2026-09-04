pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root

    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    
    // For backward compatibility and UI settings
    property bool gpsActive: Config.options.bar.weather.enableGPS
    // Matches fallbackTimer: past this we give up and use IP-based location.
    readonly property int fixTimeout: 5000
    readonly property string city: Config.options.bar.weather.city

    // Config settling at startup flips city/units from their defaults, which looks
    // identical to a user changing them. WeatherPopup already fetches on its own at
    // startup, so a forced fetch here would bypass the rate limit and double up.
    // Coalesce, then only force when the request differs from what was last fetched.
    readonly property string fetchKey: `${root.city}|${root.useUSCS}|${root.gpsActive}`
    property string lastFetchedKey: ""

    function requestRefetch() {
        refetchDebounce.restart();
    }

    Timer {
        id: refetchDebounce
        interval: 250
        repeat: false
        onTriggered: {
            if (root.fetchKey === root.lastFetchedKey)
                return;
            root.getData(true);
        }
    }

    onUseUSCSChanged: requestRefetch()
    onCityChanged: requestRefetch()
    onGpsActiveChanged: {
        if (root.gpsActive) {
            // Arm the fallback here too: GPS can be switched on after the
            // singleton was built (config settling at startup does exactly
            // that), and without this the request hangs with nothing to catch it.
            positionSource.update(root.fixTimeout);
            fallbackTimer.restart();
        } else {
            root.stopPositionFix();
            requestRefetch();
        }
    }
    onFetchIntervalChanged: {
        timer.restart();
    }

    property var location: ({
        valid: false,
        lat: 0,
        lon: 0,
        city: ""
    })

    property var data: ({
        uv: 0,
        humidity: "0%",
        sunrise: "00:00",
        sunset: "00:00",
        windDir: "N",
        wCode: 113,
        wDesc: "",
        city: "City",
        wind: "0 km/h",
        precip: "0 mm",
        visib: "0 km",
        press: "0 hPa",
        temp: "0°C",
        tempFeelsLike: "0°C",
        lastRefresh: "00:00",
        isDay: 1,
        wmoCode: -1,
    })

    // The Android wallpaper effect the current conditions call for, and how
    // hard it should come down. AOSP's weathereffects library ships four:
    // rain, fog, snow and sun. Which one a condition maps to is the ROM's
    // business, so this is the WMO table Open-Meteo returns split the way
    // Android's own weather app splits it.
    //
    // Sun is the one that needs a second input: god rays and a lens flare at
    // two in the morning are absurd, so a clear sky only lights up in daylight
    // and an overcast one (WMO 3) gets nothing either way.
    readonly property string liveEffect: {
        const c = root.data?.wmoCode ?? -1;
        if (c >= 0 && c <= 2) return root.isNight ? "" : "sun";   // clear, mainly clear, partly cloudy
        if (c === 45 || c === 48) return "fog";                   // fog, rime fog
        if (c >= 51 && c <= 57) return "rain";                    // drizzle
        if (c >= 61 && c <= 67) return "rain";                    // rain, freezing rain
        if (c >= 71 && c <= 77) return "snow";                    // snow, snow grains
        if (c >= 80 && c <= 82) return "rain";                    // rain showers
        if (c === 85 || c === 86) return "snow";                  // snow showers
        if (c >= 95) return "rain";                               // thunderstorm
        return "";
    }

    // 0..1, following the WMO code's own slight/moderate/heavy grading. For sun
    // it is how much sky is left: cloud cover dims the rays.
    readonly property real liveIntensity: {
        const c = root.data?.wmoCode ?? -1;
        const table = {
            0: 1.0, 1: 0.75, 2: 0.45,
            45: 0.8, 48: 1.0,
            51: 0.3, 53: 0.4, 55: 0.5, 56: 0.45, 57: 0.5,
            61: 0.5, 63: 0.7, 65: 1.0, 66: 0.7, 67: 0.9,
            71: 0.4, 73: 0.7, 75: 1.0, 77: 0.35,
            80: 0.6, 81: 0.8, 82: 1.0,
            85: 0.6, 86: 0.9,
            95: 0.9, 96: 1.0, 99: 1.0
        };
        return table[c] ?? 0;
    }

    readonly property bool isNight: {
        if (root.data && root.data.isDay !== undefined) {
            return root.data.isDay === 0;
        }
        if (DateTime.clock && DateTime.clock.date) {
            const hour = DateTime.clock.date.getHours();
            return hour >= 18 || hour < 6;
        }
        return false;
    }

    // Forecast data properties consumed by popup/cards
    property var forecastData: []
    property var hourlyData: []
    property bool forecastLoading: true

    function wmoToWwo(wmo) {
        if (wmo === 0 || wmo === 1) return 113; // Clear
        if (wmo === 2) return 116; // Partly Cloudy
        if (wmo === 3) return 122; // Overcast
        if (wmo === 45 || wmo === 48) return 248; // Fog
        if (wmo === 51 || wmo === 53 || wmo === 55) return 266; // Drizzle
        if (wmo === 56 || wmo === 57) return 284; // Freezing Drizzle
        if (wmo === 61 || wmo === 63 || wmo === 65) return 296; // Rain
        if (wmo === 66 || wmo === 67) return 311; // Freezing Rain
        if (wmo === 71 || wmo === 73 || wmo === 75 || wmo === 77) return 332; // Snow
        if (wmo === 80 || wmo === 81 || wmo === 82) return 353; // Rain Showers
        if (wmo === 85 || wmo === 86) return 368; // Snow Showers
        if (wmo === 95) return 386; // Thunderstorm
        if (wmo === 96 || wmo === 99) return 389; // Thunderstorm with hail
        return 113;
    }

    function degreesToCompass(deg) {
        const val = Math.floor((deg / 22.5) + 0.5);
        const arr = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        return arr[(val % 16)];
    }

    function formatTime(isoStr) {
        if (!isoStr) return "00:00";
        const parts = isoStr.split("T");
        if (parts.length < 2) return isoStr;
        let timeStr = parts[1];
        
        let uses12h = Config.options.time.format.toLowerCase().includes("a");
        if (uses12h) {
            let t = timeStr.split(":");
            if (t.length >= 2) {
                let h = parseInt(t[0]);
                let ampm = h >= 12 ? "PM" : "AM";
                h = h % 12;
                if (h === 0) h = 12;
                return h + ":" + t[1] + " " + ampm;
            }
        }
        return timeStr;
    }

    function getWeatherDescription(code) {
        const codeInt = parseInt(code);
        const descriptions = {
            "113": Translation.tr("Clear"),
            "116": Translation.tr("Partly Cloudy"),
            "119": Translation.tr("Cloudy"),
            "122": Translation.tr("Overcast"),
            "143": Translation.tr("Mist"),
            "176": Translation.tr("Patchy Rain"),
            "200": Translation.tr("Thundery Outbreaks"),
            "248": Translation.tr("Fog"),
            "266": Translation.tr("Light Drizzle"),
            "296": Translation.tr("Light Rain"),
            "302": Translation.tr("Moderate Rain"),
            "308": Translation.tr("Heavy Rain"),
            "326": Translation.tr("Light Snow"),
            "332": Translation.tr("Moderate Snow"),
            "338": Translation.tr("Heavy Snow"),
            "353": Translation.tr("Light Rain Shower"),
            "389": Translation.tr("Heavy Rain with Thunder")
        };

        if (descriptions[code]) {
            return descriptions[code];
        }

        let keys = Object.keys(descriptions).map(Number).sort((a, b) => a - b);
        let bestMatch = keys[0];

        for (let i = 0; i < keys.length; i++) {
            if (codeInt >= keys[i]) {
                bestMatch = keys[i];
            } else {
                break;
            }
        }

        return descriptions[bestMatch.toString()] || Translation.tr("Unknown");
    }

    function refineData(wData, cityName) {
        let temp = {};
        const current = wData.current;
        const daily = wData.daily;
        const hourly = wData.hourly;

        temp.uv = current.uv_index;
        temp.humidity = current.relative_humidity_2m + "%";
        temp.sunrise = formatTime(daily.sunrise[0]);
        temp.sunset = formatTime(daily.sunset[0]);
        temp.windDir = degreesToCompass(current.wind_direction_10m);
        temp.wCode = wmoToWwo(current.weather_code);
        temp.wmoCode = current.weather_code;
        temp.wDesc = getWeatherDescription(temp.wCode);
        temp.city = cityName;
        temp.isDay = current.is_day !== undefined ? current.is_day : 1;
        
        if (root.useUSCS) {
            temp.wind = Math.round(current.wind_speed_10m * 0.621371) + " mph";
            temp.precip = (current.precipitation * 0.0393701).toFixed(2) + " in";
            temp.visib = (current.visibility / 1609.34).toFixed(1) + " mi";
            temp.press = Math.round(current.pressure_msl) + " hPa"; 
            temp.temp = Math.round(current.temperature_2m * 9 / 5 + 32) + "°F";
            temp.tempFeelsLike = Math.round(current.apparent_temperature * 9 / 5 + 32) + "°F";
        } else {
            temp.wind = Math.round(current.wind_speed_10m) + " km/h";
            temp.precip = current.precipitation.toFixed(1) + " mm";
            temp.visib = (current.visibility / 1000).toFixed(1) + " km";
            temp.press = Math.round(current.pressure_msl) + " hPa";
            temp.temp = Math.round(current.temperature_2m) + "°C";
            temp.tempFeelsLike = Math.round(current.apparent_temperature) + "°C";
        }
        
        temp.lastRefresh = DateTime.time + " • " + DateTime.date;
        root.data = temp;
        console.info(`[WeatherService] Successfully fetched weather for ${cityName}: ${temp.temp}, ${temp.wDesc}`);

        // Parse forecastData (daily)
        let forecastList = [];
        if (daily && daily.time) {
            for (let i = 0; i < daily.time.length; i++) {
                let maxC = daily.temperature_2m_max[i];
                let minC = daily.temperature_2m_min[i];
                let maxF = maxC * 9 / 5 + 32;
                let minF = minC * 9 / 5 + 32;
                forecastList.push({
                    date: daily.time[i],
                    maxC: Math.round(maxC),
                    minC: Math.round(minC),
                    maxF: Math.round(maxF),
                    minF: Math.round(minF),
                    code: wmoToWwo(daily.weather_code[i])
                });
            }
        }
        root.forecastData = forecastList;

        // Parse hourlyData (3-hour slots)
        let hourlyList = [];
        if (hourly && hourly.time) {
            // Pick hourly slots every 3 hours for up to 48 hours (current day and next day)
            for (let i = 0; i < Math.min(hourly.time.length, 48); i++) {
                const hourOfDay = i % 24;
                if (hourOfDay % 3 === 0) {
                    let tempC = hourly.temperature_2m[i];
                    let tempF = tempC * 9 / 5 + 32;
                    hourlyList.push({
                        time: (hourOfDay * 100).toString(),
                        tempC: Math.round(tempC).toString(),
                        tempF: Math.round(tempF).toString(),
                        code: wmoToWwo(hourly.weather_code[i]).toString(),
                        isNight: (hourly.is_day && hourly.is_day[i] !== undefined) ? hourly.is_day[i] === 0 : (hourOfDay >= 18 || hourOfDay < 6)
                    });
                }
            }
        }
        root.hourlyData = hourlyList;
        root.forecastLoading = false;
    }

    property double lastFetchTimestamp: 0

    // Two problems, one place. A local `const xhr` is only reachable from the
    // JS stack, so once the function returns the engine may collect it
    // mid-flight and the response is dropped with no readyState change and
    // nothing logged; and firing a second request for the same endpoint while
    // the first is still open (two GPS fixes in a row do exactly that) stalls
    // both indefinitely. So: hold a reference until the request settles, refuse
    // a duplicate while one is open, and abort on a deadline of our own -
    // Qt's QML XMLHttpRequest ignores `timeout`/`ontimeout`.
    property var pendingRequests: ({})
    readonly property int requestTimeout: 8000
    readonly property int requestRetries: 2
    // Connections to the weather APIs stall outright a good fraction of the
    // time on a long path, and the stalls come in bursts, so an immediate
    // retry tends to land in the same bad window. Space them out, and if the
    // whole round still fails, re-arm well before the next poll rather than
    // leaving the widgets on placeholder data for a full fetch interval.
    readonly property int retryDelay: 5000
    readonly property int roundRetryDelay: 60000

    function request(url, label, onSuccess, attempt = 0) {
        if (attempt === 0 && root.pendingRequests[label])
            return;

        const xhr = new XMLHttpRequest();
        const deadline = deadlineComponent.createObject(root, {
            interval: root.requestTimeout
        });
        root.pendingRequests[label] = xhr;

        const settle = () => {
            delete root.pendingRequests[label];
            deadline.destroy();
        };
        const fail = message => {
            settle();
            if (attempt < root.requestRetries) {
                console.warn(`[WeatherService] ${label} ${message}, retrying`);
                const backoff = deadlineComponent.createObject(root, {
                    interval: root.retryDelay
                });
                backoff.triggered.connect(() => {
                    backoff.destroy();
                    root.request(url, label, onSuccess, attempt + 1);
                });
                backoff.start();
                return;
            }
            console.error(`[WeatherService] ${label} ${message}`);
            root.forecastLoading = false;
            roundRetryTimer.restart();
        };

        // abort() drives readyState to DONE with status 0, so mute the
        // handler first - otherwise the timeout is reported twice and retried
        // twice over.
        deadline.triggered.connect(() => {
            xhr.onreadystatechange = null;
            xhr.abort();
            fail("timed out");
        });
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                fail(`failed with status ${xhr.status}`);
                return;
            }
            settle();
            try {
                onSuccess(JSON.parse(xhr.responseText));
            } catch (e) {
                console.error(`[WeatherService] Failed to parse ${label}:`, e);
                root.forecastLoading = false;
            }
        };

        xhr.open("GET", url);
        xhr.send();
        deadline.start();
    }

    Timer {
        id: roundRetryTimer
        interval: root.roundRetryDelay
        repeat: false
        onTriggered: root.getData(true)
    }

    Component {
        id: deadlineComponent

        Timer {
            repeat: false
        }
    }

    function getData(force = false) {
        const now = Date.now();
        if (!force && (now - lastFetchTimestamp < 60000)) { // 1 minute rate limit
            return;
        }
        lastFetchTimestamp = now;
        root.lastFetchedKey = root.fetchKey;

        if (root.gpsActive && root.location.valid) {
            // If GPS is active and we have a valid position, fetch weather for it directly
            fetchWeather(root.location.lat, root.location.lon, root.location.city || "Current Location");
        } else if (root.city !== "" && !root.gpsActive) {
            // If manual city is set and GPS is off, use geocoding
            fetchCoordinates(root.city);
        } else {
            // Default to ip-api for automatic location
            root.request("http://ip-api.com/json/", "ip-api", loc => {
                if (loc.status !== "success") {
                    console.error("[WeatherService] ip-api failed:", loc.message);
                    return;
                }
                root.location.lat = loc.lat;
                root.location.lon = loc.lon;
                root.location.city = loc.city;
                root.location.valid = true;
                root.fetchWeather(loc.lat, loc.lon, loc.city);
            });
        }
    }

    function fetchCoordinates(cityName) {
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cityName)}&count=1&language=en&format=json`;
        root.request(url, "geocoding", res => {
            if (!res.results || res.results.length === 0) {
                console.error("[WeatherService] Geocoding failed for:", cityName);
                return;
            }
            const loc = res.results[0];
            root.location.lat = loc.latitude;
            root.location.lon = loc.longitude;
            root.location.city = loc.name;
            root.location.valid = true;
            root.fetchWeather(loc.latitude, loc.longitude, loc.name);
        });
    }

    function fetchWeather(lat, lon, cityName) {
        root.forecastLoading = true;
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,uv_index,visibility,is_day&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code&hourly=temperature_2m,weather_code,is_day&timezone=auto`;
        
        root.request(url, "weather", weather => root.refineData(weather, cityName));
    }

    Component.onCompleted: {
        if (root.gpsActive) {
            console.info("[WeatherService] Requesting a position fix.");
            positionSource.update(root.fixTimeout);
            fallbackTimer.start();
        } else {
            root.requestRefetch();
        }
    }

    Timer {
        id: fallbackTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.location.valid) {
                console.info("[WeatherService] GPS timed out or invalid. Falling back to IP-based location.");
                root.stopPositionFix();
                root.gpsActive = false;
                root.getData(true);
            }
        }
    }

    // GeoClue warns when a source that was never started is stopped, and the
    // stop paths below run on config changes and backend failures that can
    // happen before any fix was ever requested.
    function stopPositionFix() {
        if (positionSource.active)
            positionSource.stop();
    }

    // One fix per refresh, not a standing subscription: keeping this running
    // holds a GeoClue client open, so every privacy indicator on the system
    // says the shell is using location around the clock.
    PositionSource {
        id: positionSource

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                fallbackTimer.stop();
                root.stopPositionFix();
                root.location.lat = position.coordinate.latitude;
                root.location.lon = position.coordinate.longitude;
                root.location.valid = true;
                // Forced: the IP-based fetch from the debounce usually landed
                // seconds ago, so the rate limit would drop the fix on the
                // floor and the coordinates would go unused until the next poll.
                root.getData(true);
            } else {
                root.gpsActive = root.location.valid ? true : false;
                console.error("[WeatherService] Failed to get the GPS location.");
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                root.stopPositionFix();
                fallbackTimer.stop();
                root.location.valid = false;
                root.gpsActive = false;
                Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"), Translation.tr("Cannot find a GPS service. Using the fallback method instead."), "-a", "Shell"]);
                console.error("[WeatherService] Could not aquire a valid backend plugin.");
                root.getData(true);
            }
        }
    }

    Timer {
        id: timer
        // This singleton is built lazily, so it only exists once something has
        // actually asked for weather - the bar widget, a desktop or lock screen
        // weather widget, at-a-glance, a live weather effect. Enumerating those
        // consumers here is how the desktop widgets ended up fetching once at
        // startup and never again: the condition only knew about the bar.
        // Existing is the consent.
        running: true
        repeat: true
        interval: root.fetchInterval
        // No triggeredOnStart: the initial fetch is owned by Component.onCompleted
        // (or by the GPS/fallback path), otherwise startup fetches twice.
        onTriggered: {
            // Refresh the fix for the next round; this round uses the last one.
            if (root.gpsActive)
                positionSource.update(root.fixTimeout);
            root.getData();
        }
    }
}
