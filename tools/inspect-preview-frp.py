"""Retired diagnostic: this preview's frpc is on 192.168.10.3, not this PC."""

raise SystemExit("Not applicable: do not inspect local MatrixMesh for this preview.")

import json
import sys
import tomllib
from pathlib import Path

directory = Path("C:/ProgramData/MatrixMesh")
output = Path(sys.argv[1])
result = {"stage": "frpc-config"}
try:
    config = tomllib.loads((directory / "frp/frpc.toml").read_text(encoding="utf-8-sig"))
    proxies = config.get("proxies", [])
    result = {
    "serverAddr": config.get("serverAddr"),
    "serverPort": config.get("serverPort"),
    "proxyCount": len(proxies),
    "proxies": [
        {key: proxy.get(key) for key in ("name", "type", "localIP", "localPort", "remotePort")}
        for proxy in proxies
        if proxy.get("localPort") == 8794 or proxy.get("remotePort") == 18794
    ],
    "remotePorts": [proxy.get("remotePort") for proxy in proxies],
    "hasWebServer": "webServer" in config,
    "runtimeFields": {},
    }
    for name in ("runtime-config.json", "deployment.json"):
        try:
            data = json.loads((directory / name).read_text(encoding="utf-8-sig"))
            result["runtimeFields"][name] = list(data)
        except Exception as error:
            result["runtimeFields"][name] = {"errorType": type(error).__name__}
except Exception as error:
    result["errorType"] = type(error).__name__
output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
