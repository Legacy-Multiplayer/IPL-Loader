"""Run Lua checks in Legacy Server with the real Addon-Sscanf loaded."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import zipfile


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Legacy-IPL-checks"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def released_binary(repository, archive, checksum_file, name):
    base = "https://github.com/Legacy-Multiplayer/" + repository + "/releases/download/v1.0.0/"
    data = download(base + archive)
    checksums = download(base + checksum_file).decode("utf-8")
    checksum = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1] == archive)
    assert hashlib.sha256(data).hexdigest() == checksum, "Release checksum mismatch"
    if archive.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as bundle:
            entries = [entry for entry in bundle.namelist() if Path(entry).name.lower() == name.lower()]
            assert len(entries) == 1, "Expected one release binary"
            return bundle.read(entries[0])
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as bundle:
        entries = [entry for entry in bundle.getmembers() if Path(entry.name).name.lower() == name.lower() and entry.isfile()]
        assert len(entries) == 1, "Expected one release binary"
        return bundle.extractfile(entries[0]).read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, help="Use a local server binary")
    parser.add_argument("--scanner", type=Path, help="Use a local Addon-Sscanf binary")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    windows = os.name == "nt"
    executable = "server.exe" if windows else "server"
    plugin = "Addon-Sscanf.dll" if windows else "Addon-Sscanf.so"
    with tempfile.TemporaryDirectory(prefix="legacy-ipl-checks-") as temporary:
        root = Path(temporary)
        (root / "addons").mkdir()
        (root / "main").mkdir()
        shutil.copytree(source / "includes", root / "includes")
        shutil.copytree(source / "tests", root / "tests")
        if args.server:
            (root / executable).write_bytes(args.server.read_bytes())
        else:
            archive = "Legacy-Server-Windows-x86.zip" if windows else "Legacy-Server-Linux-x86.tar.gz"
            (root / executable).write_bytes(released_binary("Server", archive, "SHA256SUMS", executable))
        if args.scanner:
            (root / "addons" / plugin).write_bytes(args.scanner.read_bytes())
        else:
            archive = "Addon-Sscanf-windows-x86.zip" if windows else "Addon-Sscanf-linux-x86.tar.gz"
            (root / "addons" / plugin).write_bytes(released_binary("Addon-Sscanf", archive, archive + ".sha256", plugin))
        (root / executable).chmod(0o755)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        (root / "setup.json").write_text(json.dumps({
            "server": {"port": port, "maxplayers": 8, "lanmode": True, "announce_server": False},
            "asset": {"http": False}, "main": "main", "scripts": [],
        }), encoding="utf-8")
        (root / "main/main.lua").write_text('''addEventHandler("onMainScriptInit", function()
    assert(type(sscanfTable) == "function", "Addon-Sscanf did not load")
    dofile("tests/check-ipl.lua")
    dofile("tests/check-features.lua")
    print("IPL_NATIVE_CHECKS_COMPLETE")
end)
''', encoding="utf-8")
        with (root / "console.log").open("w") as output:
            process = subprocess.Popen([str(root / executable), "--nogui"], cwd=root,
                stdout=output, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if windows else 0)
            try:
                deadline = time.monotonic() + 45
                while time.monotonic() < deadline:
                    log = (root / "server.log").read_text(errors="replace") if (root / "server.log").exists() else ""
                    if "Lua error" in log or "Initialization failed" in log:
                        raise RuntimeError(log)
                    if "IPL_NATIVE_CHECKS_COMPLETE" in log:
                        for line in log.splitlines():
                            if "PASS " in line or "checks passed" in line:
                                print(line)
                        print("PASS: parser checks use the actual Addon-Sscanf plugin")
                        break
                    if process.poll() is not None:
                        raise RuntimeError(log + (root / "console.log").read_text(errors="replace"))
                    time.sleep(0.1)
                else:
                    raise RuntimeError("Native checks timed out: " + log)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == "__main__":
    main()
