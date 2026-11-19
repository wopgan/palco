# Palco

Script do KWin (Plasma 6, Wayland) estilo Stage Manager: miniaturas das janelas
minimizadas da área de trabalho atual numa faixa à esquerda.

- Clique: restaura e foca. Botão do meio: fecha.
- Se alguma janela cobre a faixa, ela recolhe numa alça fina; passe o mouse para abrir.

Instalar: `kpackagetool6 --type=KWin/Script -i package` e ativar em
Configurações > Gerenciamento de janelas > Scripts do KWin (ou
`kwriteconfig6 --file kwinrc --group Plugins --key org.sylvio.palcoEnabled true`
+ `qdbus6 org.kde.KWin /KWin reconfigure`).

Desenvolvimento: o KWin guarda o QML em cache pelo caminho do arquivo; reinstalar
e reconfigurar não pega a mudança até reiniciar a sessão. Use `./dev.sh package palcodev`,
que carrega uma cópia de um caminho novo a cada vez.
