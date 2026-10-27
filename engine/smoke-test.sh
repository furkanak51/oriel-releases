#!/bin/bash
# Motor duman testi (CI'da HVF yok: QEMU TCG ile yalnız açılıp kapanır). Kullanım: engine/smoke-test.sh <paket>
set -euo pipefail
S="${1:?paket klasörü}"
H="$S/Helpers"
T="$(mktemp -d)"
trap 'rm -rf "$T"; [ -n "${TPM_PID:-}" ] && kill "$TPM_PID" 2>/dev/null || true' EXIT
ok() { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }

VARS_FORMAT="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["varsFormat"])' "$S/engine.json")"

"$H/qemu-system-aarch64" -machine help | grep -q "^virt-10.0 " && ok "virt-10.0 makinesi"
"$H/qemu-system-aarch64" -device help | grep -q '"virtio-gpu-gl-pci"' && ok "virtio-gpu-gl-pci (3D)"
"$H/qemu-system-aarch64" -display help | grep -q cocoa && ok "cocoa ekranı"

# Firmware, virtio-net seçenek ROM'u (-L), slirp ağı ve VNC tuş eşlemleriyle açılıp QMP'den kapanmalı
printf '{"execute":"qmp_capabilities"}\n{"execute":"query-status"}\n{"execute":"quit"}\n' \
    | "$H/qemu-system-aarch64" -L "$S/qemu" -M virt-10.0 -accel tcg -cpu max -m 512 -S -nodefaults -display none \
        -drive if=pflash,format=raw,readonly=on,file="$S/qemu/edk2-aarch64-code.fd" \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
        -vnc unix:"$T/vnc.sock" -qmp stdio > "$T/qmp.out"
grep -q '"status"' "$T/qmp.out" && ok "QEMU TCG ile açılıp kapandı"

# Windows kurulum ekranı ramfb'dir: firmware onu başlatmalı. Başlatmazsa QEMU 640×480 "Guest has not initialized
# the display" yer tutucusunu verir; EDK2 ramfb'yi 800×600 açar.
"$H/qemu-img" convert -f "$VARS_FORMAT" -O qcow2 "$S/qemu/edk2-arm-vars.fd" "$T/fbvars.qcow2"
"$H/qemu-system-aarch64" -L "$S/qemu" -M virt-10.0 -accel tcg -cpu max -m 512 -nodefaults -display none -device ramfb \
    -drive if=pflash,format=raw,readonly=on,file="$S/qemu/edk2-aarch64-code.fd" \
    -drive if=pflash,format=qcow2,file="$T/fbvars.qcow2" -qmp unix:"$T/qmp.sock",server=on,wait=off &
FB_PID=$!
fb=""
for _ in $(seq 1 60); do
    sleep 2
    [ -S "$T/qmp.sock" ] || continue
    rm -f "$T/fb.ppm"
    python3 -I - "$T/qmp.sock" "$T/fb.ppm" <<'PY' || true
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw")
f.readline(); f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n"); f.flush(); f.readline()
f.write(json.dumps({"execute": "screendump", "arguments": {"filename": sys.argv[2]}}) + "\n"); f.flush(); f.readline()
PY
    fb="$(head -c 20 "$T/fb.ppm" 2>/dev/null | sed -n 2p)"
    [ -n "$fb" ] && [ "$fb" != "640 480" ] && break
done
kill "$FB_PID" 2>/dev/null || true
[ -n "$fb" ] && [ "$fb" != "640 480" ] && ok "firmware ramfb ekranını açtı ($fb)" || { echo "hata: firmware ramfb ekranını açmadı" >&2; exit 1; }

"$H/qemu-img" create -q -f qcow2 "$T/disk.qcow2" 1G && "$H/qemu-img" info "$T/disk.qcow2" | grep -q qcow2 && ok "qemu-img"
"$H/qemu-img" convert -f "$VARS_FORMAT" -O qcow2 "$S/qemu/edk2-arm-vars.fd" "$T/vars.qcow2" && ok "EFI değişken şablonu ($VARS_FORMAT)"

"$H/swtpm" socket --print-capabilities | grep -q '"tpm-2.0"' && ok "swtpm yetenekleri"
mkdir -p "$T/tpm"
"$H/swtpm" socket --tpm2 --tpmstate dir="$T/tpm" --ctrl type=unixio,path="$T/ctrl.sock" \
    --server type=unixio,path="$T/data.sock" --flags not-need-init,startup-clear --log file="$T/swtpm.log" &
TPM_PID=$!
for _ in $(seq 1 50); do [ -S "$T/ctrl.sock" ] && break; sleep 0.1; done
[ -S "$T/ctrl.sock" ] && kill -0 "$TPM_PID" && ok "swtpm soketle çalışıyor"

mkdir -p "$T/src/sub" && echo merhaba > "$T/src/sub/a.txt"
"$H/wimlib-imagex" capture "$T/src" "$T/t.wim" "deneme" >/dev/null && "$H/wimlib-imagex" info "$T/t.wim" >/dev/null && ok "wimlib-imagex"
"$H/xorriso" -as mkisofs -o "$T/t.iso" -iso-level 3 -J -joliet-long -R "$T/src" 2>/dev/null && [ -s "$T/t.iso" ] && ok "xorriso"

echo "duman testi tamam"
