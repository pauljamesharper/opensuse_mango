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

        SectionLabel { text: "Modules" }
        Txt {
            text: "the right side of the bar, left to right · switch one off to hide it · the command menu stays last"
            color: Qt.alpha(Theme.fg, 0.5)
            bottomPadding: 4
        }
        function move(i, d) {
            const l = Theme.modules.slice()
            const j = i + d
            if (j < 0 || j >= l.length) return
            const t = l[i]; l[i] = l[j]; l[j] = t
            Theme.setModules(l)
        }
        function flip(i) {
            const l = Theme.modules.slice()
            l[i] = { key: l[i].key, on: !l[i].on }
            Theme.setModules(l)
        }
        Column {
            width: parent.width
            spacing: 2
            Repeater {
                model: Theme.modules
                Rectangle {
                    id: modRow
                    required property var modelData
                    required property int index
                    readonly property var def: Theme.moduleDefs.find(d => d.key === modelData.key)
                    width: parent.width
                    height: 30
                    radius: 6
                    color: rowMa.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                    MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.flip(modRow.index) }
                    Toggle {
                        id: modToggle
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        on: modRow.modelData.on
                        onToggled: root.flip(modRow.index)
                    }
                    Txt {
                        anchors.left: modToggle.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modRow.def ? modRow.def.label : modRow.modelData.key
                        color: modRow.modelData.on ? Theme.fg : Qt.alpha(Theme.fg, 0.45)
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: [["󰅃", -1], ["󰅀", 1]]
                            Rectangle {
                                required property var modelData
                                readonly property bool can: modelData[1] < 0 ? modRow.index > 0 : modRow.index < Theme.modules.length - 1
                                width: 26; height: 24; radius: 6
                                color: arrowMa.containsMouse && can ? Qt.alpha(Theme.fg, 0.14) : "transparent"
                                opacity: can ? 1 : 0.25
                                Txt { anchors.centerIn: parent; text: parent.modelData[0]; color: Theme.accent; font.pixelSize: 14 }
                                MouseArea {
                                    id: arrowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: parent.can
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.move(modRow.index, parent.modelData[1])
                                }
                            }
                        }
                    }
                }
            }
        }
        Txt {
            text: "reset to the default order"
            color: Theme.accent
            font.pixelSize: 11
            topPadding: 4
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Theme.setModules(Theme.moduleDefs.map(d => ({ key: d.key, on: true }))) }
        }
}
