#!/bin/bash
set -euo pipefail

# build-mac.sh
# Script determinístico de build do Linka para macOS.
# Evita proliferação de versões instaladas no LaunchServices/Spotlight
# consolidando o binário e desregistrando compilações antigas de DerivedData.
#
# Uso:
#   .agents/scripts/build-mac.sh            # Compila o app para build/macos/Linka.app
#   .agents/scripts/build-mac.sh --install  # Compila e instala em /Applications/Linka.app de forma limpa
#   .agents/scripts/build-mac.sh --clean    # Limpa caches antigos e unifica registros do LaunchServices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/aplicativo-ios"
OUTPUT_DIR="$REPO_ROOT/build/macos.noindex"
DERIVED_DATA_DIR="$REPO_ROOT/build/macos-derivedData.noindex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

DO_INSTALL=false
DO_CLEAN=false

for arg in "$@"; do
    case "$arg" in
        --install)
            DO_INSTALL=true
            ;;
        --clean)
            DO_CLEAN=true
            ;;
        --help|-h)
            echo "Uso: $0 [--install] [--clean]"
            echo "  --install   Instala a versão compilada em /Applications/Linka.app substituindo versões antigas"
            echo "  --clean     Limpa registros órfãos do LaunchServices e Spotlight de builds antigos"
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $arg"
            exit 1
            ;;
    esac
done

# Impede que o Spotlight indexe pastas de build e DerivedData
mkdir -p "$REPO_ROOT/build" "$OUTPUT_DIR" "$DERIVED_DATA_DIR"
touch "$REPO_ROOT/build/.metadata_never_index"
touch "$OUTPUT_DIR/.metadata_never_index"
touch "$DERIVED_DATA_DIR/.metadata_never_index"
if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    touch "$HOME/Library/Developer/Xcode/DerivedData/.metadata_never_index"
fi

cd "$APP_DIR"

echo "==> Sincronizando projeto com XcodeGen..."
xcodegen generate

echo "==> Compilando LinkaApp_macOS (Debug)..."
xcodebuild -project LinkaApp.xcodeproj \
           -scheme LinkaApp_macOS \
           -configuration Debug \
           -derivedDataPath "$DERIVED_DATA_DIR" \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGN_ENTITLEMENTS="" \
           build > /dev/null

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/Debug/LinkaApp.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "Erro: Binário não encontrado em $BUILT_APP" >&2
    exit 1
fi

rm -rf "$OUTPUT_DIR/Linka.app"
cp -R "$BUILT_APP" "$OUTPUT_DIR/Linka.app"

echo "==> App compilado com sucesso em: $OUTPUT_DIR/Linka.app"

# Função para remover e desregistrar versões antigas/órfãs do Spotlight e LaunchServices
cleanup_stale_registrations() {
    echo "==> Limpando builds duplicados do Spotlight e LaunchServices..."
    # Remove qualquer .app indexado pelo Spotlight fora de /Applications/Linka.app
    mdfind 'kMDItemContentType == "com.apple.application-bundle" && kMDItemFSName == "*Linka*"' 2>/dev/null | while IFS= read -r app_path; do
        if [ -n "$app_path" ] && [ "$app_path" != "/Applications/Linka.app" ] && [ "$app_path" != "$OUTPUT_DIR/Linka.app" ]; then
            if [ -x "$LSREGISTER" ]; then
                "$LSREGISTER" -u "$app_path" 2>/dev/null || true
            fi
            rm -rf "$app_path" 2>/dev/null || true
        fi
    done

    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -dump | grep -E "path: +/.*Linka.*\.app" | awk '{$1=""; print substr($0,2)}' | sed 's/ ([0-9a-fx]*)$//' | while IFS= read -r app_path; do
            if [ -n "$app_path" ] && [ "$app_path" != "/Applications/Linka.app" ]; then
                "$LSREGISTER" -u "$app_path" 2>/dev/null || true
            fi
        done
    fi
}

if [ "$DO_CLEAN" = true ] || [ "$DO_INSTALL" = true ]; then
    cleanup_stale_registrations
fi

if [ "$DO_INSTALL" = true ]; then
    echo "==> Instalando em /Applications/Linka.app..."
    if [ -d "/Applications/LinkaApp.app" ]; then
        "$LSREGISTER" -u "/Applications/LinkaApp.app" 2>/dev/null || true
        rm -rf "/Applications/LinkaApp.app"
    fi
    if [ -d "/Applications/Linka.app" ]; then
        "$LSREGISTER" -u "/Applications/Linka.app" 2>/dev/null || true
        rm -rf "/Applications/Linka.app"
    fi

    cp -R "$OUTPUT_DIR/Linka.app" "/Applications/Linka.app"
    # Desregistra e remove os binários intermediários de build ANTES de apagar do disco
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -u "$OUTPUT_DIR/Linka.app" 2>/dev/null || true
        "$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true
    fi
    rm -rf "$OUTPUT_DIR/Linka.app" "$BUILT_APP"

    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "/Applications/Linka.app"
    fi
    echo "==> Linka instalado com sucesso em /Applications/Linka.app (única instância no sistema)."
fi

echo "==> Concluído."
