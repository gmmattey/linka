#!/bin/bash
set -euo pipefail

# build-mac-direct.sh
# Gera o Linka para Mac para download direto no site (fora da App Store):
# app Release com LINKA_DIRECT_DOWNLOAD, entitlements sem recursos que exigem
# perfil da App Store, hardened runtime, DMG e, quando há credenciais, assinatura
# Developer ID + notarização.
#
# Uso:
#   .agents/scripts/build-mac-direct.sh --unsigned   # só para testar localmente (Gatekeeper bloqueia)
#   DEVELOPER_ID_IDENTITY="Developer ID Application: Nome (TEAMID)" \
#   NOTARY_PROFILE="linka-notary" \
#     .agents/scripts/build-mac-direct.sh            # assina, notariza e carimba
#
# NOTARY_PROFILE é criado uma vez pelo proprietário da conta:
#   xcrun notarytool store-credentials linka-notary --apple-id <id> --team-id 2Z4T8228GR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/aplicativo-ios"
OUT="$REPO_ROOT/build/macos-direct.noindex"
DD="$OUT/derivedData"
UNSIGNED=false
[ "${1:-}" = "--unsigned" ] && UNSIGNED=true

if [ "$UNSIGNED" = false ]; then
    : "${DEVELOPER_ID_IDENTITY:?Defina DEVELOPER_ID_IDENTITY (certificado Developer ID Application)}"
    : "${NOTARY_PROFILE:?Defina NOTARY_PROFILE (perfil do notarytool)}"
fi

mkdir -p "$OUT"; touch "$OUT/.metadata_never_index"
cd "$APP_DIR"
xcodegen generate

SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
[ "$UNSIGNED" = false ] && SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=2Z4T8228GR)

xcodebuild -project LinkaApp.xcodeproj -scheme LinkaApp_macOS -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DD" \
    LINKA_ENTITLEMENTS_SUFFIX=-Direct \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LINKA_DIRECT_DOWNLOAD' \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
    "${SIGN_ARGS[@]}" build

APP="$DD/Build/Products/Release/LinkaApp.app"
[ -d "$APP" ] || { echo "App não encontrado em $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")

STAGE="$OUT/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Linka.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Linka-$VERSION-$BUILD.dmg"; rm -f "$DMG"
hdiutil create -volname "Linka" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ "$UNSIGNED" = false ]; then
    codesign --verify --deep --strict --verbose=2 "$STAGE/Linka.app"
    codesign --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

shasum -a 256 "$DMG"
echo "==> Pronto: $DMG"
