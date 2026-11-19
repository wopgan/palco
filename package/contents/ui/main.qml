import QtQuick
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kwin

// Palco: faixa na esquerda com miniaturas das janelas minimizadas
// da área de trabalho atual. Clique restaura; botão do meio fecha.
PlasmaCore.Window {
    id: palco

    // ---- ajustes ----
    readonly property int larguraMiniatura: 170
    readonly property int margem: 14
    readonly property int larguraRecolhida: 6
    // -----------------

    property var minimizadas: []
    property bool sobreposta: false
    property bool mouseDentro: hover.hovered
    readonly property bool recolhida: sobreposta && !mouseDentro
    readonly property var area: Workspace.clientArea(KWin.PlacementArea, Workspace.activeScreen, Workspace.currentDesktop)

    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    visible: minimizadas.length > 0

    readonly property int larguraAlvo: recolhida ? larguraRecolhida : larguraMiniatura + margem * 2
    onLarguraAlvoChanged: posicionar()
    onAreaChanged: posicionar()

    // x/y declarativos com valor 0 não marcam a posição como explícita
    // e a janela nasce centralizada; setGeometry resolve.
    function posicionar() {
        if (!area)
            return;
        setGeometry(area.x, area.y, larguraAlvo, area.height);
    }

    function naAreaAtual(w) {
        const d = Workspace.currentDesktop;
        if (!w.onAllDesktops && !w.desktops.some(x => x.id === d.id))
            return false;
        const a = Workspace.currentActivity;
        if (w.activities.length > 0 && w.activities.indexOf(a) < 0)
            return false;
        return !w.output || !Workspace.activeScreen || w.output.name === Workspace.activeScreen.name;
    }

    function relevante(w) {
        return w && w.normalWindow && !w.skipTaskbar && !w.deleted;
    }

    function atualizar() {
        const lista = [];
        let cobre = false;
        const faixa = Qt.rect(area.x, area.y, larguraMiniatura + margem * 2, area.height);
        const ordem = Workspace.stackingOrder;
        for (let i = ordem.length - 1; i >= 0; i--) {
            const w = ordem[i];
            if (!relevante(w) || !naAreaAtual(w))
                continue;
            if (w.minimized) {
                lista.push(w);
            } else {
                const g = w.frameGeometry;
                if (g.x < faixa.x + faixa.width && g.x + g.width > faixa.x
                        && g.y < faixa.y + faixa.height && g.y + g.height > faixa.y)
                    cobre = true;
            }
        }
        if (lista.length !== minimizadas.length || lista.some((w, i) => w !== minimizadas[i]))
            minimizadas = lista;
        sobreposta = cobre;
    }

    function restaurar(w) {
        w.minimized = false;
        Workspace.activeWindow = w;
    }

    // Minimizar/mover não muda o stackingOrder; um timer leve cobre tudo.
    Timer {
        interval: 350
        running: true
        repeat: true
        onTriggered: palco.atualizar()
    }
    Connections {
        target: Workspace
        function onWindowAdded() { palco.atualizar(); }
        function onWindowRemoved() { palco.atualizar(); }
        function onCurrentDesktopChanged() { palco.atualizar(); }
        function onWindowActivated() { palco.atualizar(); }
    }

    mainItem: Item {
        HoverHandler { id: hover }

        // alça quando recolhida
        Rectangle {
            visible: palco.recolhida
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: Math.min(parent.height * 0.3, 160)
            radius: 2
            color: Kirigami.Theme.highlightColor
            opacity: 0.7
        }

        Rectangle {
            anchors.fill: parent
            visible: !palco.recolhida && palco.sobreposta
            color: Kirigami.Theme.backgroundColor
            opacity: 0.75
        }

        Flickable {
            id: rolagem
            visible: !palco.recolhida
            x: palco.margem
            width: palco.larguraMiniatura
            height: parent.height
            contentHeight: coluna.height
            clip: true
            interactive: contentHeight > height

            Column {
                id: coluna
                width: rolagem.width
                spacing: 18
                // centraliza verticalmente quando cabe
                y: Math.max(0, (rolagem.height - height) / 2)

                Repeater {
                    model: palco.minimizadas

                    delegate: Item {
                        id: cartao
                        required property var modelData
                        readonly property var janela: modelData
                        readonly property real proporcao: janela.frameGeometry.width > 0
                            ? janela.frameGeometry.height / janela.frameGeometry.width : 0.6
                        width: coluna.width
                        height: miniatura.height + titulo.height + 6

                        scale: toque.containsMouse ? 1.06 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120 } }

                        WindowThumbnail {
                            id: miniatura
                            client: cartao.janela
                            width: parent.width
                            height: Math.min(width * cartao.proporcao, width * 1.2)
                        }

                        Kirigami.Icon {
                            source: cartao.janela.icon
                            width: 28
                            height: 28
                            anchors.right: miniatura.right
                            anchors.bottom: miniatura.bottom
                            anchors.margins: -6
                        }

                        Text {
                            id: titulo
                            anchors.top: miniatura.bottom
                            anchors.topMargin: 6
                            width: parent.width
                            text: cartao.janela.caption
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            font.pointSize: 8
                            color: Kirigami.Theme.textColor
                            style: Text.Outline
                            styleColor: Qt.rgba(0, 0, 0, 0.35)
                        }

                        MouseArea {
                            id: toque
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: (ev) => {
                                if (ev.button === Qt.MiddleButton)
                                    cartao.janela.closeWindow();
                                else
                                    palco.restaurar(cartao.janela);
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: { atualizar(); posicionar(); }
}
