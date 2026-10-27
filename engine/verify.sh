#!/bin/bash
# Motor paketini doğrular: bağımlılıklar paket içinde ya da sistemde, geliştirici/CI yolu yok, imzalar geçerli,
# QEMU'da hypervisor yetkisi var, engine.json özetleri tutuyor. Kullanım: engine/verify.sh <paket-klasörü>
set -euo pipefail
STAGE="${1:?paket klasörü}"
fail=0
err() { printf '\033[0;31mHATA: %s\033[0m\n' "$*" >&2; fail=1; }

machos=()
while IFS= read -r -d '' f; do
    file -b "$f" | grep -q "Mach-O" && machos+=("$f")
done < <(find "$STAGE/Helpers" "$STAGE/Frameworks" -type f -print0)
[ ${#machos[@]} -gt 0 ] || err "Mach-O dosyası bulunamadı"

for f in "${machos[@]}"; do
    own="$(otool -D "$f" | sed -n '2p')"
    while IFS= read -r dep; do
        [ -z "$dep" ] || [ "$dep" = "$own" ] && continue
        case "$dep" in
            /usr/lib/*|/System/*) ;;
            @rpath/*)
                rel="${dep#@rpath/}"
                [ -e "$STAGE/Frameworks/$rel" ] || err "${f#$STAGE/}: çözülemeyen $dep" ;;
            *) err "${f#$STAGE/}: sistem dışı bağımlılık $dep" ;;
        esac
    done < <(otool -L "$f" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility.*//')
    if strings -a "$f" | grep -E "/Users/runner|/opt/homebrew|/usr/local/(lib|opt|Cellar)" >/dev/null; then
        echo "uyarı: ${f#$STAGE/} içinde derleme makinesi yolu geçiyor (çalışmayı etkilemeyebilir)" >&2
    fi
done

# İmzalar: çerçeveler paket olarak, yardımcılar tek tek
for fw in "$STAGE"/Frameworks/*.framework; do
    codesign --verify --strict "$fw" 2>/dev/null || err "${fw#$STAGE/}: imza geçersiz"
done
for exe in "$STAGE"/Helpers/*; do
    codesign --verify --strict "$exe" 2>/dev/null || err "${exe#$STAGE/}: imza geçersiz"
done

for exe in "$STAGE"/Helpers/*; do
    otool -l "$exe" | grep -A2 LC_RPATH | grep -q "@executable_path/../Frameworks" \
        || { otool -L "$exe" | grep -q "@rpath" && err "${exe#$STAGE/}: @executable_path/../Frameworks rpath'i yok"; }
done

codesign -d --entitlements - --xml "$STAGE/Helpers/qemu-system-aarch64" 2>/dev/null \
    | grep -q "com.apple.security.hypervisor" || err "QEMU'da com.apple.security.hypervisor yok"

python3 -I - "$STAGE" <<'PY' || fail=1
import hashlib, json, os, sys
stage = sys.argv[1]
m = json.load(open(os.path.join(stage, "engine.json")))
bad = 0
for rel, want in m["files"].items():
    h = hashlib.sha256(open(os.path.join(stage, rel), "rb").read()).hexdigest()
    if h != want:
        print(f"HATA: özet uyuşmuyor: {rel}", file=sys.stderr); bad = 1
for rel in ("Helpers/qemu-system-aarch64", "Helpers/qemu-img", "Helpers/swtpm", "Helpers/virgl_render_server",
            "Helpers/wimlib-imagex", "Helpers/xorriso", m["varsTemplate"], m["codeFirmware"], "THIRD_PARTY_NOTICES.txt"):
    if rel not in m["files"]:
        print(f"HATA: pakette yok: {rel}", file=sys.stderr); bad = 1
sys.exit(bad)
PY

[ $fail = 0 ] && echo "motor doğrulandı: $STAGE" || { echo "motor doğrulaması BAŞARISIZ" >&2; exit 1; }
