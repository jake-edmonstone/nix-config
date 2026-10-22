import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class EngineTicketLauncherTests(unittest.TestCase):
    def test_new_session_runs_codex_vdi_as_a_fish_child(self):
        with tempfile.TemporaryDirectory(prefix="engine-ticket-launcher-") as directory:
            path = Path(directory)
            engine = path / "engine"
            engine.mkdir()
            script = path / "engine-ticket"
            script.write_text((ROOT / "scripts/engine-ticket").read_text()
                              .replace("engine_repo=/scratch/dev/engine", "engine_repo=" + shlex.quote(str(engine)), 1)
                              .replace("dev_root=/scratch/dev", "dev_root=" + shlex.quote(str(path)), 1))
            calls = path / "calls.jsonl"
            mock = path / "mock-command"
            mock.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "name, args = Path(sys.argv[0]).name, sys.argv[1:]\n"
                "with open(os.environ['MOCK_CALLS'], 'a') as log:\n"
                "    log.write(json.dumps({'command': name, 'args': args}) + '\\n')\n"
                "if name == 'git':\n"
                "    args = args[2:]\n"
                "    if args == ['rev-parse', '--show-toplevel']:\n"
                "        print(os.environ['MOCK_ENGINE_REPO'])\n"
                "    if args[0] == 'show-ref': sys.exit(1)\n"
                "    if args[0] == 'ls-remote': sys.exit(2)\n"
                "if name == 'tmux' and args[0] == 'has-session': sys.exit(1)\n"
            )
            mock.chmod(0o700)
            for name in ("git", "tmux", "codex-vdi", "nvim", "lazygit", "fish"):
                (path / name).symlink_to(mock)
            env = dict(os.environ)
            env.pop("TMUX", None)
            env["PATH"] = str(path) + os.pathsep + env["PATH"]
            env["MOCK_CALLS"] = str(calls)
            env["MOCK_ENGINE_REPO"] = str(engine)
            result = subprocess.run(
                ["bash", str(script), "EVAL-9999", path.name],
                env=env, capture_output=True, text=True, timeout=5, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in calls.read_text().splitlines()]
            session = next(event["args"] for event in events
                           if event["command"] == "tmux" and event["args"][0] == "new-session")
            self.assertEqual(session[-3:], [str(path / "fish"), "-C", str(path / "codex-vdi")])
            windows = [event["args"] for event in events
                       if event["command"] == "tmux" and event["args"][0] == "new-window"]
            self.assertIn([str(path / "fish"), "-C", str(path / "nvim") + " ."],
                          [arguments[-3:] for arguments in windows])
            self.assertFalse(any(event["command"] == "codex-vdi" for event in events))


if __name__ == "__main__":
    unittest.main()
