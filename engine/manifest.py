"""engine.json: motor sürümü, QEMU sürümü, EFI değişken şablonunun biçimi, ikili başına entitlement'lar ve her
dosyanın SHA-256 özeti. Uygulama motoru kendi klasörüne kopyalarken bu özetleri doğrular."""
import argparse
import hashlib
import json
import os


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--stage", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--qemu-version", required=True)
    p.add_argument("--vars-format", required=True)
    p.add_argument("--utm", required=True)
    p.add_argument("--entitlements", action="append", default=[], help="yol=entitlement[,entitlement]")
    a = p.parse_args()

    files = {}
    for dirpath, _, names in os.walk(a.stage):
        for n in names:
            full = os.path.join(dirpath, n)
            rel = os.path.relpath(full, a.stage)
            if rel == "engine.json" or os.path.islink(full):
                continue
            files[rel] = sha256(full)
    entitlements = {}
    for e in a.entitlements:
        path, _, ents = e.partition("=")
        entitlements[path] = ents.split(",")
    manifest = {
        "format": 1,
        "version": a.version,
        "qemuVersion": a.qemu_version,
        "utm": a.utm,
        "varsTemplate": "qemu/edk2-arm-vars.fd",
        "varsFormat": a.vars_format,
        "codeFirmware": "qemu/edk2-aarch64-code.fd",
        "entitlements": entitlements,
        "files": dict(sorted(files.items())),
    }
    with open(os.path.join(a.stage, "engine.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")
    print(f"engine.json: {len(files)} dosya, QEMU {a.qemu_version}, vars {a.vars_format}")


if __name__ == "__main__":
    main()
