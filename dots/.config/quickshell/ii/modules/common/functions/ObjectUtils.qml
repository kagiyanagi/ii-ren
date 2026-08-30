pragma Singleton
import Quickshell

Singleton {
    id: root

    function toPlainObject(qtObj) {
        if (qtObj === null || typeof qtObj !== "object") return qtObj;

        // Handle true arrays
        if (Array.isArray(qtObj)) {
            return qtObj.map(item => toPlainObject(item));
        }

        // Handle array-like Qt objects (e.g., have length and numeric keys)
        if (
            typeof qtObj.length === "number" &&
            qtObj.length > 0 &&
            Object.keys(qtObj).every(
                key => !isNaN(key) || key === "length"
            )
        ) {
            let arr = [];
            for (let i = 0; i < qtObj.length; i++) {
                arr.push(toPlainObject(qtObj[i]));
            }
            return arr;
        }

        const result = ({});
        for (let key in qtObj) {
            if (
                typeof qtObj[key] !== "function" &&
                !key.startsWith("objectName") &&
                !key.startsWith("children") &&
                !key.startsWith("object") &&
                !key.startsWith("parent") &&
                !key.startsWith("metaObject") &&
                !key.startsWith("destroyed") &&
                !key.startsWith("reloadableId")
            ) {
                result[key] = toPlainObject(qtObj[key]);
            }
        }
        // console.log(JSON.stringify(result))
        return result;
    }
}
