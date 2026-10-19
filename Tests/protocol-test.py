"""Exercises the real native bridge with a deterministic test-only MTP ABI."""
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pori-protocol-") as directory:
    fake = pathlib.Path(directory) / "fake.dylib"
    subprocess.run(["xcrun", "clang", "-dynamiclib", str(root / "Tests/fake-kalam.c"), "-o", str(fake)], check=True)
    commands = ["connect", "storages", "list", "exists", "upload", "download", "disconnect"]
    payload = "".join(json.dumps({"id": i + 1, "command": command, "payload": {"sources": ["日本語 ' $.txt"]}}) + "\n" for i, command in enumerate(commands))
    output = subprocess.run([str(root / "Pori.app/Contents/MacOS/mtp-helper"), str(fake)], input=payload, text=True, capture_output=True, check=True, timeout=10)
    rows = [json.loads(line) for line in output.stdout.splitlines()]
    completed = [row for row in rows if row["event"] == "done"]
    assert [row["id"] for row in completed] == list(range(1, 8))
    assert completed[1]["result"]["data"][0]["Info"]["FreeSpaceInBytes"] == 9_000_000_000
    assert completed[2]["result"]["data"][0]["name"] == "日本語.txt"
    assert [row["event"] for row in rows if row["id"] == 5] == ["preprocess", "progress", "done"]
    assert completed[5]["result"]["errorType"] == "ErrorDeviceChanged"
    assert completed[6]["result"]["data"] is True
print("Native bridge: streaming progress, request IDs, Unicode, 64-bit sizes and device errors passed")
