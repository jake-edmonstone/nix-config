import argparse
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import test_engine_ticket_workflow as fixtures
from engine_ticket_evals import runner


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="engine-eval-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def baseline(self):
        return {"head": "a", "branch": "master", "index": "", "patch": "", "files": [], "untracked": {}}

    def test_workflow_rejects_missing_module_spec_or_loader(self):
        for spec in (None, mock.Mock(loader=None)):
            with self.subTest(spec=spec), mock.patch.object(
                runner.importlib.util, "spec_from_file_location", return_value=spec
            ), self.assertRaisesRegex(ImportError, "Cannot load the workflow helper"):
                runner.workflow()

    def test_grader_checks_state_not_success_claims(self):
        before = self.baseline()
        after = {**before, "patch": "changed", "files": ["source.cpp"]}
        events = [{"params": {"item": {"type": "agentMessage", "text": "Everything passed"}}}]
        self.assertEqual(runner.grade(before, after, events, ["source.cpp"])["automated_checks"], "failing")
        self.assertEqual(runner.grade(before, after, events, ["source.cpp"], allow_edits=True)["automated_checks"], "passing")
        self.assertEqual(runner.grade(before, after, events, [], allow_edits=True)["automated_checks"], "failing")
        self.assertEqual(runner.grade(before, before, events, [])["semantic_review"].split(":")[0], "unverified")

    def test_forbidden_actions_fail_even_without_git_changes(self):
        for item in [{"type": "commandExecution", "command": "git push origin master"},
                     {"type": "command_execution", "command": "git commit -m pilot"},
                     {"type": "collabAgentToolCall"}, {"type": "mcpToolCall"},
                     {"type": "fileChange", "changes": []}]:
            result = runner.grade(self.baseline(), self.baseline(), [{"params": {"item": item}}], [], reviewer=True)
            self.assertEqual(result["automated_checks"], "failing", item)

    def test_read_only_git_and_helper_commands_are_not_false_positive(self):
        for command in ["git branch --show-current", "git diff --stat", "git rev-parse HEAD",
                        "python3 workflow.py bazel EVAL-9999 -- test //fixture:test"]:
            self.assertEqual(runner.violations([{"type": "commandExecution", "command": command}]), [], command)
        self.assertTrue(runner.violations([{"type": "commandExecution", "command": "bazel test //fixture:test"}]))

    def test_budget_reservations_are_persistent_and_bounded(self):
        runner.save(self.root / "usage.json", {"reserved_turns": 0})
        for number in range(1, 13):
            self.assertEqual(runner.reserve(self.root), number)
        with self.assertRaises(ValueError):
            runner.reserve(self.root)
        self.assertEqual(json.loads((self.root / "usage.json").read_text())["reserved_turns"], 12)
        self.assertEqual((self.root / "usage.json").stat().st_mode & 0o777, 0o600)

    def test_reviewer_read_only_searches_do_not_count_as_executions(self):
        commands = [
            'bash -lc "rg --files -g AGENTS.md -g \'!bazel-*\' .; rg -n \'tests from|PASSED|FAILED|Executed\' /scratch/log"',
            "rg -n 'bazel test|git push|make' source.cpp",
            "cat /scratch/bazel-cache/log; rg '; ninja' file",
            "git diff -- make; git show HEAD:pytest",
            ["rg", "bazel test", "file"],
        ]
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(runner.violations([{"type": "commandExecution", "command": command}], reviewer=True), [])

    def test_reviewer_real_build_commands_are_still_rejected(self):
        commands = [
            "bazel test //fixture:test", "bazelisk build //fixture:bin",
            "bash -lc 'git status; /usr/bin/make all'",
            "cd /tmp && ninja", "python3 -m unittest discover",
            "env TASK=value /usr/bin/pytest tests",
            "python3 workflow.py --data-dir /tmp/data bazel EVAL-9999 -- test //fixture:test",
            ["bash", "-lc", "ctest"],
        ]
        for command in commands:
            with self.subTest(command=command):
                self.assertIn("reviewer attempted builds/tests", runner.violations([
                    {"type": "commandExecution", "command": command}], reviewer=True))

    def test_shell_wrapped_git_mutations_are_still_rejected(self):
        for command in ["bash -lc 'git -C /tmp/repo push origin master'",
                        "git branch ticket", "git switch ticket", "git add source.cpp"]:
            with self.subTest(command=command):
                self.assertTrue(runner.violations([{"type": "commandExecution", "command": command}]))

    def test_budget_symlink_is_rejected(self):
        runner.save(self.root / "usage.json", {"reserved_turns": 0})
        target = self.root / "untouched"
        target.write_text("unchanged")
        (self.root / ".usage.lock").symlink_to(target)
        with self.assertRaises(OSError):
            runner.reserve(self.root)
        self.assertEqual(target.read_text(), "unchanged")

    def test_rpc_handles_multiple_buffered_messages_and_errors(self):
        program = "import json,sys; req=json.loads(input()); print(json.dumps({'method':'notice'})+'\\n'+json.dumps({'id':req['id'],'result':{'ok':True}}),flush=True); req=json.loads(input()); print(json.dumps({'id':req['id'],'error':{'message':'failure'}}),flush=True)"
        rpc = runner.Rpc([sys.executable, "-c", program], self.root / "trace", self.root / "stderr", 3)
        received = []
        rpc.on_event = received.append
        try:
            self.assertEqual(rpc.request("first", {}), {"ok": True})
            with self.assertRaises(RuntimeError):
                rpc.request("second", {})
            self.assertEqual(len(rpc.events), 3)
            self.assertEqual(received, rpc.events)
            requests = [json.loads(line) for line in (self.root / "trace.requests.jsonl").read_text().splitlines()]
            self.assertEqual([request["method"] for request in requests], ["first", "second"])
        finally:
            rpc.close()

    def test_rpc_timeout_and_cleanup_leave_unrelated_process_alive(self):
        unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        rpc = runner.Rpc([sys.executable, "-c", "import time; time.sleep(30)"], self.root / "trace", self.root / "stderr", 0.02)
        try:
            with self.assertRaises(TimeoutError):
                rpc.receive()
            rpc.close()
            self.assertIsNotNone(rpc.process.poll())
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=3)


class PilotTests(unittest.TestCase):
    root: Path
    engine: Path
    data: Path
    key: str

    setUp = fixtures.WorkflowTests.setUp
    git = fixtures.WorkflowTests.git
    invocation = fixtures.WorkflowTests.invocation
    run_helper = fixtures.WorkflowTests.run_helper

    def test_harness_initializes_master_without_changing_git_or_default_cli(self):
        self.git("switch", "master")
        guidance = self.root / "guidance"
        guidance.mkdir()
        (guidance / "preferences.md").write_text("Approved preferences")
        (guidance / "lessons.md").write_text("Approved lessons")
        before = runner.state(self.engine)
        helper = runner.workflow()
        with mock.patch.object(runner, "workflow", return_value=helper), mock.patch.object(
                helper, "initialize", side_effect=AssertionError("Pilot must seed its own fixtures")):
            run = runner.init_pilot(self.engine, self.root / "evals", guidance)
        self.assertEqual(runner.state(self.engine), before)
        manifest = json.loads((run / "manifest.json").read_text())
        self.assertEqual(manifest["baseline"]["branch"], "master")
        self.assertEqual((Path(manifest["data_dir"]) / "preferences.md").read_text(), "Approved preferences")
        args = argparse.Namespace(ticket=runner.KEY, data_dir=Path(manifest["data_dir"]))
        path, base = helper.dossier(args, self.engine.resolve(), "master")
        self.assertEqual(base, before["head"])
        self.assertEqual(len(helper.fingerprint(args, self.engine, path, base)), 64)
        self.assertIn("Not approved", (path / "brief.md").read_text())
        self.assertIn("Not approved", (path / "plan.md").read_text())
        self.assertNotEqual(self.run_helper("init", self.key, check=False).returncode, 0)

    def test_direct_initializer_rejects_master_before_creating_records(self):
        args = argparse.Namespace(ticket=self.key, data_dir=self.data, base="origin/master")
        with self.assertRaisesRegex(ValueError, "ticket branch"):
            runner.workflow().initialize(args, self.engine, "master")
        self.assertFalse(self.data.exists())

    def test_dirty_pilot_does_not_create_eval_records(self):
        self.git("switch", "master")
        (self.engine / "source.cpp").write_text("user change")
        output = self.root / "evals"
        with self.assertRaises(ValueError):
            runner.init_pilot(self.engine, output, self.root / "guidance")
        self.assertFalse(output.exists())

    def test_unavailable_codex_records_blocked_trial_without_retry(self):
        self.git("switch", "master")
        guidance = self.root / "guidance"
        guidance.mkdir()
        for name in ["preferences.md", "lessons.md"]:
            (guidance / name).write_text("Approved guidance")
        run = runner.init_pilot(self.engine, self.root / "evals", guidance)
        prompt = self.root / "prompt.md"
        prompt.write_text("Intake only")
        args = argparse.Namespace(run_dir=run, role="coordinator", prompt=prompt,
            allow_engine_edits=False, codex=str(self.root / "missing-codex"), timeout=1)
        before = runner.state(self.engine)
        self.assertEqual(runner.live(args), 1)
        results = list(run.glob("turn-*/result.json"))
        self.assertEqual(len(results), 1)
        self.assertEqual(json.loads(results[0].read_text())["automated_checks"], "blocked")
        self.assertEqual(json.loads((run / "usage.json").read_text())["reserved_turns"], 1)
        self.assertEqual(runner.state(self.engine), before)


if __name__ == "__main__":
    unittest.main()
