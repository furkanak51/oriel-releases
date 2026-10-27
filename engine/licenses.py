"""Lisans metinlerini licenses.tsv'ye göre toplar ve THIRD_PARTY_NOTICES.txt yazar.

Her tablo satırının en az bir lisans dosyası bulunmalı; paketteki her çerçeve ve yardımcı program da bir satır
tarafından kapsanmalı. İkisinden biri eksikse derleme durur (lisanssız ikili dağıtılmaz).
"""
import argparse
import fnmatch
import glob
import os
import shutil
import sys

SOURCE_OFFER = """Kaynak kodu / Source code
Bu pakette GPL ve LGPL lisanslı bileşenler vardır. Bu bileşenlerin tam kaynak kodu, değişikliklerimiz ve derleme
betikleri, paketle aynı yerde (https://github.com/furkanak51/oriel-releases, ilgili engine-… sürümü,
oss-sources-<sürüm>.tar.xz) yayımlanır. Copyleft bileşenler Oriel uygulamasından ayrı süreçler (QEMU, swtpm,
wimlib-imagex, xorriso) ya da bu süreçlerin yüklediği değiştirilebilir dinamik kitaplıklar olarak çalışır.

The GPL/LGPL components in this package, our modifications and the build scripts are published at the same
location (https://github.com/furkanak51/oriel-releases, matching engine-… release, oss-sources-<version>.tar.xz).
"""


def read_table(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != 5:
            sys.exit(f"licenses.tsv: 5 sütun bekleniyordu: {line!r}")
        name, spdx, provides, dir_glob, files = cols
        rows.append({
            "name": name, "spdx": spdx,
            "provides": [] if provides == "-" else provides.split(","),
            "dir_glob": dir_glob, "files": files.split(),
        })
    return rows


def source_dirs(roots, pattern):
    found = []
    for root in roots:
        if pattern == ".":
            found.append(root)
        elif pattern.startswith("**/"):
            sub = pattern[3:]
            for dirpath, dirnames, _ in os.walk(root):
                if dirpath[len(root):].count(os.sep) >= 6:
                    dirnames[:] = []
                    continue
                found += [os.path.join(dirpath, d) for d in dirnames if fnmatch.fnmatch(d, sub)]
        else:
            found += [d for d in glob.glob(os.path.join(root, pattern)) if os.path.isdir(d)]
    return found


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--table", required=True)
    p.add_argument("--search", action="append", required=True)
    p.add_argument("--dest", required=True)
    p.add_argument("--notices", required=True)
    p.add_argument("--frameworks", required=True)
    p.add_argument("--helpers", required=True)
    a = p.parse_args()

    rows = read_table(a.table)
    errors, notices = [], []
    for r in rows:
        copied = []
        for d in source_dirs(a.search, r["dir_glob"]):
            for pat in r["files"]:
                for f in glob.glob(os.path.join(d, pat)):
                    if os.path.isfile(f):
                        out = os.path.join(a.dest, r["name"], os.path.relpath(f, d).replace(os.sep, "_"))
                        if not os.path.exists(out):
                            os.makedirs(os.path.dirname(out), exist_ok=True)
                            shutil.copy2(f, out)
                            copied.append(os.path.basename(out))
            if copied:
                break
        if not copied:
            errors.append(f"{r['name']}: lisans dosyası bulunamadı ({r['dir_glob']}: {' '.join(r['files'])})")
        notices.append(f"{r['name']}  [{r['spdx']}]  Licenses/{r['name']}/: {', '.join(sorted(copied))}")

    provided = {x for r in rows for x in r["provides"]}
    shipped = [f[: -len(".framework")] for f in os.listdir(a.frameworks) if f.endswith(".framework")]
    shipped += os.listdir(a.helpers)
    for item in shipped:
        if item not in provided:
            errors.append(f"{item}: licenses.tsv'de karşılığı yok")
    if errors:
        sys.exit("\n".join(errors))

    with open(a.notices, "w", encoding="utf-8") as f:
        f.write("Oriel motoru — üçüncü taraf bileşenler / third-party components\n\n")
        f.write("\n".join(notices) + "\n\n" + SOURCE_OFFER)
    print(f"lisanslar: {len(rows)} bileşen")


if __name__ == "__main__":
    main()
