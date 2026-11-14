"""Exercise the lifecycle CLI's destructive-action boundary with a real listener."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LifecycleTest(unittest.TestCase):
    def test_foreign_listener_is_not_adopted_or_stopped(self):
        with tempfile.TemporaryDirectory() as directory:
            server = subprocess.Popen([
                sys.executable, "-c",
                "from http.server import HTTPServer, SimpleHTTPRequestHandler; "
                "s = HTTPServer(('127.0.0.1', 0), SimpleHTTPRequestHandler); "
                "print(s.server_port, flush=True); s.serve_forever()",
            ], cwd=directory, stdout=subprocess.PIPE, text=True)
            try:
                port = server.stdout.readline().strip()
                self.assertTrue(port.isdigit())
                for action in ("server-start", "server-stop"):
                    with self.subTest(action=action):
                        result = subprocess.run(
                            [sys.executable, "scripts/dev.py", action], cwd=ROOT,
                            env={**os.environ, "PORT": port}, capture_output=True, text=True,
                            timeout=10,
                        )
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("refusing to touch it", result.stderr)
                        self.assertIsNone(server.poll())
            finally:
                server.terminate()
                server.wait(timeout=5)
                server.stdout.close()
