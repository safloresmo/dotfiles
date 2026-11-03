// La animación Navi a pantalla completa, encima de todo y sin tomar el foco.
// La lanza navi-intro con NAVI_CUADROS apuntando a los cuadros del tema de Plymouth.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: raiz

    readonly property string cuadros: Quickshell.env("NAVI_CUADROS") || "/usr/share/plymouth/themes/navi"
    // NAVI_PANTALLA=<salida> la limita a una pantalla (para probarla)
    readonly property string solo: Quickshell.env("NAVI_PANTALLA") || ""
    readonly property int total: 90
    property int cuadro: 0
    property real velo: 0

    function ruta(n) {
        return "file://" + cuadros + "/f" + String(n + 1).padStart(3, "0") + ".png"
    }

    // negro que entra rápido, la animación una vuelta y salida suave al escritorio
    SequentialAnimation on velo {
        running: true
        NumberAnimation { to: 1; duration: 220; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 2700 }
        NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutCubic }
        ScriptAction { script: Qt.quit() }
    }

    // 30 cuadros por segundo, como el vídeo; se queda en el último
    Timer {
        interval: 33
        repeat: true
        running: raiz.cuadro < raiz.total - 1
        onTriggered: raiz.cuadro++
    }

    Variants {
        model: Quickshell.screens.filter(s => !raiz.solo || s.name === raiz.solo)

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // no recibe clics ni teclas: el escritorio sigue usable debajo
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "navi-intro"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: raiz.velo
            }

            Image {
                // mismo tamaño que en el arranque: escalado a una pantalla de 1920x1080
                readonly property real ajuste: Math.min(parent.width / 1920, parent.height / 1080)
                anchors.centerIn: parent
                width: 1030 * ajuste
                height: 240 * ajuste
                source: raiz.ruta(raiz.cuadro)
                asynchronous: false
                smooth: true
                opacity: raiz.velo
                scale: 0.96 + 0.04 * raiz.velo
            }
        }
    }
}
