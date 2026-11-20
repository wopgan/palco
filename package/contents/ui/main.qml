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
    readonly property int passoPilha: 30      // deslocamento entre cartas na pilha
    readonly property int maxNaPilha: 4       // cartas visíveis na pilha
    readonly property int maxCartas: 40       // cartões fixos (nunca recriados)
    readonly property int larguraRecolhida: 10
    readonly property int invasaoMinima: 60   // px de janela sobre a pilha para recolher
    readonly property int duracao: 200
    readonly property real opacidadeRepouso: 0.55  // pilha sem mouse e sem pedido de atenção
    readonly property int tempoEspiada: 4000  // ms visível ao chegar pedido de atenção
    // Kirigami.Theme não segue o tema dentro do KWin; cor fixa.
    readonly property color corDestaque: "#4a90d9"
    readonly property color corAtencao: "#f0a030"
    // Modo palco (como o Stage Manager): ativar uma janela manda as outras
    // da área atual para a pilha. Liga com:
    //   kwriteconfig6 --file kwinrc --group Script-org.sylvio.palco --key ModoPalco true
    readonly property bool modoPalco: KWin.readConfig("ModoPalco", false)
    // -----------------

    property var minimizadas: []
    property var cartaoSobMouse: null
    // contador "(n)" do título por janela (WhatsApp Web, Gmail...): sites
    // não pedem atenção ao KWin, então o aumento do contador conta como pedido.
    property var contadores: ({})
    property bool sobreposta: false
    // menu em tela cheia do Plasma (painel de aplicativos) aberto: o Palco
    // some (fica com 1 px) para não ficar por cima do menu.
    property bool menuAberto: false
    readonly property bool aberta: hover.hovered || segurarAberta.running
    readonly property bool recolhida: sobreposta && !aberta && !espiada.running
    readonly property int nAtencao: minimizadas.filter(w => w.demandsAttention).length
    readonly property bool pedeAtencao: nAtencao > 0
    property int nAtencaoAntes: 0
    // pedido novo: mostra a pilha mesmo coberta por alguns segundos
    onNAtencaoChanged: {
        if (nAtencao > nAtencaoAntes)
            espiada.restart();
        nAtencaoAntes = nAtencao;
    }
    Timer {
        id: espiada
        interval: palco.tempoEspiada
    }
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
    // Sempre visível (1 px sem minimizadas): esconder/mostrar a janela com o
    // mouse por perto é uma das suspeitas dos crashes do KWin de 19/11.
    visible: true

    // A janela só ocupa o tamanho do conteúdo (o KWin não aceita máscara),
    // para não roubar cliques das janelas de baixo.
    readonly property bool escondido: n === 0 || menuAberto
    readonly property int larguraAlvo: escondido ? 1 : recolhida ? larguraRecolhida : larguraCartao + margem * 2
    readonly property int alturaAlvo: escondido ? 1 : recolhida ? Math.min(area ? area.height : 0, 200) : alturaConteudo + margem * 2
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
        const h = Math.max(1, Math.min(alturaAlvo, area.height));
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

    // Painel de aplicativos (kickerdash) e afins: janela do plasmashell,
    // que não é painel nem fundo, cobrindo quase a tela toda.
    function ehMenuTelaCheia(w) {
        if (!w || w.minimized || w.deleted || w.dock || w.desktopWindow)
            return false;
        const classe = (w.resourceClass || "") + " " + (w.desktopFileName || "");
        if (classe.indexOf("plasmashell") < 0)
            return false;
        if (w.output && Workspace.activeScreen && w.output.name !== Workspace.activeScreen.name)
            return false;
        const g = w.frameGeometry;
        const t = w.output ? w.output.geometry : area;
        return g.width * g.height >= t.width * t.height * 0.9;
    }

    function verificarContador(w) {
        const m = /^\((\d+)\)/.exec(w.caption || "");
        const atual = m ? parseInt(m[1]) : 0;
        const id = String(w.internalId);
        const antes = contadores[id];
        contadores[id] = atual;
        if (w.minimized && antes !== undefined && atual > antes && !w.demandsAttention)
            w.demandsAttention = true;
    }

    function atualizar() {
        const lista = [];
        let cobre = false;
        let menu = false;
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
            if (ehMenuTelaCheia(w)) {
                menu = true;
                continue;
            }
            if (!relevante(w) || !naAreaAtual(w))
                continue;
            verificarContador(w);
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
        // quem pede atenção vai para o topo da pilha
        const urgentes = lista.filter(w => w.demandsAttention);
        if (urgentes.length > 0 && urgentes.length < lista.length)
            lista.splice(0, lista.length, ...urgentes, ...lista.filter(w => !w.demandsAttention));
        if (lista.length !== minimizadas.length || lista.some((w, i) => w !== minimizadas[i]))
        {
            cartaoSobMouse = null;  // o cartão sob o mouse pode ter mudado de janela
            minimizadas = lista;
        }
        sobreposta = cobre;
        menuAberto = menu;
    }

    // Modo palco: a janela ativada fica sozinha em cena (com as outras do
    // mesmo app); o resto vai minimizado para a pilha. Diálogos, janelas
    // "sempre acima" (ex.: picture-in-picture) e transientes ficam de fora.
    function trocarCena(ativa) {
        if (!modoPalco || !relevante(ativa) || ativa.transient || ativa.minimized || !naAreaAtual(ativa))
            return;
        const ordem = Workspace.stackingOrder;
        for (let i = 0; i < ordem.length; i++) {
            const w = ordem[i];
            if (w === ativa || !relevante(w) || w.minimized || !w.minimizable || w.transient || w.keepAbove)
                continue;
            if (w.resourceClass === ativa.resourceClass || !naAreaAtual(w))
                continue;
            w.minimized = true;
        }
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
        function onWindowRemoved(w) {
            if (w) delete palco.contadores[String(w.internalId)];
            palco.atualizar();
        }
        function onCurrentDesktopChanged() { palco.atualizar(); }
        function onWindowActivated(w) {
            palco.trocarCena(w);
            palco.atualizar();
        }
    }

    Item {
        anchors.fill: parent
        HoverHandler { id: hover }

        // alça quando recolhida: só aparece com pedido de atenção;
        // sem ele a faixa fica invisível mas ainda abre o palco no hover
        Rectangle {
            id: alca
            visible: palco.recolhida && palco.pedeAtencao
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: parent.height * 0.8
            radius: 3
            color: palco.corAtencao
            opacity: 0.85
            SequentialAnimation on opacity {
                running: palco.pedeAtencao && palco.recolhida
                loops: Animation.Infinite
                onRunningChanged: if (!running) alca.opacity = 0.85
                NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
            }
        }

        Item {
            id: palcoCartas
            visible: !palco.recolhida && !palco.menuAberto
            opacity: palco.aberta || palco.pedeAtencao || espiada.running ? 1 : palco.opacidadeRepouso
            Behavior on opacity { NumberAnimation { duration: palco.duracao } }
            x: palco.margem
            y: palco.margem
            width: palco.larguraCartao
            height: palco.alturaConteudo

            Repeater {
                id: cartoes
                // Modelo numérico fixo: os cartões nunca são apagados nem
                // recriados, só trocam de janela ou se escondem.
                model: palco.maxCartas

                delegate: Item {
                    id: cartao
                    required property int index
                    readonly property var janela: index < palco.n ? palco.minimizadas[index] : null
                    visible: janela !== null
                    readonly property real esc: palco.escalaLeque
                    readonly property int profundidade: Math.min(index, palco.maxNaPilha - 1)
                    readonly property bool atencao: janela !== null && janela.demandsAttention
                    readonly property bool sobMouse: palco.cartaoSobMouse === cartao

                    width: palco.larguraCartao
                    height: palco.alturaMiniatura + 22
                    transformOrigin: Item.Top
                    z: palco.n - index

                    // pilha: cartas deslocadas e menores atrás; leque: coluna
                    y: palco.aberta
                        ? index * (palco.alturaMiniatura + 22 + palco.espacoLeque) * esc
                        : profundidade * palco.passoPilha
                    scale: palco.aberta
                        ? esc * (cartao.sobMouse ? 1.05 : 1.0)
                        : 1.0 - profundidade * 0.05
                    opacity: palco.aberta || index < palco.maxNaPilha ? 1 : 0

                    Behavior on y { NumberAnimation { duration: palco.duracao; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: palco.duracao; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: palco.duracao } }

                    // tremida periódica enquanto a janela pede atenção; desloca
                    // o x de um Item interno (transform foi suspeita de crash)
                    SequentialAnimation {
                        running: cartao.atencao && !palco.recolhida
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) tremor.x = 0
                        NumberAnimation { target: tremor; property: "x"; to: -6; duration: 50 }
                        NumberAnimation { target: tremor; property: "x"; to: 6; duration: 70 }
                        NumberAnimation { target: tremor; property: "x"; to: -4; duration: 70 }
                        NumberAnimation { target: tremor; property: "x"; to: 4; duration: 70 }
                        NumberAnimation { target: tremor; property: "x"; to: 0; duration: 50 }
                        PauseAnimation { duration: 1700 }
                    }

                    Item {
                    id: tremor
                    width: parent.width
                    height: parent.height

                    Rectangle {
                        id: moldura
                        width: parent.width
                        height: palco.alturaMiniatura
                        radius: 8
                        color: Qt.rgba(0.08, 0.09, 0.11, 0.55)
                        border.width: cartao.atencao || cartao.sobMouse ? 2 : 1
                        border.color: cartao.atencao
                            ? palco.corAtencao
                            : cartao.sobMouse
                                ? palco.corDestaque
                                : Qt.rgba(1, 1, 1, 0.12)

                        WindowThumbnail {
                            anchors.fill: parent
                            anchors.margins: 5
                            client: cartao.janela
                            visible: cartao.janela !== null
                        }
                    }

                    Kirigami.Icon {
                        source: cartao.janela ? cartao.janela.icon : ""
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
                        text: cartao.janela ? cartao.janela.caption : ""
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        font.pointSize: 8
                        color: "white"
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.6)
                        opacity: palco.aberta ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: palco.duracao } }
                    }
                    }
                }
            }

            // Uma só área de mouse, fixa, para o palco inteiro (cartões sem
            // hover próprio), por causa dos crashes do KWin de 19/11/2026.
            MouseArea {
                id: toqueGeral
                anchors.fill: parent
                z: 10000
                hoverEnabled: true
                enabled: palco.aberta
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                // cartão de cima primeiro (índice menor = z maior)
                function cartaoEm(x, y) {
                    for (let i = 0; i < palco.n; i++) {
                        const c = cartoes.itemAt(i);
                        if (!c || !c.visible || !c.janela)
                            continue;
                        const p = toqueGeral.mapToItem(c, x, y);
                        if (c.contains(p))
                            return c;
                    }
                    return null;
                }
                onPositionChanged: (ev) => palco.cartaoSobMouse = cartaoEm(ev.x, ev.y)
                onExited: palco.cartaoSobMouse = null
                onEnabledChanged: if (!enabled) palco.cartaoSobMouse = null
                onClicked: (ev) => {
                    const c = cartaoEm(ev.x, ev.y);
                    palco.cartaoSobMouse = null;
                    if (!c || !c.janela)
                        return;
                    if (ev.button === Qt.MiddleButton)
                        c.janela.closeWindow();
                    else
                        palco.restaurar(c.janela);
                }
            }
        }
    }

    Component.onCompleted: { atualizar(); posicionar(); }
}
