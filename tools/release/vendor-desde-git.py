#!/usr/bin/env python3
"""Instala vendor/ de la API a partir de composer.lock descargando cada paquete con git.

Sirve cuando Composer no puede descargar los .zip de GitHub (por ejemplo, detrás de
un proxy que solo deja pasar git) y para no llenar el disco con el historial de git
(Composer, si no puede usar los .zip, clona los repositorios completos).

Para cada paquete trae solo la revisión fijada en composer.lock (git fetch --depth 1)
y la extrae con «git archive», que respeta export-ignore como los .zip de GitHub.
Después escribe vendor/composer/installed.json y genera el autoload con Composer.

Uso:
    python3 tools/release/vendor-desde-git.py api [--no-dev]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor


def fetch(package, vendor, work):
    name = package["name"]
    source = package.get("source") or {}
    url, ref = source.get("url"), source.get("reference")
    target = os.path.join(vendor, name)
    if not url or not ref:
        raise RuntimeError(f"{name}: sin origen git en composer.lock")
    repo = os.path.join(work, name.replace("/", "__"))
    os.makedirs(repo)
    run = lambda *args: subprocess.run(args, cwd=repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    run("git", "init", "-q")
    for attempt in range(4):
        try:
            run("git", "fetch", "-q", "--depth", "1", url, ref)
            break
        except subprocess.CalledProcessError:
            if attempt == 3:
                raise
    os.makedirs(target, exist_ok=True)
    archive = subprocess.Popen(["git", "archive", "FETCH_HEAD"], cwd=repo, stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", target], stdin=archive.stdout, check=True)
    if archive.wait() != 0:
        raise RuntimeError(f"{name}: git archive falló")
    shutil.rmtree(repo)
    return name


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    api = os.path.abspath(sys.argv[1])
    no_dev = "--no-dev" in sys.argv
    lock = json.load(open(os.path.join(api, "composer.lock")))
    packages = list(lock["packages"])
    dev_packages = [] if no_dev else list(lock.get("packages-dev", []))
    vendor = os.path.join(api, "vendor")
    shutil.rmtree(vendor, ignore_errors=True)
    os.makedirs(os.path.join(vendor, "composer"))
    with tempfile.TemporaryDirectory() as work:
        with ThreadPoolExecutor(max_workers=6) as pool:
            for name in pool.map(lambda p: fetch(p, vendor, work), packages + dev_packages):
                print("  -", name)
    installed = []
    for package in packages + dev_packages:
        entry = dict(package)
        entry["installation-source"] = "dist"
        entry["install-path"] = "../" + package["name"]
        installed.append(entry)
    json.dump({
        "packages": installed,
        "dev": not no_dev,
        "dev-package-names": [p["name"] for p in dev_packages],
    }, open(os.path.join(vendor, "composer", "installed.json"), "w"), indent=4)
    # Ejecutables de los paquetes (vendor/bin), como los crea Composer.
    for package in packages + dev_packages:
        for binary in package.get("bin", []):
            os.makedirs(os.path.join(vendor, "bin"), exist_ok=True)
            target = os.path.join(vendor, "bin", os.path.basename(binary))
            with open(target, "w") as proxy:
                proxy.write("#!/usr/bin/env php\n<?php\n\nrequire __DIR__.'/../%s/%s';\n" % (package["name"], binary))
            os.chmod(target, 0o755)
    env = dict(os.environ, COMPOSER_ALLOW_SUPERUSER="1")
    args = ["composer", "dump-autoload", "--optimize", "--no-interaction"] + (["--no-dev"] if no_dev else [])
    subprocess.run(args, cwd=api, check=True, env=env)
    # Que «composer install» posterior no reinstale nada (vendor/composer/installed.php ya está).
    print("vendor/ listo:", len(installed), "paquetes" + (" (sin los de desarrollo)" if no_dev else ""))


if __name__ == "__main__":
    main()
