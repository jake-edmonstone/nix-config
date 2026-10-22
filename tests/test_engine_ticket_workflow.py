import argparse
import errno
import fcntl
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
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
            "if os.environ.get('DELETE_RECORD'): Path(os.environ['DELETE_RECORD']).unlink()\n"
            "if os.environ.get('LINK_RECORD'):\n"
            "    p = Path(os.environ['LINK_RECORD']); p.unlink(); p.symlink_to(os.environ['LINK_TARGET'])\n"
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
        result = subprocess.run(self.invocation(*args), cwd=cwd or self.engine, env={**os.environ, **(env or {})}, capture_output=True, text=True, timeout=10, check=False)
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

    def test_deleted_guidance_after_build_still_records_invalidated_evidence(self):
        path = self.initialize()
        result = self.run_helper("bazel", self.key, "--", "build", "//fixture:lib", env={"DELETE_RECORD": str(self.data / "lessons.md")}, check=False)
        self.assertEqual(result.returncode, 3, result.stderr)
        evidence = (path / "verification.md").read_text()
        self.assertIn("Exit code: `0`", evidence)
        self.assertIn("invalidated", evidence)
        self.assertIn("lessons.md", evidence)

    def test_new_commit_invalidates_candidate_but_remote_base_does_not_move_it(self):
        path = self.initialize()
        base = self.git("rev-parse", "HEAD")
        original = self.snapshot()
        (self.engine / "source.cpp").write_text("int value = 2;\n")
        self.git("add", "source.cpp")
        self.git("commit", "-m", "candidate")
        self.assertNotEqual(original, self.snapshot())
        current = self.snapshot()
        self.git("update-ref", "refs/remotes/origin/master", "HEAD")
        self.run_helper("init", self.key)
        self.assertEqual(current, self.snapshot())
        self.assertIn(f"- Base commit: `{base}`", (path / "status.md").read_text())

    def test_staging_same_content_preserves_candidate_identity(self):
        self.initialize()
        (self.engine / "source.cpp").write_text("int value = 5;\n")
        before = self.snapshot()
        self.git("add", "source.cpp")
        self.assertEqual(before, self.snapshot())

    def test_same_ticket_in_another_worktree_cannot_reuse_approvals(self):
        path = self.initialize()
        original = (path / "status.md").read_bytes()
        sibling = self.root / "sibling"
        self.git("worktree", "add", "-b", "CE-1234/developer/alternative", str(sibling), "master")
        for command in ["init", "snapshot"]:
            result = self.run_helper(command, self.key, cwd=sibling, check=False)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(original, (path / "status.md").read_bytes())

    def test_private_roots_and_dossiers_reject_symlinks(self):
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        self.data.symlink_to(elsewhere, target_is_directory=True)
        self.assertNotEqual(self.run_helper("init", self.key, check=False).returncode, 0)
        self.assertEqual(list(elsewhere.iterdir()), [])
        self.data.unlink()
        path = self.initialize()
        path.rename(self.root / "saved-dossier")
        path.symlink_to(self.root / "saved-dossier", target_is_directory=True)
        result = self.run_helper("snapshot", self.key, check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_invalid_keys_and_detached_head_do_not_create_records(self):
        for key in ["../CE-1", "ce-1234", "CE-1234/elsewhere"]:
            self.assertNotEqual(self.run_helper("init", key, check=False).returncode, 0)
        self.git("switch", "--detach")
        self.assertNotEqual(self.run_helper("init", self.key, check=False).returncode, 0)
        self.assertFalse(self.data.exists())

    def test_untracked_symlink_target_and_mode_affect_candidate(self):
        self.initialize()
        source = self.engine / "untracked-link"
        source.symlink_to("source.cpp")
        initial = self.snapshot()
        source.unlink()
        source.symlink_to(".gitignore")
        self.assertNotEqual(initial, self.snapshot())
        file = self.engine / "new-tool"
        file.write_text("contents\n")
        initial = self.snapshot()
        file.chmod(0o700)
        self.assertNotEqual(initial, self.snapshot())

    def test_resume_does_not_recreate_deleted_approved_guidance(self):
        self.initialize()
        (self.data / "preferences.md").unlink()
        result = self.run_helper("init", self.key, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.data / "preferences.md").exists())

    def test_waiting_build_revalidates_branch_before_running(self):
        self.initialize()
        self.logs.mkdir()
        with (self.logs / ".bazel.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen(self.invocation("bazel", self.key, "--", "build", "//fixture:lib"), cwd=self.engine, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.addCleanup(lambda: process.kill() if process.poll() is None else None)
            assert process.stdout is not None
            self.assertIn("Waiting", process.stdout.readline())
            self.git("branch", "-m", "CE-1234/developer/other")
            fcntl.flock(lock, fcntl.LOCK_UN)
            output, error = process.communicate(timeout=5)
        self.assertNotEqual(process.returncode, 0, output + error)
        self.assertIn("different branch/worktree", error)
        self.assertFalse(list(self.logs.glob("*/*.log")))

    def test_different_worktrees_share_the_same_bazel_lock(self):
        self.initialize()
        sibling = self.root / "sibling"
        other_key = "CE-4567"
        self.git("worktree", "add", "-b", f"{other_key}/developer/sibling", str(sibling), "master")
        self.run_helper("init", other_key, cwd=sibling)
        events = self.root / "events.txt"
        env = {**os.environ, "EVENTS": str(events), "DELAY": "0.2"}
        processes = [
            subprocess.Popen(self.invocation("bazel", self.key, "--", "build", "//fixture:lib"), cwd=self.engine, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE),
            subprocess.Popen(self.invocation("bazel", other_key, "--", "test", "//fixture:test"), cwd=sibling, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE),
        ]
        for process in processes:
            output, error = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, output + error)
        self.assertEqual(events.read_text().splitlines(), ["start", "end", "start", "end"])
        for key in [self.key, other_key]:
            self.assertIn("Result: passing", (self.data / "tickets" / key / "verification.md").read_text())

    def test_master_still_rejected_by_production_cli(self):
        self.git("switch", "master")
        result = self.run_helper("init", self.key, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ticket branch", result.stderr)
        self.assertFalse(self.data.exists())

    def test_concurrent_initialization_preserves_one_complete_dossier(self):
        processes = [subprocess.Popen(self.invocation("init", self.key), cwd=self.engine,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(3)]
        for process in processes:
            out, err = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, out + err)
        self.assertEqual(len(self.snapshot()), 64)
        self.assertEqual(len(list((self.data / "tickets").iterdir())), 1)

    def test_partial_init_and_invalid_base_do_not_overwrite_existing_context(self):
        path = self.data / "tickets" / self.key
        path.mkdir(parents=True)
        (path / "context.md").write_text("User context survives\n")
        result = self.run_helper("init", self.key, "--base", "missing-ref", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((path / "status.md").exists())
        self.initialize()
        self.assertEqual((path / "context.md").read_text(), "User context survives\n")

    def test_malformed_record_refuses_resume_without_repair(self):
        path = self.initialize()
        text = (path / "status.md").read_text().replace("- Base commit:", "- Unknown field:")
        (path / "status.md").write_text(text)
        self.assertNotEqual(self.run_helper("snapshot", self.key, check=False).returncode, 0)
        self.assertNotEqual(self.run_helper("init", self.key, check=False).returncode, 0)
        self.assertEqual((path / "status.md").read_text(), text)

    def test_binary_untracked_file_with_spaces_is_fingerprinted(self):
        self.initialize()
        file = self.engine / "a binary file.dat"
        file.write_bytes(b"\x00\xff\n")
        before = self.snapshot()
        file.write_bytes(b"\x00\xfe\n")
        self.assertNotEqual(before, self.snapshot())

    def test_lock_symlinks_are_rejected_without_touching_target(self):
        target = self.root / "user-file"
        target.write_text("unchanged")
        path = self.data / "tickets" / self.key
        path.mkdir(parents=True)
        (path / ".record.lock").symlink_to(target)
        self.assertNotEqual(self.run_helper("init", self.key, check=False).returncode, 0)
        (path / ".record.lock").unlink()
        self.initialize()
        self.logs.mkdir()
        (self.logs / ".bazel.lock").symlink_to(target)
        self.assertNotEqual(self.run_helper("bazel", self.key, "--", "test", "//fixture:test", check=False).returncode, 0)
        self.assertEqual(target.read_text(), "unchanged")
        self.assertFalse(list(self.logs.glob("*/*.log")))

    def test_verification_symlink_inserted_during_build_is_not_followed(self):
        path = self.initialize()
        target = self.root / "user-file"
        target.write_text("unchanged")
        result = self.run_helper("bazel", self.key, "--", "test", "//fixture:test",
            env={"LINK_RECORD": str(path / "verification.md"), "LINK_TARGET": str(target)}, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "unchanged")
        self.assertEqual(len(list(self.logs.glob("*/*.log"))), 1)

    def test_fifo_lock_refused_instead_of_hanging(self):
        path = self.data / "tickets" / self.key
        path.mkdir(parents=True)
        os.mkfifo(path / ".record.lock")
        result = self.run_helper("init", self.key, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((path / "status.md").exists())

    def test_evidence_disk_failure_does_not_report_verification_success(self):
        path = self.initialize()
        spec = importlib.util.spec_from_file_location("helper", SCRIPT)
        assert spec is not None and spec.loader is not None
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        args = argparse.Namespace(ticket=self.key, data_dir=self.data, log_dir=self.logs,
                                  bazel_bin=str(self.mock), bazel_args=["test", "//fixture:test"])
        original = helper.private_append
        def append(file):
            if file == path / "verification.md":
                raise OSError(errno.ENOSPC, "No space left on device")
            return original(file)
        with (
            mock.patch.object(helper, "private_append", side_effect=append),
            mock.patch.object(helper, "engine_workspace", return_value=(self.engine, f"{self.key}/developer/fixture")),
            self.assertRaises(OSError),
        ):
            helper.run_bazel(args, self.engine, path, self.git("rev-parse", "HEAD"))
        self.assertEqual(len(list(self.logs.glob("*/*.log"))), 1)
        self.assertNotIn("Result: passing", (path / "verification.md").read_text())

    def prepare_review(self, role="engine_correctness_reviewer", executable="codex"):
        path = self.initialize()
        packet = path / "reviews" / "packet.md"
        packet.write_text("Review only source.cpp. Do not change files or run tests.\n")
        codex = self.root / executable
        codex.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys, time\n"
            "from pathlib import Path\n"
            "prompt = sys.stdin.read()\n"
            "Path(os.environ['CAPTURE']).write_text(json.dumps({'argv':sys.argv[1:], 'prompt':prompt}))\n"
            "time.sleep(float(os.environ.get('DELAY', '0')))\n"
            "if os.environ.get('MUTATE'): Path('source.cpp').write_text('int value = 9;\\n')\n"
            "if os.environ.get('MUTATE_PACKET'): Path(os.environ['MUTATE_PACKET']).write_text('Changed packet')\n"
            "mode = os.environ.get('MODE', 'complete')\n"
            "if mode == 'malformed': print('not JSON'); sys.exit(0)\n"
            "if mode != 'empty': print(json.dumps({'type':'item.completed', 'item':{'type':'agent_message', 'text':'No actionable findings.'}}))\n"
            "if mode == 'fail': print(json.dumps({'type':'turn.failed'})); sys.exit(1)\n"
            "if mode != 'incomplete': print(json.dumps({'type':'turn.completed'}))\n"
        )
        codex.chmod(0o700)
        invocation = [*self.invocation("review", self.key, "--role", role, "--stage", "design",
                                      "--round", "1", "--packet", str(packet))]
        invocation[2:2] = ["--codex-bin", str(codex), "--agents-dir", str(REPO / "config/codex/agents")]
        return path, packet, invocation

    def run_review_fixture(self, invocation, **env):
        return subprocess.run(invocation, cwd=self.engine, capture_output=True, text=True, timeout=8,
                              env={**os.environ, "CAPTURE": str(self.root / "launch.json"), **env}, check=False)

    def test_review_launches_both_roles_at_standard_with_independent_stdin_packets(self):
        for role, model, effort in [("engine_correctness_reviewer", "gpt-6.1-sol", "medium"),
                                   ("engine_patterns_reviewer", "gpt-6-luna", "high")]:
            with self.subTest(role=role):
                path, packet, invocation = self.prepare_review(role)
                before = self.snapshot()
                result = self.run_review_fixture(invocation)
                self.assertEqual(result.returncode, 0, result.stderr)
                capture = json.loads((self.root / "launch.json").read_text())
                argv = capture["argv"]
                self.assertEqual(argv[:2], ["--no-daemon", "exec"])
                self.assertEqual(argv[argv.index("--model") + 1], model)
                self.assertEqual(argv[argv.index("--sandbox") + 1], "read-only")
                settings = dict(arg.split("=", 1) for i, arg in enumerate(argv) if i and argv[i - 1] == "-c")
                self.assertEqual(json.loads(settings["model_reasoning_effort"]), effort)
                self.assertEqual(json.loads(settings["service_tier"]), "default")
                self.assertEqual(json.loads(settings["approval_policy"]), "never")
                self.assertFalse(json.loads(settings["agents.enabled"]))
                self.assertFalse(json.loads(settings["features.apps"]))
                self.assertIn("Review the assigned engine ticket", json.loads(settings["developer_instructions"]))
                self.assertEqual(capture["prompt"], packet.read_text())
                self.assertEqual(argv[-1], "-")
                self.assertIn("--ephemeral", argv)
                self.assertNotIn("resume", argv)
                self.assertNotIn("fork", argv)
                self.assertNotIn("agent_type", argv)
                report = path / "reviews" / f"design-{role}-1.md"
                self.assertEqual(report.read_text(), "No actionable findings.\n")
                self.assertEqual(report.stat().st_mode & 0o777, 0o600)
                self.assertEqual(self.snapshot(), before)

    def test_review_uses_vdi_wrapper_without_duplicate_no_daemon_flag(self):
        _, _, invocation = self.prepare_review(executable="codex-vdi")
        result = self.run_review_fixture(invocation)
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = json.loads((self.root / "launch.json").read_text())["argv"]
        self.assertEqual(argv[0], "exec")
        self.assertNotIn("--no-daemon", argv)

    def test_review_automatically_selects_installed_vdi_wrapper(self):
        _, _, invocation = self.prepare_review(executable="codex-vdi")
        index = invocation.index("--codex-bin")
        del invocation[index:index + 2]
        result = self.run_review_fixture(invocation, PATH=f"{self.root}:/usr/bin:/bin")
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = json.loads((self.root / "launch.json").read_text())["argv"]
        self.assertEqual(argv[0], "exec")
        self.assertNotIn("--no-daemon", argv)

    def test_review_automatically_falls_back_to_bare_codex(self):
        _, _, invocation = self.prepare_review()
        index = invocation.index("--codex-bin")
        del invocation[index:index + 2]
        result = self.run_review_fixture(invocation, PATH=f"{self.root}:/usr/bin:/bin")
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = json.loads((self.root / "launch.json").read_text())["argv"]
        self.assertEqual(argv[:2], ["--no-daemon", "exec"])

    def test_failed_or_incomplete_review_never_creates_accepted_report(self):
        path, _, invocation = self.prepare_review()
        for mode in ["fail", "incomplete", "empty", "malformed"]:
            with self.subTest(mode=mode):
                result = self.run_review_fixture(invocation, MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((path / "reviews" / "design-engine_correctness_reviewer-1.md").exists())

    def test_review_refuses_to_overwrite_a_report_before_starting_codex(self):
        path, _, invocation = self.prepare_review()
        report = path / "reviews" / "design-engine_correctness_reviewer-1.md"
        report.write_text("Existing human review\n")
        result = self.run_review_fixture(invocation)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "launch.json").exists())
        self.assertEqual(report.read_text(), "Existing human review\n")

    def test_candidate_change_invalidates_review(self):
        path, _, invocation = self.prepare_review()
        result = self.run_review_fixture(invocation, MUTATE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Candidate changed", result.stderr)
        self.assertFalse((path / "reviews" / "design-engine_correctness_reviewer-1.md").exists())

    def test_packet_change_invalidates_review(self):
        path, packet, invocation = self.prepare_review()
        result = self.run_review_fixture(invocation, MUTATE_PACKET=str(packet))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Review packet changed", result.stderr)
        self.assertFalse((path / "reviews" / "design-engine_correctness_reviewer-1.md").exists())

    def test_unchanged_crlf_packet_is_accepted(self):
        _, packet, invocation = self.prepare_review()
        packet.write_bytes(b"Read only source.cpp.\r\nDo not write files.\r\n")
        result = self.run_review_fixture(invocation)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_packet_outside_private_reviews_is_refused_before_launch(self):
        _, packet, invocation = self.prepare_review()
        outside = self.root / "packet.md"
        outside.write_text(packet.read_text())
        invocation[-1] = str(outside)
        result = self.run_review_fixture(invocation)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "launch.json").exists())

    def test_packet_symlink_is_refused_before_launch(self):
        _, packet, invocation = self.prepare_review()
        target = packet.with_name("source-packet.md")
        packet.rename(target)
        packet.symlink_to(target)
        result = self.run_review_fixture(invocation)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "launch.json").exists())

    def test_priority_role_configuration_is_refused_before_launch(self):
        _, _, invocation = self.prepare_review()
        agents = self.root / "agents"
        agents.mkdir()
        source = REPO / "config/codex/agents/engine_correctness_reviewer.toml"
        (agents / source.name).write_text(source.read_text().replace('service_tier = "default"', 'service_tier = "priority"'))
        invocation[invocation.index("--agents-dir") + 1] = str(agents)
        result = self.run_review_fixture(invocation)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Standard", result.stderr)
        self.assertFalse((self.root / "launch.json").exists())

    def test_review_timeout_preserves_logs_without_accepting_a_report(self):
        path, _, invocation = self.prepare_review()
        result = self.run_review_fixture([*invocation, "--timeout", "1"], DELAY="4")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("timed out", result.stderr)
        self.assertEqual(len(list((path / "reviews").glob("*/events.jsonl"))), 1)
        self.assertFalse((path / "reviews" / "design-engine_correctness_reviewer-1.md").exists())

    def test_same_review_round_cannot_launch_twice_concurrently(self):
        _, _, invocation = self.prepare_review()
        env = {**os.environ, "CAPTURE": str(self.root / "launch.json"), "DELAY": "0.5"}
        first = subprocess.Popen(invocation, cwd=self.engine, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not (self.root / "launch.json").exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            second = self.run_review_fixture(invocation)
            self.assertNotEqual(second.returncode, 0)
            out, err = first.communicate(timeout=5)
            self.assertEqual(first.returncode, 0, out + err)
        finally:
            if first.poll() is None:
                first.kill()
                first.communicate()


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
