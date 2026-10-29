"""Normal Explorer-started helper. No UI input, elevation, or system changes."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime, timezone
from ctypes import wintypes


def integrity(process_id):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    security = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    security.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    security.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    security.GetSidSubAuthorityCount.argtypes = [ctypes.c_void_p]
    security.GetSidSubAuthorityCount.restype = ctypes.POINTER(ctypes.c_ubyte)
    security.GetSidSubAuthority.argtypes = [ctypes.c_void_p, wintypes.DWORD]
    security.GetSidSubAuthority.restype = ctypes.POINTER(wintypes.DWORD)
    process = kernel.OpenProcess(0x1000, False, process_id)
    token = wintypes.HANDLE()
    try:
        if not process or not security.OpenProcessToken(process, 8, ctypes.byref(token)):
            raise ctypes.WinError(ctypes.get_last_error())
        size = wintypes.DWORD()
        security.GetTokenInformation(token, 25, None, 0, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        if not security.GetTokenInformation(token, 25, buffer, size, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        sid = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_void_p))[0]
        count = security.GetSidSubAuthorityCount(sid)[0]
        rid = security.GetSidSubAuthority(sid, count - 1)[0]
        for ceiling, level in [(0x1000, "Untrusted"), (0x2000, "Low"), (0x2100, "Medium"), (0x3000, "MediumPlus"), (0x4000, "High"), (0x5000, "System")]:
            if rid < ceiling:
                return level
        return "Protected"
    finally:
        if token:
            kernel.CloseHandle(token)
        if process:
            kernel.CloseHandle(process)


def slots(directory):
    result = {}
    for name in ["settings.json", "saves/mingqi-v2.json", "saves/legacy-v1.json"]:
        for suffix in ["", ".backup", ".rollback", ".staged"]:
            relative = name + suffix
            file = directory / relative
            result[relative] = hashlib.sha256(file.read_bytes()).hexdigest() if file.is_file() else None
    return result


def write_new(path, value):
    with path.open("x", encoding="utf-8") as file:
        json.dump(value, file, ensure_ascii=False, indent=2)


request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
output = Path(request["output"])
try:
    root = Path(__file__).resolve().parents[1]
    if Path(request["root"]).resolve() != root:
        raise RuntimeError("request-root-mismatch")
    helper_level = integrity(os.getpid())
    if helper_level != "Medium":
        raise RuntimeError("helper-integrity-not-medium:" + helper_level)
    profile = Path(request["profile"])
    if not profile.resolve().is_relative_to(root / "Temp/ming-maritime-profiles/native"):
        raise RuntimeError("profile-outside-native-isolation")
    original = Path(request["originalDirectory"])
    before = slots(original)
    if before != request["originalSlotsBefore"]:
        raise RuntimeError("original-slots-changed-before-launch")
    environment = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile))
    arguments = ["--path", str(root), "--resolution", "1600x900"]
    with (output / "game.log").open("xb") as log:
        child = subprocess.Popen([request["exe"], *arguments], cwd=root, env=environment,
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                 creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS)
    time.sleep(2)
    if child.poll() is not None:
        raise RuntimeError("game-exited-during-startup:" + str(child.returncode))
    child_level = integrity(child.pid)
    after = slots(original)
    receipt = dict(request, pid=child.pid, helperPid=os.getpid(), helperIntegrity=helper_level,
                   integrity=child_level, args=arguments, originalSlotsAfterLaunch=after,
                   originalSlotsUnchanged=before == after,
                   scope="Normal project main entry via existing Explorer; isolated APPDATA and LOCALAPPDATA; no UI input or scripted scene replacement.")
    write_new(output / "launch.json", receipt)
    (output / "pid.txt").write_text(str(child.pid), encoding="ascii")
    if child_level != "Medium":
        raise RuntimeError("game-integrity-not-medium:" + child_level)
    # Remain a hidden observer so a later normal quit or unexpected exit has an
    # exit code and original-slot check. Never send input or terminate the game.
    exit_code = child.wait()
    final_slots = slots(original)
    write_new(output / "process-exit.json", {"pid": child.pid, "exitCode": exit_code,
              "observedAtUtc": datetime.now(timezone.utc).isoformat(),
              "originalSlotsAfterExit": final_slots,
              "originalSlotsUnchanged": before == final_slots})
except Exception as error:
    write_new(output / "launch-error.json", {"error": str(error), "helperPid": os.getpid()})
