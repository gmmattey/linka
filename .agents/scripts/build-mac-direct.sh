#!/bin/bash
set -euo pipefail

# build-mac-direct.sh
# Gera o Linka para Mac para download direto no site (fora da App Store):
# app Release com LINKA_DIRECT_DOWNLOAD, entitlements sem recursos que exigem
# perfil da App Store, hardened runtime e DMG.
#
# Modos:
#   --unsigned   Só para testar a compilação; o Gatekeeper bloqueia.
#   (padrão)     Xcode gerenciado: archive com assinatura automática, notarização
#                pelo próprio xcodebuild (-exportArchive com destino upload e
#                -exportNotarizedApp) e DMG. Exige a conta da equipe 2Z4T8228GR
#                logada no Xcode, com o contrato de programa aceito.
#   identidade   Com DEVELOPER_ID_IDENTITY e NOTARY_PROFILE no ambiente: assina o
#                app com o certificado Developer ID do Keychain e notariza com o
#                notarytool (perfil criado por `xcrun notarytool store-credentials`).
#
# Saída: build/macos-direct.noindex/Linka-<versão>-<build>.dmg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/aplicativo-ios"
OUT="$REPO_ROOT/build/macos-direct.noindex"
DD="$OUT/derivedData"
TEAM=2Z4T8228GR
MODE=managed
[ "${1:-}" = "--unsigned" ] && MODE=unsigned
[ "$MODE" = managed ] && [ -n "${DEVELOPER_ID_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ] && MODE=identity

DIRECT_ARGS=(LINKA_ENTITLEMENTS_SUFFIX=-Direct
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LINKA_DIRECT_DOWNLOAD'
    ENABLE_HARDENED_RUNTIME=YES)

mkdir -p "$OUT"; touch "$OUT/.metadata_never_index"
cd "$APP_DIR"
xcodegen generate

make_dmg() { # app, versão, build
    local app="$1" stage="$OUT/stage"
    rm -rf "$stage"; mkdir -p "$stage"
    cp -R "$app" "$stage/Linka.app"
    ln -s /Applications "$stage/Applications"
    DMG="$OUT/Linka-$2-$3.dmg"; rm -f "$DMG"
    hdiutil create -volname "Linka" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
}

read_version() { # app
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$1/Contents/Info.plist")
    BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$1/Contents/Info.plist")
}

case "$MODE" in
unsigned|identity)
    if [ "$MODE" = unsigned ]; then
        SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
    else
        SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=$TEAM
            OTHER_CODE_SIGN_FLAGS="--timestamp")
    fi
    xcodebuild -project LinkaApp.xcodeproj -scheme LinkaApp_macOS -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$DD" \
        "${DIRECT_ARGS[@]}" "${SIGN_ARGS[@]}" build
    APP="$DD/Build/Products/Release/LinkaApp.app"
    [ -d "$APP" ] || { echo "App não encontrado em $APP" >&2; exit 1; }
    read_version "$APP"
    make_dmg "$APP" "$VERSION" "$BUILD"
    if [ "$MODE" = identity ]; then
        codesign --verify --deep --strict --verbose=2 "$APP"
        codesign --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        spctl --assess --type open --context context:primary-signature -v "$DMG"
    fi
    ;;
managed)
    ARCHIVE="$OUT/Linka.xcarchive"
    rm -rf "$ARCHIVE" "$OUT/export" "$OUT/notarized"
    xcodebuild -project LinkaApp.xcodeproj -scheme LinkaApp_macOS -configuration Release \
        -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/archiveDerivedData" \
        "${DIRECT_ARGS[@]}" -allowProvisioningUpdates archive > "$OUT/archive.log" 2>&1 \
        || { grep -E "error:" "$OUT/archive.log" | head -5; exit 1; }

    cat > "$OUT/exportUpload.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$TEAM</string>
<key>signingStyle</key><string>automatic</string>
<key>destination</key><string>upload</string>
</dict></plist>
EOF
    # Envia para a notarização da Apple.
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/exportUpload.plist" \
        -exportPath "$OUT/export" -allowProvisioningUpdates > "$OUT/export.log" 2>&1 \
        || { grep -vi progress "$OUT/export.log" | tail -8; exit 1; }

    # Espera o resultado e baixa o app já notarizado e carimbado.
    NOTARIZED=false
    for _ in $(seq 1 60); do
        if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/notarized" \
            > "$OUT/notarized.log" 2>&1; then NOTARIZED=true; break; fi
        sleep 20
    done
    $NOTARIZED || { grep -vi progress "$OUT/notarized.log" | tail -8; echo "Notarização não concluída." >&2; exit 1; }

    APP="$OUT/notarized/LinkaApp.app"
    xcrun stapler validate "$APP"
    spctl --assess --type execute -vv "$APP"
    read_version "$APP"
    make_dmg "$APP" "$VERSION" "$BUILD"
    ;;
esac

shasum -a 256 "$DMG"
echo "==> Pronto ($MODE): $DMG"
