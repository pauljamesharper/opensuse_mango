import QtQuick
import Quickshell

// The bar's own settings, as a column for the settings panel's Bar tab:
// tag icons, height, element scale and popup size, each persisted to a
// state file Theme.qml watches.
Column {
    id: root
    spacing: 6
    function persistFile(name, v) {
        Quickshell.execDetached(["sh", "-c",
            "printf '%s\\n' " + v + " > '" + Theme.stateDir + "/" + name + "'"])
    }

        SectionLabel { text: "Bar" }

        Grid {
            id: barGrid
            width: parent.width
            columns: 3
            spacing: 4

            Repeater {
                model: [
                    { icon: "󱂬", label: "Tag icons", active: Theme.tagIcons,
                      run: () => {
                          Theme.tagIcons = !Theme.tagIcons
                          root.persistFile("tag-icons", Theme.tagIcons ? 1 : 0)
                      } }
                ]
                TogglePill { width: (barGrid.width - 8) / 3 }
            }
        }
        TweakSlider {
            label: "bar height"
            from: 36; to: 72
            value: Theme.barHeight
            suffix: " px"
            applyFn: v => Theme.barHeight = v
            persistFn: v => root.persistFile("bar-height", v)
        }
        TweakSlider {
            label: "element scale"
            from: 0.7; to: 2.0
            value: Theme.barUserScale
            isInt: false
            suffix: "×"
            applyFn: v => Theme.barUserScale = v
            persistFn: v => root.persistFile("bar-scale", v)
        }
        TweakSlider {
            label: "popup size"
            from: 0.8; to: 2.0
            value: Theme.popupUserScale
            isInt: false
            suffix: "×"
            live: false
            applyFn: v => Theme.popupUserScale = v
            persistFn: v => root.persistFile("popup-scale", v)
        }
}
