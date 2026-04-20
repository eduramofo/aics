#!/usr/bin/env bash
set -e

VERSION="1.0"
OUTPUT="AICS-v${VERSION}.zip"
DIR="$(cd "$(dirname "$0")" && pwd)"

FILES=(
    cmd/INSTALAR.bat
    cmd/DESINSTALAR.bat
    cmd/STATUS.bat
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

# coleta apenas os arquivos existentes
EXISTING=()
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] && EXISTING+=("$f")
done

# cria o zip: usa 'zip' no Linux, PowerShell no Windows
if command -v zip &>/dev/null; then
    zip "$OUTPUT" "${EXISTING[@]}"
else
    powershell -NoProfile -Command "
        \$files = @($(printf "'%s'," "${EXISTING[@]}" | sed 's/,$//'))
        Compress-Archive -Path \$files -DestinationPath '${OUTPUT}' -Force
    "
fi

echo "Gerado: $DIR/$OUTPUT"
