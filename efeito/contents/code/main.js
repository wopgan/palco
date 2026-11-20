/*
    Palco: animação de minimizar/restaurar.
    Baseado no efeito Squash do KWin (Vlad Zahorodnii, GPL-2.0-or-later).

    Sem gerenciador de tarefas a janela não tem iconGeometry, então o alvo
    é a coluna do Palco: o lugar da janela dele (achada pelo título) ou,
    se ele estiver escondido, a borda esquerda no meio da tela. Ao
    restaurar com o cursor sobre o Palco (clique num cartão), a janela
    sai do cursor. Janelas que se mexem juntas (uma cena) terminam em
    cascata, com durações um pouco diferentes (sem delay: delay mostra
    a janela inteira antes de a animação começar).

    Só usa a API de efeitos em JS (animate/redirect/cancel), sem QML.
*/

"use strict";

const tituloPalco = "org.sylvio.palco";
const larguraCartao = 170;
const alturaCartao = 110;
const margem = 18;
const passoCascata = 40;   // ms a mais por janela de um mesmo lote
const janelaLote = 60;     // ms: eventos mais próximos que isso são um lote

var palcoAnim = {
    duracao: animationTime(260),
    ultimoEvento: 0,
    noLote: 0,

    loadConfig: function () {
        palcoAnim.duracao = animationTime(260);
    },

    duracaoEmCascata: function () {
        const agora = Date.now();
        palcoAnim.noLote = agora - palcoAnim.ultimoEvento < janelaLote ? palcoAnim.noLote + 1 : 0;
        palcoAnim.ultimoEvento = agora;
        return palcoAnim.duracao + Math.min(palcoAnim.noLote, 5) * passoCascata;
    },

    janelaPalco: function () {
        const ordem = effects.stackingOrder;
        for (let i = ordem.length - 1; i >= 0; i--) {
            const w = ordem[i];
            if (w && w.caption === tituloPalco)
                return w;
        }
        return null;
    },

    // retângulo do cartão de destino/origem para a janela
    alvo: function (window, restaurando) {
        const g = window.geometry;
        const escala = Math.min(larguraCartao / Math.max(1, g.width), alturaCartao / Math.max(1, g.height));
        const w = Math.max(1, g.width * escala);
        const h = Math.max(1, g.height * escala);
        const tela = window.screen ? window.screen.geometry : g;

        const palco = palcoAnim.janelaPalco();
        const p = palco ? palco.geometry : null;
        const palcoVisivel = p && p.width > 1 && p.height > 1;
        const c = effects.cursorPos;

        // restaurar pelo clique num cartão: sai de onde está o cursor
        if (restaurando && palcoVisivel &&
                c.x >= p.x && c.x < p.x + p.width && c.y >= p.y && c.y < p.y + p.height)
            return { x: c.x - w / 2, y: c.y - h / 2, width: w, height: h };

        // coluna do Palco: topo (o mais recente fica em cima)
        const x = tela.x + margem + (larguraCartao - w) / 2;
        let y;
        if (palcoVisivel && p.y >= tela.y && p.y < tela.y + tela.height)
            y = Math.max(tela.y + margem, p.y + margem - (restaurando ? 0 : (alturaCartao + 12) / 2));
        else
            y = tela.y + (tela.height - h) / 2;
        return { x: x, y: y, width: w, height: h };
    },

    deveAnimar: function (window) {
        if (effects.hasActiveFullScreenEffect)
            return false;
        if (!window || window.caption === tituloPalco)
            return false;
        return window.normalWindow || window.dialog;
    },

    animar: function (window, restaurando) {
        const icone = palcoAnim.alvo(window, restaurando);
        const r = window.geometry;
        const desloc = {
            value1: icone.x - r.x - (r.width - icone.width) / 2,
            value2: icone.y - r.y - (r.height - icone.height) / 2
        };
        const cheio = { value1: r.width, value2: r.height };
        const pequeno = { value1: icone.width, value2: icone.height };
        const zero = { value1: 0.0, value2: 0.0 };
        window.setData(Effect.WindowForceBlurRole, true);
        return animate({
            window: window,
            curve: restaurando ? QEasingCurve.OutCubic : QEasingCurve.InOutCubic,
            duration: palcoAnim.duracaoEmCascata(),
            keepAlive: false,
            animations: [
                { type: Effect.Size, from: restaurando ? pequeno : cheio, to: restaurando ? cheio : pequeno },
                { type: Effect.Translation, from: restaurando ? desloc : zero, to: restaurando ? zero : desloc },
                { type: Effect.Opacity, from: restaurando ? 0.0 : 1.0, to: restaurando ? 1.0 : 0.0 }
            ]
        });
    },

    slotWindowMinimized: function (window) {
        if (!palcoAnim.deveAnimar(window))
            return;
        if (window.unminimizeAnimation) {
            if (redirect(window.unminimizeAnimation, Effect.Backward))
                return;
            cancel(window.unminimizeAnimation);
            delete window.unminimizeAnimation;
        }
        if (window.minimizeAnimation) {
            if (redirect(window.minimizeAnimation, Effect.Forward))
                return;
            cancel(window.minimizeAnimation);
        }
        window.minimizeAnimation = palcoAnim.animar(window, false);
    },

    slotWindowUnminimized: function (window) {
        if (!palcoAnim.deveAnimar(window))
            return;
        if (window.minimizeAnimation) {
            if (redirect(window.minimizeAnimation, Effect.Backward))
                return;
            cancel(window.minimizeAnimation);
            delete window.minimizeAnimation;
        }
        if (window.unminimizeAnimation) {
            if (redirect(window.unminimizeAnimation, Effect.Forward))
                return;
            cancel(window.unminimizeAnimation);
        }
        window.unminimizeAnimation = palcoAnim.animar(window, true);
    },

    slotWindowAdded: function (window) {
        window.minimizedChanged.connect(() => {
            if (window.minimized)
                palcoAnim.slotWindowMinimized(window);
            else
                palcoAnim.slotWindowUnminimized(window);
        });
    },

    restoreForceBlurState: function (window) {
        window.setData(Effect.WindowForceBlurRole, null);
    },

    init: function () {
        effect.configChanged.connect(palcoAnim.loadConfig);
        effect.animationEnded.connect(palcoAnim.restoreForceBlurState);
        effects.windowAdded.connect(palcoAnim.slotWindowAdded);
        for (const window of effects.stackingOrder)
            palcoAnim.slotWindowAdded(window);
    }
};

palcoAnim.init();
