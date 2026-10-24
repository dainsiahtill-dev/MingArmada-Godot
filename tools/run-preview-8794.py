"""Local documentation preview, supervised by Windows Task Scheduler."""

from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
import sys
import traceback


root = Path(__file__).resolve().parents[1]
story_root = (root / "docs" / "narrative" / "zheng-zhilong").resolve()


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(root), **kwargs)

    def send_head(self):
        # frp forwards requests through a local connection; route restrictions
        # must apply to loopback clients too, regardless of forwarded headers.
        target = Path(self.translate_path(self.path)).resolve()
        if not target.is_relative_to(story_root):
            self.send_error(403, "This preview publishes only the story reader")
            return None
        return super().send_head()

    def list_directory(self, path):
        self.send_error(403, "Directory listing is disabled")
        return None


log_dir = Path(os.environ["LOCALAPPDATA"]) / "MingArmada" / "preview-8794"
log_dir.mkdir(parents=True, exist_ok=True)
log_path = log_dir / "server.log"
if log_path.exists() and log_path.stat().st_size > 5 * 1024 * 1024:
    log_path.replace(log_dir / "server.previous.log")

with log_path.open("a", encoding="utf-8", buffering=1) as log:
    sys.stdout = sys.stderr = log
    try:
        with ThreadingHTTPServer(("0.0.0.0", 8794), PreviewHandler) as server:
            print("Serving the story reader on port 8794 for local, LAN and frp access", flush=True)
            server.serve_forever()
    except BaseException:
        traceback.print_exc()
    # An unattended preview should not exit successfully; let the task retry.
    sys.exit(1)
