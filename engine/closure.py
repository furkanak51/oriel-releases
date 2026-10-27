"""Çerçeve bağımlılık kapanışı: köklerden `otool -L` yürüyüşüyle ulaşılan @rpath çerçevelerini kopyalar.

Kökler yardımcı programlar (--root) ve çalışma anında yüklenen çerçevelerdir (--runtime: DXMT mutlak yolla,
ANGLE libepoxy'nin dlopen'ıyla yüklenir; otool bunları göremez). Çözülemeyen @rpath ya da sistem dışı mutlak yol
bulunursa durur. Kopyalanmayan çerçeveler boyutlarıyla listelenir (sessiz atma yok).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def framework_binary(fw_dir):
    base = os.path.basename(fw_dir)[: -len(".framework")]
    for cand in (os.path.join(fw_dir, "Versions", "A", base), os.path.join(fw_dir, base)):
        if os.path.isfile(cand) and not os.path.islink(cand):
            return cand
    for cand in (os.path.join(fw_dir, "Versions", "Current", base), os.path.join(fw_dir, base)):
        if os.path.exists(cand):
            return os.path.realpath(cand)
    sys.exit(f"çerçeve ikilisi yok: {fw_dir}")


def dependencies(binary):
    own_id = run("otool", "-D", binary).splitlines()[1:]
    own_id = own_id[0].strip() if own_id else None
    for line in run("otool", "-L", binary).splitlines()[1:]:
        path = line.strip().split(" (compatibility")[0].strip()
        if path and path != own_id:
            yield path


def size_of(path):
    total = 0
    for dirpath, _, files in os.walk(path):
        for f in files:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total += os.path.getsize(fp)
    return total


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--frameworks", required=True, help="kaynak Frameworks klasörü (sysroot)")
    p.add_argument("--dest", required=True)
    p.add_argument("--root", action="append", default=[])
    p.add_argument("--runtime", action="append", default=[])
    a = p.parse_args()

    needed, errors = set(), []
    queue = list(a.root)
    for fw in a.runtime:
        if not os.path.isdir(os.path.join(a.frameworks, fw)):
            sys.exit(f"çalışma anı çerçevesi yok: {fw}")
        needed.add(fw)
        queue.append(framework_binary(os.path.join(a.frameworks, fw)))
    seen = set()
    while queue:
        binary = queue.pop()
        if binary in seen:
            continue
        seen.add(binary)
        for dep in dependencies(binary):
            m = re.match(r"@rpath/([^/]+\.framework)/", dep)
            if m:
                fw = m.group(1)
                fw_dir = os.path.join(a.frameworks, fw)
                if not os.path.isdir(fw_dir):
                    errors.append(f"{binary}: çözülemeyen {dep}")
                    continue
                if fw not in needed:
                    needed.add(fw)
                    queue.append(framework_binary(fw_dir))
            elif dep.startswith(SYSTEM_PREFIXES):
                continue
            else:
                errors.append(f"{binary}: sistem dışı bağımlılık {dep}")
    if errors:
        sys.exit("\n".join(errors))

    os.makedirs(a.dest, exist_ok=True)
    kept = dropped = 0
    for fw in sorted(os.listdir(a.frameworks)):
        if not fw.endswith(".framework"):
            continue
        src = os.path.join(a.frameworks, fw)
        size = size_of(src)
        if fw in needed:
            shutil.copytree(src, os.path.join(a.dest, fw), symlinks=True)
            kept += size
            print(f"  + {fw} ({size // 1024} KB)")
        else:
            dropped += size
            print(f"  - {fw} ({size // 1024} KB, kullanılmıyor)")
    print(f"çerçeveler: {len(needed)} alındı ({kept // 1048576} MB), {dropped // 1048576} MB atıldı")


if __name__ == "__main__":
    main()
