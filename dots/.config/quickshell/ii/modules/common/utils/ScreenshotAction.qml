pragma ComponentBehavior: Bound
pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound,
        AskAI
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "", previewPath = "") {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        // grim writes these screenshots as PPM - it is ~150ms faster than PNG -
        // and magick keeps whatever format it was handed unless told otherwise.
        // So every consumer has to name the format it wants: `png:-` for the
        // pipes, a .png path for the files. Cropping onto the source path is
        // the one case that legitimately stays PPM, because only tesseract
        // reads it.
        const cropBase = `magick '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' `
            + `-crop ${rw}x${rh}+${rx}+${ry} +repage`
        const cropToStdout = `${cropBase} png:-`
        const cropInPlace = `${cropBase} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const cleanup = `rm '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        const uploadAndGetUrl = (filePath) => {
            return `curl -sf -F 'files[]=@${StringUtils.shellSingleQuoteEscape(filePath)};type=image/png' `
                + `${root.fileUploadApiEndpoint} | jq -r '.files[0].url // empty'`
        }
        const annotationCommand = `${Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"} -f -`;
        switch (action) {
            case ScreenshotAction.Action.Copy:
                if (saveDir === "") {
                    if (previewPath !== "") {
                        // Keep the crop on disk so the preview popup has
                        // something to show, save or edit afterwards. The popup
                        // owns that file from here on - it deletes it if the
                        // user discards or ignores it.
                        const preview = `'${StringUtils.shellSingleQuoteEscape(previewPath)}'`
                        return ["bash", "-c", `${cropBase} ${preview} && wl-copy < ${preview} && ${cleanup}`]
                    }
                    // not saving the screenshot, just copy to clipboard
                    return ["bash", "-c", `${cropToStdout} | wl-copy && ${cleanup}`]
                    break;
                }
                return [
                    "bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(saveDir)}' && \
                    saveFileName="screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                    savePath="${saveDir}/$saveFileName" && \
                    ${cropToStdout} | tee >(wl-copy) > "$savePath" && \
                    ${cleanup}`
                ]

                break;
            case ScreenshotAction.Action.Edit:
                return ["bash", "-c", `${cropToStdout} | ${annotationCommand} && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Search: {
                /*
                 * The browser opens Lens. We never do.
                 *
                 * Uploading the crop to Google ourselves and opening the results
                 * URL it hands back does not work, however correct that URL
                 * looks: the visual-search session belongs to whoever uploaded,
                 * so one minted by curl is not a session the browser may use. It
                 * loads as "Expired visual search" and the page sits on
                 * "Thinking a little longer" forever. Giving xdg-open the
                 * uploadbyurl link instead lets the browser mint its own session
                 * against its own cookies, which is the only arrangement that
                 * returns results - and is what upstream has always done.
                 *
                 * The crop also has to be a real PNG. grim writes PPM here for
                 * speed and magick's crop-in-place keeps that format, so the old
                 * code uploaded raw Netpbm: Google accepted it, could not decode
                 * it, and issued a stub session whose page never stops thinking.
                 * Cropping to a .png path is what converts it - the extension
                 * picks the encoder. Measured, same image, same second:
                 *
                 *     PPM  -> session type 1, no backend block, timestamp 0
                 *     PNG  -> session type 2, backend block, real timestamp
                 *
                 * The upload is public for as long as the host keeps it, which
                 * is the price of Lens being able to fetch it at all.
                 */
                const searchPath = `${screenshotPath}.png`
                const searchFile = `'${StringUtils.shellSingleQuoteEscape(searchPath)}'`
                return ["bash", "-c",
                    `${cropBase} ${searchFile} && `
                    + `imageUrl=$(${uploadAndGetUrl(searchPath)}) && `
                    + `[ -n "$imageUrl" ] && `
                    + `xdg-open "${root.imageSearchEngineBaseUrl}$imageUrl"; `
                    + `rm -f ${searchFile} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`]
            }
            case ScreenshotAction.Action.AskAI:
                return ["bash", "-c", `${cropToStdout} | wl-copy && ${cleanup}`]
                break;
            case ScreenshotAction.Action.CharRecognition:
                return ["bash", "-c", `${cropInPlace} && tesseract '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Record:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'`]
                break;
            case ScreenshotAction.Action.RecordWithSound:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound`]
                break;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
