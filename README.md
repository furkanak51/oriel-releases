# Oriel — indirmeler ve açık kaynak bileşenler

**Oriel**, Apple Silicon Mac'lerde Windows 11'i (ARM) kendi penceresinde çalıştıran bir sanal makine uygulamasıdır.
Uygulama, satış ve indirme sayfası: https://oriel-vm.vercel.app

Bu depo iki şey için vardır:

1. **İndirmeler** — Oriel'in DMG dosyaları ve güncelleme paketleri [Sürümler](../../releases) sayfasında yayımlanır.
2. **Motor ve kaynak kodu** — Oriel, sanal makineleri açık kaynak bileşenlerle çalıştırır (QEMU, virglrenderer,
   DXMT, ANGLE, spice-server, glib, swtpm/libtpms, wimlib, GNU xorriso ve diğerleri). Bu bileşenlerden oluşan
   "motor" paketi bu depodaki `engine/` betikleriyle GitHub Actions'ta derlenir. Her `engine-…` sürümünde motor
   paketi ile birlikte, copyleft lisanslı (GPL/LGPL) bileşenlerin tam kaynak kodu (`oss-sources-….tar`) da
   yayımlanır.

Oriel uygulamasının kendisi kapalı kaynaklıdır; motor ayrı süreçler olarak çalışır.

## Motoru yeniden derlemek

macOS 26 SDK'lı tam Xcode gerekir (DXMT'nin Metal derleyicisi ve ANGLE için):

```bash
engine/build-engine.sh          # build/engine/oriel-engine-<sürüm>-arm64.tar.xz ve oss-sources-<sürüm>.tar
engine/verify.sh build/engine/oriel-engine-<sürüm>-arm64
```

Ayrıntılar `engine/README.md` dosyasındadır.

## Lisanslar

- `engine/` altındaki betikler MIT lisanslıdır (bkz. `LICENSE`).
- Motor paketindeki her bileşen kendi lisansına tabidir; metinler paketin `Licenses/` klasöründe ve
  `THIRD_PARTY_NOTICES.txt` dosyasındadır.
- Windows, Microsoft Corporation'ın ticari markasıdır; QEMU, Fabrice Bellard'ın ticari markasıdır. Oriel bu
  şirketlerle ve Parallels ile bağlantılı değildir.

---

**English.** Oriel runs Windows 11 (ARM) on Apple silicon Macs. This repository hosts Oriel's downloads and the
build scripts for its open source "engine" (QEMU and friends). Every `engine-…` release ships the engine package
together with the complete corresponding source of its copyleft components. The scripts in `engine/` are MIT
licensed; every bundled component keeps its own license.
