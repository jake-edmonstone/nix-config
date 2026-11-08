import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = {"client_id": "client:test", "connection_state": "connected",
          "info": {"kind": "app", "platform": "macos", "label": "Mac"},
          "principal": {"transport": "unix"}}
STUB = '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as f:
    f.write(json.dumps(args) + "\\n")
if "client" in args:
    print(json.dumps({"clients": json.loads(os.environ["CLIENTS"])}))
elif "ls" in args:
    print(json.dumps({"sessions": json.loads(os.environ.get("SESSIONS", "[]"))}))
elif "new" in args:
    if os.environ.get("FAIL") == "new": sys.exit(1)
    print(json.dumps({} if os.environ.get("FAIL") == "json" else {"session_id": "session:test"}))
elif "do" in args:
    if os.environ.get("FAIL") == "select": sys.exit(1)
else:
    sys.exit(9)
'''


@unittest.skipUnless(shutil.which("jq") and shutil.which("trash"), "jq and trash required")
class AssignmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="rex assignment ' "))
        self.addCleanup(lambda: subprocess.run(["trash", str(self.tmp)], check=True))
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for name, code in (("rex", STUB), ("nvim", "pass")):
            p = self.bin / name
            p.write_text(f"#!{sys.executable}\n" + code)
            p.chmod(0o755)
        self.work = self.tmp / "work"
        self.assignments = self.work / "academic/undergrad/term/course/assignments"
        self.assignments.mkdir(parents=True)
        self.target = self.assignments / "a3"
        self.calls = self.tmp / "calls.jsonl"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        TYPST_ROOT=str(self.work), CALLS=str(self.calls), CLIENTS=json.dumps([CLIENT]))
        self.env.pop("REX_CLIENT", None)

    def run_script(self, **env):
        return subprocess.run(["bash", str(ROOT / "scripts/new-assignment"), "--course", "course",
                               "--assignment", "3", "--layout", "1,2ab"],
                              env=self.env | env, capture_output=True, text=True, timeout=15)

    def test_success_and_quoting(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list(self.target.glob("*.typ"))), 4)
        for path in self.target.glob("*.typ"):
            self.assertIn('#import "../../course-preamble.typ": *', path.read_text())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        create = next(args for args in calls if args[0] == "new")
        self.assertEqual(create[create.index("-c") + 1], str(self.target))
        self.assertEqual(create[-2:], [str(self.bin / "nvim"), str(self.target / "a3.typ")])
        self.assertEqual(calls[-1], ["--autostart=false", "-C", "client:test", "do",
                                     "session.select", "session_id=session:test"])
        self.assertNotEqual(self.run_script().returncode, 0)

    def test_missing_ambiguous_and_explicit_clients(self):
        for clients in ([], [CLIENT, CLIENT | {"client_id": "client:other"}]):
            result = self.run_script(CLIENTS=json.dumps(clients))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.target.exists())
        result = self.run_script(CLIENTS=json.dumps([CLIENT, CLIENT | {"client_id": "client:other"}]),
                                 REX_CLIENT="client:other")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_label_collision_before_generation(self):
        result = self.run_script(SESSIONS=json.dumps([{"label": "typst_course_a3"}]))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.target.exists())

    def test_creation_and_selection_failures_preserve_files(self):
        for failure in ("new", "json", "select"):
            with self.subTest(failure=failure):
                result = self.run_script(FAIL=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((self.target / "a3.typ").is_file())
                self.assertIn("preserved", result.stderr)
                if failure == "select": self.assertIn("session:test", result.stdout)
                subprocess.run(["trash", str(self.target)], check=True)
