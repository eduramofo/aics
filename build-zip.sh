#!/usr/bin/env bash
set -e

VERSION="1.0"
OUTPUT="AICS-v${VERSION}.zip"
DIR="$(cd "$(dirname "$0")" && pwd)"

FILES=(
    INSTALAR.bat
    DESINSTALAR.bat
    STATUS.bat
    setup.ps1
    install-service.ps1
    desinstalar.ps1
    verificar.ps1
    ativar-ics.ps1
    tray.ps1
    config.txt
    COMO_INSTALAR.txt
    GERENCIAR_SERVICOS.txt
    README.md
    nssm.exe
)

cd "$DIR"

# avisa sobre arquivos ausentes mas não para
for f in "${FILES[@]}"; do
    [[ ! -f "$f" ]] && echo "AVISO: $f não encontrado, será omitido do zip."
done

# remove zip anterior se existir
rm -f "$OUTPUT"

# cria o zip apenas com os arquivos existentes
zip "$OUTPUT" "${FILES[@]}" 2>/dev/null || \
    zip "$OUTPUT" $(for f in "${FILES[@]}"; do [[ -f "$f" ]] && echo "$f"; done)

echo "Gerado: $DIR/$OUTPUT"
