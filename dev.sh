#!/bin/bash
# uso: dev.sh <pasta-package> <nome>  -> carrega cópia com caminho único
S=${TMPDIR:-/tmp}/palco-dev
for n in org.sylvio.palco palcodev; do qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript $n >/dev/null; done
T=$S/build/$(date +%s%N); mkdir -p $T; cp -r "$1"/contents $T/
id=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript $T/contents/ui/main.qml "$2")
qdbus6 org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run
