import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest


REPO = Path(__file__).resolve().parents[1]
SKILL = REPO / "config/codex/skills/engine-ticket-workflow"
SCRIPT = SKILL / "scripts/workflow.py"


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="engine-workflow-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.engine = self.root / "engine"
        self.engine.mkdir()
        self.git("init", "--initial-branch=master")
        self.git("config", "user.name", "Workflow Test")
        self.git("config", "user.email", "workflow@example.invalid")
        (self.engine / "source.cpp").write_text("int value = 1;\n")
        (self.engine / ".gitignore").write_text("ignored-output\n")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.git("update-ref", "refs/remotes/origin/master", "HEAD")
        self.git("switch", "-c", "CE-1234/developer/fixture")
        self.data = self.root / "private"
        self.logs = self.root / "logs"
        self.mock = self.root / "bazel"
        self.mock.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys, time\n"
            "from pathlib import Path\n"
            "print(repr(sys.argv[1:]), flush=True)\n"
            "if os.environ.get('EVENTS'):\n"
            "    with open(os.environ['EVENTS'], 'a') as f: f.write('start\\n')\n"
            "time.sleep(float(os.environ.get('DELAY', '0')))\n"
            "if os.environ.get('MUTATE'): Path('source.cpp').write_text('int value = 9;\\n')\n"
            "if os.environ.get('EVENTS'):\n"
            "    with open(os.environ['EVENTS'], 'a') as f: f.write('end\\n')\n"
            "sys.exit(int(os.environ.get('EXIT_CODE', '0')))\n"
        )
        self.mock.chmod(0o700)
        self.key = "CE-1234"

    def git(self, *args, root=None):
        return subprocess.check_output(["git", "-C", str(root or self.engine), *args], stderr=subprocess.DEVNULL).decode().strip()

    def invocation(self, *args):
        return [sys.executable, str(SCRIPT), "--engine-repo", str(self.engine), "--data-dir", str(self.data), "--log-dir", str(self.logs), "--bazel-bin", str(self.mock), *args]

    def run_helper(self, *args, cwd=None, env=None, check=True):
        result = subprocess.run(self.invocation(*args), cwd=cwd or self.engine, env={**os.environ, **(env or {})}, capture_output=True, text=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def initialize(self, cwd=None):
        self.run_helper("init", self.key, cwd=cwd)
        return self.data / "tickets" / self.key

    def snapshot(self):
        return self.run_helper("snapshot", self.key).stdout.strip()

    def test_initialization_preserves_user_guidance_and_existing_records(self):
        self.data.mkdir()
        preferences = self.data / "preferences.md"
        preferences.write_text("# My preferences\nKeep this exact text.\n")
        (self.engine / "source.cpp").write_text("int value = 2;\n")
        (self.engine / "user-note.txt").write_text("user-owned")
        path = self.initialize()
        (path / "context.md").write_text("original conversation")
        self.run_helper("init", self.key)
        self.assertEqual(preferences.read_text(), "# My preferences\nKeep this exact text.\n")
        self.assertEqual((path / "context.md").read_text(), "original conversation")
        self.assertIn("int value = 2", (path / "baseline.patch").read_text())
        self.assertIn("user-note.txt", (path / "status.md").read_text())
        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertEqual((path / "status.md").stat().st_mode & 0o777, 0o600)

    def test_engine_identity_accepts_sibling_and_rejects_unrelated_checkout(self):
        sibling = self.root / "sibling"
        self.git("worktree", "add", "-b", "CE-4567/developer/sibling", str(sibling), "master")
        result = self.run_helper("identify", cwd=sibling)
        self.assertEqual(result.stdout.strip(), str(sibling))
        other = self.root / "other"
        other.mkdir()
        self.git("init", root=other)
        result = self.run_helper("identify", cwd=other, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a worktree", result.stderr)

    def test_wrong_ticket_and_changed_branch_cannot_reuse_dossier(self):
        self.assertNotEqual(self.run_helper("init", "CE-9999", check=False).returncode, 0)
        self.initialize()
        self.git("branch", "-m", "CE-1234/developer/different")
        result = self.run_helper("init", self.key, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("different branch/worktree", result.stderr)

    def test_fingerprint_tracks_code_untracked_guidance_and_plan_not_logs(self):
        path = self.initialize()
        current = self.snapshot()
        for file in [self.engine / "source.cpp", self.engine / "untracked.cpp", self.data / "preferences.md", self.data / "lessons.md", path / "context.md", path / "brief.md", path / "plan.md"]:
            with file.open("a") as handle:
                handle.write("changed\n")
            changed = self.snapshot()
            self.assertNotEqual(current, changed, str(file))
            current = changed
        (self.engine / "ignored-output").write_text("generated")
        (path / "verification.md").write_text("new evidence")
        (path / "status.md").write_text((path / "status.md").read_text() + "\nNew progress.\n")
        self.assertEqual(current, self.snapshot())

    def test_bazel_records_limits_success_failure_and_launch_failure(self):
        path = self.initialize()
        self.run_helper("bazel", self.key, "--", "test", "//fixture:test", "--jobs=100")
        evidence = (path / "verification.md").read_text()
        self.assertIn("Result: passing", evidence)
        self.assertIn("--local_test_jobs=3", evidence)
        self.assertIn("--local_resources=memory=12288", evidence)
        log = next((self.logs / self.key).glob("*.log"))
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertLess(log.read_text().index("--jobs=100"), log.read_text().index("--jobs=3"))
        result = self.run_helper("bazel", self.key, "--", "build", "//fixture:lib", env={"EXIT_CODE": "7"}, check=False)
        self.assertEqual(result.returncode, 7)
        self.assertIn("Result: failing", (path / "verification.md").read_text())
        self.mock.rename(self.root / "missing-bazel")
        result = self.run_helper("bazel", self.key, "--", "build", "//fixture:lib", check=False)
        self.assertEqual(result.returncode, 127)
        self.assertIn("Exit code: `127`", (path / "verification.md").read_text())

    def test_bazel_rejects_unsupported_commands_and_cache_overrides(self):
        self.initialize()
        for command in [["clean"], ["run", "//deploy"], ["build", "//fixture", "--disk_cache=/elsewhere"], ["test", "//fixture", "--", "arg"]]:
            result = self.run_helper("bazel", self.key, "--", *command, check=False)
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.logs.exists())

    def test_successful_build_with_source_change_invalidates_evidence(self):
        path = self.initialize()
        result = self.run_helper("bazel", self.key, "--", "build", "//fixture:lib", env={"MUTATE": "1"}, check=False)
        self.assertEqual(result.returncode, 3)
        self.assertIn("invalidated", (path / "verification.md").read_text())

    def test_bazel_runs_are_serialized(self):
        self.initialize()
        events = self.root / "events.txt"
        env = {**os.environ, "EVENTS": str(events), "DELAY": "0.3"}
        first = subprocess.Popen(self.invocation("bazel", self.key, "--", "build", "//fixture:lib"), cwd=self.engine, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        second = subprocess.Popen(self.invocation("bazel", self.key, "--", "test", "//fixture:test"), cwd=self.engine, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for process in [first, second]:
            output, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, error + output)
        self.assertEqual(events.read_text().splitlines(), ["start", "end", "start", "end"])

    def test_interruption_records_failure_and_releases_lock(self):
        path = self.initialize()
        process = subprocess.Popen(self.invocation("bazel", self.key, "--", "build", "//fixture:lib"), cwd=self.engine, env={**os.environ, "DELAY": "20"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        deadline = time.monotonic() + 5
        while not list(self.logs.glob("*/*.log")) and time.monotonic() < deadline:
            time.sleep(0.02)
        time.sleep(0.05)
        process.terminate()
        process.communicate(timeout=12)
        self.assertEqual(process.returncode, 130)
        self.assertIn("interrupted", (path / "verification.md").read_text())
        self.run_helper("bazel", self.key, "--", "build", "//fixture:lib")


class AgentConfigurationTests(unittest.TestCase):
    def test_reviewers_use_explicit_cost_settings_without_main_model_override(self):
        for name, model, effort in [("engine_correctness_reviewer", "gpt-6.1-sol", "medium"), ("engine_patterns_reviewer", "gpt-6-luna", "high")]:
            config = tomllib.loads((REPO / f"config/codex/agents/{name}.toml").read_text())
            self.assertEqual(config["name"], name)
            self.assertEqual(config["model"], model)
            self.assertEqual(config["model_reasoning_effort"], effort)
            self.assertEqual(config["service_tier"], "default")
            self.assertEqual(config["sandbox_mode"], "read-only")
            self.assertTrue(config["developer_instructions"])


if __name__ == "__main__":
    unittest.main()
