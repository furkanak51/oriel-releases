# Oriel motoru

`build-engine.sh`, UTM v5.0.8'in `scripts/build_dependencies.sh` betiğini sabit etiketten indirip uyarlar ve şunları
üretir:

| Yol | İçerik |
|---|---|
| `Helpers/qemu-system-aarch64` | UTM'nin QEMU çatalı (10.0.12-utm), Cocoa'lı bağımsız program, 2D ve 3D |
| `Helpers/qemu-img` | disk ve snapshot işlemleri |
| `Helpers/swtpm` | `swtpm-launcher.c`: UTM'nin kitaplık olarak derlediği swtpm'i (libtpms 0.9.6) çağırır |
| `Helpers/virgl_render_server` | 3D (Neptune/DXMT) render sunucusu |
| `Helpers/wimlib-imagex`, `Helpers/xorriso` | Windows ESD → kurulum ISO'su (yalnız sistem kitaplıkları) |
| `Frameworks/` | `closure.py` ile bulunan bağımlılık kapanışı + çalışma anında yüklenenler (DXMT, ANGLE) |
| `qemu/` | QEMU'ya `-L` ile verilen firmware ve tuş eşlemleri (yalnız aarch64 virt için gerekenler) |
| `Licenses/`, `THIRD_PARTY_NOTICES.txt` | `licenses.tsv` ile toplanan lisans metinleri; eksik varsa derleme durur |
| `engine.json` | sürümler, EFI değişken şablonunun biçimi, entitlement'lar, her dosyanın SHA-256'sı |

Doğrulama: `verify.sh` (bağımlılık yolları, imzalar, entitlement, özetler) ve `smoke-test.sh` (TCG ile açılış,
qemu-img, swtpm, wimlib, xorriso). Yayın: `engine-<sürüm>` etiketi → GitHub Actions (`.github/workflows/engine.yml`).
