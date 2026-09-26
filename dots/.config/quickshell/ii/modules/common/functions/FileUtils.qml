pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Trims the File protocol off the input string
     * @param {string} str
     * @returns {string}
     */
    function trimFileProtocol(str) {
        let s = str;
        if (typeof s !== "string") s = str.toString(); // Convert to string if it's an url or whatever
        return s.startsWith("file://") ? s.slice(7) : s;
    }

    /**
     * Extracts the file name from a file path
     * @param {string} str
     * @returns {string}
     */
    function fileNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        return trimmed.split(/[\\/]/).pop();
    }

    /**
     * Extracts the folder name from a directory path
     * @param {string} str
     * @returns {string}
     */
    function folderNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        // Remove trailing slash if present
        const noTrailing = trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
        if (!noTrailing) return "";
        return noTrailing.split(/[\\/]/).pop();
    }

    /**
     * Removes the file extension from a file path or name
     * @param {string} str
     * @returns {string}
     */
    function trimFileExt(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const lastDot = trimmed.lastIndexOf(".");
        if (lastDot > -1 && lastDot > trimmed.lastIndexOf("/")) {
            return trimmed.slice(0, lastDot);
        }
        return trimmed;
    }

    /**
     * A Material Symbol for a file, by its extension; `draft` for anything unknown.
     * Every name here exists in the older of the two Material Symbols builds, the
     * one Qt resolves the family to.
     * @param {string} str
     * @returns {string}
     */
    function iconForFile(str) {
        const name = fileNameForPath((str ?? "").toString()).toLowerCase();
        const dot = name.lastIndexOf(".");
        const ext = dot > 0 ? name.slice(dot + 1) : "";
        const groups = [
            ["image", "png jpg jpeg webp gif bmp svg ico tif tiff heic heif avif jxl"],
            ["movie", "mp4 mkv webm avi mov m4v flv wmv mpg mpeg 3gp"],
            ["music_note", "mp3 flac ogg opus wav aac m4a wma alac aiff mid midi"],
            ["picture_as_pdf", "pdf"],
            ["folder_zip", "zip tar gz tgz bz2 xz zst rar 7z lz4 cab"],
            ["html", "html htm xhtml"],
            ["css", "css scss sass less"],
            ["javascript", "js mjs cjs jsx ts tsx"],
            ["php", "php"],
            ["terminal", "sh bash zsh fish ps1 bat cmd"],
            ["code", "py rs go c cc cpp cxx h hpp java kt kts swift rb lua qml cs dart scala zig nim hs ml ex exs clj vue svelte r jl pl asm s"],
            ["data_object", "json jsonc yaml yml toml xml ini conf cfg env lock plist"],
            ["table", "csv tsv xls xlsx ods numbers"],
            ["slideshow", "ppt pptx odp key"],
            ["article", "doc docx odt rtf pages tex"],
            ["markdown", "md markdown mdx rst org"],
            ["description", "txt log text nfo"],
            ["menu_book", "epub mobi azw3 djvu cbz cbr"],
            ["font_download", "ttf otf woff woff2"],
            ["android", "apk aab"],
            ["deployed_code", "exe msi appimage deb rpm flatpak snap pkg dmg bin run"],
            ["album", "iso img"],
            ["database", "db sqlite sqlite3 sql mdb"],
            ["key", "pem key crt cer gpg asc pub p12 pfx"],
            ["view_in_ar", "stl obj blend fbx gltf glb 3mf step"],
            ["draw", "psd xcf kra ai sketch fig"],
            ["calendar_month", "ics"],
            ["contact_page", "vcf"],
            ["mail", "eml msg mbox"]
        ];
        const hit = groups.find(group => group[1].split(" ").includes(ext));
        return hit ? hit[0] : "draft";
    }

    /**
     * Returns the parent directory of a given file path
     * @param {string} str
     * @returns {string}
     */
    function parentDirectory(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const parts = trimmed.split(/[\\/]/);
        if (parts.length <= 1) return "";
        parts.pop();
        return parts.join("/");
    }
}
