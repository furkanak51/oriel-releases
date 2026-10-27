#!/bin/bash
# Copyleft (GPL/LGPL) bileşenlerin tam kaynak kodu, değişikliklerimiz ve derleme betikleri → tek arşiv (.tar).
# İzinli lisanslı bileşenler (MIT/BSD/Apache) kaynak dağıtımı gerektirmez; onların lisans metinleri motor paketinde.
# Kullanım: engine/oss-sources.sh <UTM-klasörü> <araç-klasörü> <çıktı.tar>
set -euo pipefail
UTM="$1"; TOOLS="$2"; OUTFILE="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$UTM/build-macOS-arm64"
TMP="$(mktemp -d)"
D="$TMP/oss-sources"
mkdir -p "$D/upstream" "$D/build-scripts"

# UTM'nin indirip derlediği copyleft kaynak arşivleri (qemu arşivi UTM yamalarını zaten içerir)
for pat in 'qemu-*.tar.*' 'glib-*.tar.*' 'gettext-*.tar.*' 'libiconv-*.tar.*' 'spice-0.*.tar.*' 'libusb-*.tar.*' \
           'usbredir-*.tar.*' 'gstreamer-1.*.tar.*' 'gst-plugins-base-*.tar.*'; do
    found=0
    for f in "$B"/$pat; do
        [ -f "$f" ] || continue
        cp "$f" "$D/upstream/"; found=1
    done
    [ $found = 1 ] || { echo "hata: kaynak arşivi yok: $pat" >&2; exit 1; }
done

# DXMT (LGPL-2.1+) git deposu olarak gelir
if git -C "$B/dxmt.git" rev-parse HEAD >/dev/null 2>&1; then
    c="$(git -C "$B/dxmt.git" rev-parse --short=12 HEAD)"
    git -C "$B/dxmt.git" archive --format=tar.gz --prefix="dxmt-$c/" -o "$D/upstream/dxmt-$c.tar.gz" HEAD
else
    tar -C "$B" --exclude .git --exclude 'build*' -czf "$D/upstream/dxmt.tar.gz" dxmt.git
fi

# wimlib ve GNU xorriso (GPL-3.0)
cp "$TOOLS"/dl/wimlib-*.tar.gz "$TOOLS"/dl/xorriso-*.tar.gz "$D/upstream/"

# Derleme betikleri: UTM'nin betik ve yamaları (sabit etiket) + bizim engine/ klasörümüz (yamalar dahil)
utm_ref="$(git -C "$UTM" describe --tags --always 2>/dev/null || git -C "$UTM" rev-parse --short HEAD)"
git -C "$UTM" archive --format=tar.gz --prefix="UTM-$utm_ref/" -o "$D/build-scripts/UTM-$utm_ref-scripts-patches.tar.gz" HEAD scripts patches
tar -C "$ROOT" --exclude __pycache__ -czf "$D/build-scripts/oriel-engine-scripts.tar.gz" engine .github/workflows/engine.yml

cat > "$D/README.txt" <<EOF
Oriel motoru — copyleft bileşenlerin tam kaynak kodu / complete corresponding source

upstream/       GPL/LGPL bileşenlerin kaynak arşivleri: QEMU (UTM yamalı), glib, gettext (libintl), libiconv,
                spice-server, libusb, usbredir, GStreamer çekirdek ve plugins-base, DXMT, wimlib, GNU xorriso
build-scripts/  UTM $utm_ref scripts/ ve patches/ ile Oriel'in engine/ betikleri (glib yaması dahil)

Yeniden derleme / rebuild: oriel-engine-scripts.tar.gz içindeki engine/build-engine.sh betiği, macOS 26 SDK'lı tam
Xcode ile çalıştırılır (GitHub Actions: .github/workflows/engine.yml). Betik UTM'yi $utm_ref etiketinden indirir,
scripts/build_dependencies.sh'i uyarlar ve yukarıdaki arşivlerle aynı kaynakları derler.

Kaynak, ilgili motor paketiyle aynı sürüm sayfasında (https://github.com/furkanak51/oriel-releases) yayımlanır.
EOF

mkdir -p "$(dirname "$OUTFILE")"
tar -C "$TMP" -cf "$OUTFILE" oss-sources
rm -rf "$TMP"
echo "kaynak arşivi: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
