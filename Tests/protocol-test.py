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
    requests = [{"id": i + 1, "command": command, "payload": {"sources": ["日本語 ' $.txt"]}} for i, command in enumerate(commands)]
    delete_payload = {"storageId": 65537, "Files": ["/Download/日本語 ' $.txt", "/Download/Folder"]}
    requests.append({"id": 8, "command": "delete", "payload": delete_payload})
    for i, invalid in enumerate([[], ["/"], ["/Download/../Pictures"], ["relative.txt"]], start=9):
        requests.append({"id": i, "command": "delete", "payload": {"storageId": 65537, "Files": invalid}})
    payload = "".join(json.dumps(request) + "\n" for request in requests)
    output = subprocess.run([str(root / "Pori.app/Contents/MacOS/mtp-helper"), str(fake)], input=payload, text=True, capture_output=True, check=True, timeout=10)
    rows = [json.loads(line) for line in output.stdout.splitlines()]
    completed = [row for row in rows if row["event"] == "done"]
    assert [row["id"] for row in completed] == list(range(1, len(requests) + 1))
    assert completed[1]["result"]["data"][0]["Info"]["FreeSpaceInBytes"] == 9_000_000_000
    assert completed[2]["result"]["data"][0]["name"] == "日本語.txt"
    assert [row["event"] for row in rows if row["id"] == 5] == ["preprocess", "progress", "done"]
    assert completed[5]["result"]["errorType"] == "ErrorDeviceChanged"
    assert completed[6]["result"]["data"] is True
    assert completed[7]["result"]["testRequest"] == delete_payload
    for rejected in completed[8:]:
        assert rejected["result"]["errorType"] == "ProtocolError"
        assert "testRequest" not in rejected["result"]
print("Native bridge: progress, Unicode, large sizes, device errors, deletion payload and invalid-target rejection passed")
