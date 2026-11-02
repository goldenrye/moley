#!/bin/bash
set -euo pipefail

export PATH="${MOLEY_GO_BIN:-/opt/homebrew/bin}:/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v go >/dev/null || { echo "error: Install Go and set MOLEY_GO_BIN in Config/Local.xcconfig."; exit 1; }

source_dir="${SRCROOT}/Vendor/WireGuard/Sources/WireGuardKitGo"
if [[ ! -f "$source_dir/Makefile" ]]; then
    echo "error: Missing vendored WireGuardKit at $source_dir."
    exit 1
fi

# The upstream bridge needs a patched Go runtime so timers include device sleep.
# Keep its GOROOT isolated from the installed Go toolchain.
case "$PLATFORM_NAME" in
    iphoneos) target="apple-ios${IPHONEOS_DEPLOYMENT_TARGET}" ;;
    iphonesimulator) target="apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator" ;;
    *) echo "error: Unsupported platform: $PLATFORM_NAME"; exit 1 ;;
esac

for arch in $ARCHS; do
    /usr/bin/make -C "$source_dir" \
        ARCHS="$arch" \
        GOOS_iphonesimulator=ios \
        CC="$(xcrun --find clang)" \
        CFLAGS_PREFIX="-target ${arch}-${target} -isysroot ${SDKROOT} -arch" \
        BUILDDIR="${PROJECT_TEMP_DIR}/WireGuardGo-${arch}" \
        DESTDIR="${PROJECT_TEMP_DIR}/WireGuardGo-${arch}/out"
done

archives=()
for arch in $ARCHS; do
    archives+=("${PROJECT_TEMP_DIR}/WireGuardGo-${arch}/out/libwg-go.a")
done
mkdir -p "$BUILT_PRODUCTS_DIR"
xcrun lipo -create "${archives[@]}" -output "$BUILT_PRODUCTS_DIR/libwg-go.a"
