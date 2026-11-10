import QtQuick

// openSUSE chameleon — the command center, no extra buttons needed:
//   left: app launcher (LauncherPopup; the clipboard popup lives here
//   too) · right: the settings panel's
//   Wallpaper tab · middle: random wallpaper
// Both wallpaper paths re-theme the desktop from the image's palette.
BarModule {
    id: root

    icon: ""  // openSUSE chameleon (Font Logos, in Roboto Mono Nerd Font too)
    iconColor: Theme.accent
    iconPixelSize: Math.round(Theme.iconSize * 1.35)
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            BarIpc.call("settings", "open", "wallpaper")
        else if (mouse.button === Qt.MiddleButton)
            BarIpc.call("wallpapers", "random", "")
        else
            launcher.visible = !launcher.visible
    }

    LauncherPopup {
        id: launcher
        anchorItem: root
    }

    ClipboardPopup {
        anchorItem: root
    }
}
