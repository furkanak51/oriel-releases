#!/bin/bash
# Oriel motor paketini derler: UTM'nin QEMU çatalı (2D + 3D) + virglrenderer/Neptune + DXMT + ANGLE,
# qemu-img, swtpm, wimlib-imagex ve GNU xorriso. Homebrew'a çalışma anında bağımlılık yoktur.
#
# Çıktılar ($OUT, varsayılan build/engine):
#   oriel-engine-<sürüm>-arm64.tar.xz (+ .sha256)   uygulamanın gömdüğü motor
#   oss-sources-<sürüm>.tar (+ .sha256)              copyleft bileşenlerin tam kaynak kodu ve derleme betikleri
#
# Tam Xcode + macOS 26 SDK + Metal araçları gerekir (DXMT metal derleyicisi, ANGLE xcodebuild); bu yüzden CI'da
# (macos-26) çalışır. Kullanım: engine/build-engine.sh   (ortam: WORK, OUT, VERSION, NCPU)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ENGINE="$ROOT/engine"

UTM_TAG="v5.0.8"
VERSION="${VERSION:-utm-5.0.8-3}"
WORK="${WORK:-$ROOT/.engine-work}"
OUT="${OUT:-$ROOT/build/engine}"
NAME="oriel-engine-$VERSION-arm64"
STAGE="$OUT/$NAME"
MINOS="12.0"   # UTM'nin macOS alt sınırıyla aynı (uygulama kendisi macOS 26 ister)

WIMLIB_VER="1.14.5"
WIMLIB_URL="https://wimlib.net/downloads/wimlib-$WIMLIB_VER.tar.gz"
WIMLIB_SHA="84221a3abd5b91228f15f8e6065c335a336237b5738197b75bf419eea561a194"
XORRISO_VER="1.5.8.pl02"
XORRISO_URL="https://www.gnu.org/software/xorriso/xorriso-$XORRISO_VER.tar.gz"
XORRISO_SHA="b1455ecafbf0692ddafe1d71002a96f2ce2d77f4deae602678261ce033f97bc8"
# EDK2: UTM'nin sysroot'undaki derleme her açılışta UTM logosu gösterir ve tek başına ramfb'yi başlatmaz (Windows
# kurulumunda ekran gelmez). Yerine QEMU'nun resmi pc-bios derlemesi (Homebrew QEMU 11.1.2'dekiyle bayt bayt aynı).
EDK2_QEMU_TAG="v11.1.2"
EDK2_BASE="https://gitlab.com/qemu-project/qemu/-/raw/$EDK2_QEMU_TAG/pc-bios"
EDK2_CODE_SHA="c023444108b7a132fdebf70c4765cd2dd9af2a9ff7d001a743aaabe87c20a458"   # edk2-aarch64-code.fd.bz2
EDK2_VARS_SHA="0011d83b5e67c691a58e3ae25a2e7fdf1d245a73d1b2b8bccb24af1a8c2e2523"   # edk2-arm-vars.fd.bz2
EDK2_LICENSES_SHA="1ddeaed2e7d2e9ecb960bdfc1b8ee45387aff70d056d985d145949af3951657c" # edk2-licenses.txt

say() { printf '\033[0;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[0;31mhata: %s\033[0m\n' "$*" >&2; exit 1; }

# UTM betiğinde bir satırı değiştirir; eşleşme yoksa sessizce geçmek yerine durur (sürüm kayması).
replace_line() {
    local file="$1" old="$2" new="$3"
    OLD="$old" NEW="$new" perl -0pi -e '$n += s/\Q$ENV{OLD}\E/$ENV{NEW}/; END { exit($n ? 0 : 3) }' "$file" \
        || die "$file içinde beklenen satır yok: $old"
}

fetch() { # url sha256 hedef
    [ -f "$3" ] && echo "$2  $3" | shasum -a 256 -c --status && return 0
    curl -fL --retry 3 -o "$3" "$1"
    echo "$2  $3" | shasum -a 256 -c --status || die "SHA-256 uyuşmuyor: $1"
}

# QEMU fork'u HVF'nin 4 KB IPA ayarını (3D blob belleği için şart) macOS 26'da yalnızca 26 SDK'sıyla derlenince
# genel API'den yapar; eski SDK'da VM HV_UNSUPPORTED ile açılmaz.
SDK_MAJOR="$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)"
[ "$SDK_MAJOR" -ge 26 ] || die "macOS 26 SDK gerekli (şu an $(xcrun --sdk macosx --show-sdk-version))"

mkdir -p "$WORK" "$OUT"

# ---------------------------------------------------------------- UTM bağımlılıkları ve QEMU
UTM="$WORK/UTM"
if [ ! -d "$UTM/.git" ]; then
    say "UTM $UTM_TAG indiriliyor"
    # CI önbelleği kaynak arşivlerini klondan önce $UTM altına geri yükleyebilir: klonu yanına alıp birleştir
    rm -rf "$UTM.clone"
    git clone --depth 1 --branch "$UTM_TAG" https://github.com/utmapp/UTM.git "$UTM.clone"
    if [ -d "$UTM" ]; then cp -a "$UTM/." "$UTM.clone/"; rm -rf "$UTM"; fi
    mv "$UTM.clone" "$UTM"
fi
git -C "$UTM" checkout -q -- scripts/build_dependencies.sh

say "UTM derleme betiği uyarlanıyor"
B="$UTM/scripts/build_dependencies.sh"
# QEMU kütüphane değil, Cocoa'lı bağımsız program (yalnız aarch64-softmmu); araçlar (qemu-img) varsayılan olarak derlenir
replace_line "$B" 'QEMU_PLATFORM_BUILD_FLAGS="--enable-shared-lib --disable-cocoa --disable-sdl --cpu=$CPU"' \
                  'QEMU_PLATFORM_BUILD_FLAGS="--enable-cocoa --disable-sdl --cpu=$CPU --target-list=aarch64-softmmu --enable-tools"'
replace_line "$B" $'\nbuild_spice_client\n' $'\n: # build_spice_client (Oriel: gerekmiyor)\n'
replace_line "$B" $'\nbuild_vulkan_drivers\n' $'\n: # build_vulkan_drivers (Oriel: Neptune için gerekmiyor)\n'

# Kendi kaynak yamalarımız (UTM betiği patches/<kaynak-adı>.patch dosyasını açtığı kaynağa uygular):
#   glib-2.83.0: macOS'ta select() taklidi yerine gerçek poll() — 3D'de QEMU 1024'ten fazla tanıtıcı açar
for p in "$ENGINE"/patches/*.patch; do
    dest="$UTM/patches/$(basename "$p")"
    if [ -f "$dest" ] && ! cmp -s "$p" "$dest"; then die "UTM'de aynı adlı yama var: $(basename "$p")"; fi
    cp "$p" "$dest"
done

if [ -f "$UTM/build-macOS-arm64/BUILD_SUCCESS" ] && [ -n "${SKIP_UTM_BUILD:-}" ]; then
    say "UTM derlemesi atlanıyor (SKIP_UTM_BUILD)"
else
    say "Bağımlılıklar ve QEMU derleniyor (uzun sürer)"
    (cd "$UTM" && NCPU="${NCPU:-0}" ./scripts/build_dependencies.sh -p macos -a arm64)
fi
SYSROOT="$UTM/sysroot-macOS-arm64"
UTMBUILD="$UTM/build-macOS-arm64"
for f in bin/qemu-system-aarch64 bin/qemu-img libexec/virgl_render_server \
         Frameworks/dxmt-native.framework/Versions/A/dxmt-native Frameworks/swtpm.0.framework/swtpm.0; do
    [ -e "$SYSROOT/$f" ] || die "UTM derlemesi eksik: $f"
done

# ---------------------------------------------------------------- wimlib ve GNU xorriso (yalnız sistem kitaplıkları)
TOOLS="$WORK/tools"
mkdir -p "$TOOLS/dl" "$TOOLS/src" "$TOOLS/prefix"
export MACOSX_DEPLOYMENT_TARGET="$MINOS"
TOOLCFLAGS="-arch arm64 -mmacosx-version-min=$MINOS -O2"

say "wimlib $WIMLIB_VER"
fetch "$WIMLIB_URL" "$WIMLIB_SHA" "$TOOLS/dl/wimlib-$WIMLIB_VER.tar.gz"
rm -rf "$TOOLS/src/wimlib-$WIMLIB_VER" && tar -xzf "$TOOLS/dl/wimlib-$WIMLIB_VER.tar.gz" -C "$TOOLS/src"
(cd "$TOOLS/src/wimlib-$WIMLIB_VER" && CFLAGS="$TOOLCFLAGS" ./configure --prefix="$TOOLS/prefix" \
    --without-ntfs-3g --without-fuse --disable-shared --enable-static --disable-dependency-tracking >/dev/null \
    && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null)

say "GNU xorriso $XORRISO_VER"
fetch "$XORRISO_URL" "$XORRISO_SHA" "$TOOLS/dl/xorriso-$XORRISO_VER.tar.gz"
XSRC="$TOOLS/src/xorriso-${XORRISO_VER%%.pl*}"
rm -rf "$XSRC" && tar -xzf "$TOOLS/dl/xorriso-$XORRISO_VER.tar.gz" -C "$TOOLS/src"
(cd "$XSRC" && CFLAGS="$TOOLCFLAGS" ./configure --prefix="$TOOLS/prefix" --disable-shared --enable-static \
    --disable-dependency-tracking --disable-libreadline --disable-libedit --disable-libacl --disable-xattr \
    --disable-zlib --disable-libbz2 --disable-libcdio --disable-external-filters --disable-launch-frontend >/dev/null \
    && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null)

# ---------------------------------------------------------------- paket yerleşimi
say "Paket hazırlanıyor: $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/Helpers" "$STAGE/Frameworks" "$STAGE/qemu" "$STAGE/Licenses"

cp -a "$SYSROOT/bin/qemu-system-aarch64" "$SYSROOT/bin/qemu-img" "$SYSROOT/libexec/virgl_render_server" "$STAGE/Helpers/"
cp -a "$TOOLS/prefix/bin/wimlib-imagex" "$TOOLS/prefix/bin/xorriso" "$STAGE/Helpers/"

# swtpm: UTM onu kitaplık olarak derler (swtpm_main); küçük bir başlatıcı aynı komut satırını sunar
clang -target arm64-apple-macos"$MINOS" -O2 -o "$STAGE/Helpers/swtpm" "$ENGINE/swtpm-launcher.c" \
    -F "$SYSROOT/Frameworks" -framework swtpm.0 -Wl,-rpath,@executable_path/../Frameworks

# Programlar sysroot'taki dylib'lere değil paket içindeki çerçevelere bağlansın
for exe in qemu-system-aarch64 qemu-img virgl_render_server; do
    "$UTM/scripts/fixup.sh" -p macos -s "$SYSROOT" -i "$STAGE/Helpers/$exe"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$STAGE/Helpers/$exe" 2>/dev/null || true
done

# Yalnız ulaşılan çerçeveler: yardımcılardan otool yürüyüşü + çalışma anında yüklenenler
# (DXMT mutlak yolla, ANGLE libepoxy'nin dlopen'ıyla)
python3 -I "$ENGINE/closure.py" --frameworks "$SYSROOT/Frameworks" --dest "$STAGE/Frameworks" \
    --root "$STAGE/Helpers/qemu-system-aarch64" --root "$STAGE/Helpers/qemu-img" \
    --root "$STAGE/Helpers/virgl_render_server" --root "$STAGE/Helpers/swtpm" \
    --runtime dxmt-native.framework --runtime EGL.framework --runtime GLESv2.framework

# Firmware: yalnız aarch64 virt + aygıt kümemizin kullandıkları (QEMU'ya -L <motor>/qemu verilir).
# EDK2 QEMU'nun resmi pc-bios'undan (yukarıdaki not), seçenek ROM'ları ve tuş eşlemleri UTM sysroot'undan.
fetch "$EDK2_BASE/edk2-aarch64-code.fd.bz2" "$EDK2_CODE_SHA" "$TOOLS/dl/edk2-aarch64-code-$EDK2_QEMU_TAG.fd.bz2"
fetch "$EDK2_BASE/edk2-arm-vars.fd.bz2" "$EDK2_VARS_SHA" "$TOOLS/dl/edk2-arm-vars-$EDK2_QEMU_TAG.fd.bz2"
fetch "$EDK2_BASE/edk2-licenses.txt" "$EDK2_LICENSES_SHA" "$TOOLS/dl/edk2-licenses-$EDK2_QEMU_TAG.txt"
bunzip2 -c "$TOOLS/dl/edk2-aarch64-code-$EDK2_QEMU_TAG.fd.bz2" > "$STAGE/qemu/edk2-aarch64-code.fd"
bunzip2 -c "$TOOLS/dl/edk2-arm-vars-$EDK2_QEMU_TAG.fd.bz2" > "$STAGE/qemu/edk2-arm-vars.fd"
cp "$TOOLS/dl/edk2-licenses-$EDK2_QEMU_TAG.txt" "$STAGE/qemu/edk2-licenses.txt"
for f in efi-virtio.rom vgabios-ramfb.bin; do
    cp -a "$SYSROOT/share/qemu/$f" "$STAGE/qemu/"
done
cp -a "$SYSROOT/share/qemu/keymaps" "$STAGE/qemu/keymaps"

# ---------------------------------------------------------------- lisanslar
say "Lisans metinleri"
python3 -I "$ENGINE/licenses.py" --table "$ENGINE/licenses.tsv" --search "$UTMBUILD" --search "$TOOLS/src" \
    --search "$SYSROOT/share/qemu" --dest "$STAGE/Licenses" --notices "$STAGE/THIRD_PARTY_NOTICES.txt" \
    --frameworks "$STAGE/Frameworks" --helpers "$STAGE/Helpers"

{
    echo "Oriel motoru $VERSION"
    echo "UTM $UTM_TAG ($(git -C "$UTM" rev-parse HEAD)) scripts/build_dependencies.sh ile derlendi."
    echo "QEMU yapılandırması: --enable-cocoa --disable-sdl --target-list=aarch64-softmmu --enable-tools"
    echo "Atlanan adımlar: build_spice_client, build_vulkan_drivers"
    echo "Ek araçlar: wimlib $WIMLIB_VER ($WIMLIB_SHA), GNU xorriso $XORRISO_VER ($XORRISO_SHA)"
    echo "EDK2: QEMU $EDK2_QEMU_TAG pc-bios (edk2-aarch64-code.fd.bz2 $EDK2_CODE_SHA)"
    echo "oriel-releases: $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo yerel)"
    echo
    cat "$UTM/patches/sources"
} > "$STAGE/SOURCES.txt"

# ---------------------------------------------------------------- imza (ad-hoc; uygulama paketlenirken yeniden imzalanır)
say "İmzalanıyor (ad-hoc)"
find "$STAGE/Frameworks" -maxdepth 1 -name '*.framework' -exec codesign --force --sign - {} \;
for exe in "$STAGE"/Helpers/*; do
    if [ "$(basename "$exe")" = qemu-system-aarch64 ]; then
        codesign --force --sign - --entitlements "$ENGINE/qemu.entitlements" "$exe"
    else
        codesign --force --sign - "$exe"
    fi
done

# ---------------------------------------------------------------- engine.json (sürümler, dosya özetleri, entitlement'lar)
QEMU_VERSION="$("$STAGE/Helpers/qemu-system-aarch64" --version | head -1 | sed -E 's/.*version ([^ ]+).*/\1/')"
VARS_FORMAT="$("$STAGE/Helpers/qemu-img" info --output=json "$STAGE/qemu/edk2-arm-vars.fd" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["format"])')"
python3 -I "$ENGINE/manifest.py" --stage "$STAGE" --version "$VERSION" --qemu-version "$QEMU_VERSION" \
    --vars-format "$VARS_FORMAT" --utm "$UTM_TAG" --entitlements "Helpers/qemu-system-aarch64=com.apple.security.hypervisor"

"$ENGINE/verify.sh" "$STAGE"

# ---------------------------------------------------------------- arşivler
say "Arşivleniyor"
tar -C "$OUT" -cJf "$OUT/$NAME.tar.xz" "$NAME"
(cd "$OUT" && shasum -a 256 "$NAME.tar.xz" > "$NAME.tar.xz.sha256")

say "Copyleft kaynak arşivi"
"$ENGINE/oss-sources.sh" "$UTM" "$TOOLS" "$OUT/oss-sources-$VERSION.tar"
(cd "$OUT" && shasum -a 256 "oss-sources-$VERSION.tar" > "oss-sources-$VERSION.tar.sha256")

say "hazır"
cat "$OUT"/*.sha256
du -sh "$STAGE" "$OUT"/*.tar.xz "$OUT"/*.tar
