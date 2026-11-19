import QtQuick
import QtQuick.Window as QW
import org.kde.kirigami as Kirigami
import org.kde.kwin

// QW.Window: "Window" sozinho colide com o tipo Window do org.kde.kwin.
// Palco: miniaturas das janelas minimizadas da área de trabalho atual,
// empilhadas na borda esquerda. Mouse em cima abre o leque; clique
// restaura, botão do meio fecha. Se uma janela cobre a área, vira alça.
QW.Window {
    id: palco

    // ---- ajustes ----
    readonly property int larguraCartao: 170
    readonly property int alturaMiniatura: 110
    readonly property int margem: 18
    readonly property int espacoLeque: 14
    readonly property int passoPilha: 16      // deslocamento entre cartas na pilha
    readonly property int maxNaPilha: 4       // cartas visíveis na pilha
    readonly property int larguraRecolhida: 10
    readonly property int invasaoMinima: 60   // px de janela sobre a pilha para recolher
    readonly property int duracao: 200
    // Kirigami.Theme não segue o tema dentro do KWin; cor fixa.
    readonly property color corDestaque: "#4a90d9"
    // -----------------

    property var minimizadas: []
    property bool sobreposta: false
    readonly property bool aberta: hover.hovered || segurarAberta.running
    readonly property bool recolhida: sobreposta && !aberta
    readonly property var area: Workspace.clientArea(KWin.PlacementArea, Workspace.activeScreen, Workspace.currentDesktop)

    readonly property int alturaCartao: alturaMiniatura + (aberta ? 22 : 0)
    readonly property int n: minimizadas.length
    readonly property int alturaPilha: alturaMiniatura + Math.max(0, Math.min(n, maxNaPilha) - 1) * passoPilha
    readonly property int alturaLequeBruta: n * (alturaMiniatura + 22) + Math.max(0, n - 1) * espacoLeque
    // se não couber na tela, as cartas do leque encolhem
    readonly property real escalaLeque: area ? Math.min(1, (area.height - margem * 2) / Math.max(1, alturaLequeBruta)) : 1
    readonly property int alturaConteudo: aberta ? Math.ceil(alturaLequeBruta * escalaLeque) : alturaPilha

    // No Wayland o bypass não basta: o KWin gerencia a janela. Por isso o
    // título fixo, para achá-la e marcá-la como "sempre acima" e fora das listas.
    readonly property string tituloProprio: "org.sylvio.palco"
    title: tituloProprio
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: n > 0

    // A janela só ocupa o tamanho do conteúdo (o KWin não aceita máscara),
    // para não roubar cliques das janelas de baixo.
    readonly property int larguraAlvo: recolhida ? larguraRecolhida : larguraCartao + margem * 2
    readonly property int alturaAlvo: recolhida ? Math.min(area ? area.height : 0, 200) : alturaConteudo + margem * 2
    onLarguraAlvoChanged: posicionar()
    onAlturaAlvoChanged: atrasoEncolher.restart()
    onAreaChanged: posicionar()
    onAbertaChanged: if (aberta) posicionar()

    // Ao fechar o leque, espera a animação terminar antes de encolher a janela.
    Timer {
        id: atrasoEncolher
        interval: palco.aberta ? 0 : palco.duracao
        onTriggered: palco.posicionar()
    }
    // Pequena tolerância ao sair com o mouse, para o leque não piscar.
    Timer {
        id: segurarAberta
        interval: 250
    }
    Connections {
        target: hover
        function onHoveredChanged() {
            if (!hover.hovered)
                segurarAberta.restart();
        }
    }

    // x/y declarativos com valor 0 não marcam a posição como explícita
    // e a janela nasce centralizada; setGeometry resolve.
    function posicionar() {
        if (!area)
            return;
        const h = Math.min(alturaAlvo, area.height);
        setGeometry(area.x, area.y + Math.round((area.height - h) / 2), larguraAlvo, h);
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
        return w && w.normalWindow && !w.skipTaskbar && !w.deleted && w.caption !== tituloProprio;
    }

    function ajustarPropria(w) {
        if (!w.keepAbove) w.keepAbove = true;
        if (!w.skipTaskbar) w.skipTaskbar = true;
        if (!w.skipSwitcher) w.skipSwitcher = true;
        if (!w.skipPager) w.skipPager = true;
        if (!w.onAllDesktops) w.onAllDesktops = true;
    }

    function atualizar() {
        const lista = [];
        let cobre = false;
        // área de referência: a pilha no centro da borda
        const faixaH = alturaPilha + margem * 2;
        const faixa = Qt.rect(area.x, area.y + (area.height - faixaH) / 2, larguraCartao + margem * 2, faixaH);
        const ordem = Workspace.stackingOrder;
        for (let i = ordem.length - 1; i >= 0; i--) {
            const w = ordem[i];
            if (w && w.caption === tituloProprio) {
                ajustarPropria(w);
                continue;
            }
            if (!relevante(w) || !naAreaAtual(w))
                continue;
            if (w.minimized) {
                lista.push(w);
            } else {
                const g = w.frameGeometry;
                const dx = Math.min(g.x + g.width, faixa.x + faixa.width) - Math.max(g.x, faixa.x);
                const dy = Math.min(g.y + g.height, faixa.y + faixa.height) - Math.max(g.y, faixa.y);
                if (dx >= invasaoMinima && dy >= invasaoMinima)
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

    Item {
        anchors.fill: parent
        HoverHandler { id: hover }

        // alça quando recolhida
        Rectangle {
            visible: palco.recolhida
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: parent.height * 0.8
            radius: 3
            color: palco.corDestaque
            opacity: 0.85
        }

        Item {
            id: palcoCartas
            visible: !palco.recolhida
            x: palco.margem
            y: palco.margem
            width: palco.larguraCartao
            height: palco.alturaConteudo

            Repeater {
                model: palco.minimizadas

                delegate: Item {
                    id: cartao
                    required property var modelData
                    required property int index
                    readonly property var janela: modelData
                    readonly property real esc: palco.escalaLeque
                    readonly property int profundidade: Math.min(index, palco.maxNaPilha - 1)

                    width: palco.larguraCartao
                    height: palco.alturaMiniatura + 22
                    transformOrigin: Item.Top
                    z: palco.n - index

                    // pilha: cartas deslocadas e menores atrás; leque: coluna
                    y: palco.aberta
                        ? index * (palco.alturaMiniatura + 22 + palco.espacoLeque) * esc
                        : profundidade * palco.passoPilha
                    scale: palco.aberta
                        ? esc * (toque.containsMouse ? 1.05 : 1.0)
                        : 1.0 - profundidade * 0.05
                    opacity: palco.aberta || index < palco.maxNaPilha ? 1 : 0

                    Behavior on y { NumberAnimation { duration: palco.duracao; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: palco.duracao; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: palco.duracao } }

                    Rectangle {
                        id: moldura
                        width: parent.width
                        height: palco.alturaMiniatura
                        radius: 8
                        color: Qt.rgba(0.08, 0.09, 0.11, 0.55)
                        border.width: toque.containsMouse ? 2 : 1
                        border.color: toque.containsMouse
                            ? palco.corDestaque
                            : Qt.rgba(1, 1, 1, 0.12)

                        WindowThumbnail {
                            anchors.fill: parent
                            anchors.margins: 5
                            client: cartao.janela
                        }
                    }

                    Kirigami.Icon {
                        source: cartao.janela.icon
                        width: 26
                        height: 26
                        anchors.right: moldura.right
                        anchors.bottom: moldura.bottom
                        anchors.margins: -5
                    }

                    Text {
                        anchors.top: moldura.bottom
                        anchors.topMargin: 5
                        width: parent.width
                        text: cartao.janela.caption
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        font.pointSize: 8
                        color: "white"
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.6)
                        opacity: palco.aberta ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: palco.duracao } }
                    }

                    MouseArea {
                        id: toque
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: palco.aberta
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

    Component.onCompleted: { atualizar(); posicionar(); }
}
