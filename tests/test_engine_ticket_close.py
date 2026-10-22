import json
import os
import pty
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import NotRequired, TypedDict

ROOT = Path(__file__).resolve().parents[1]
TMUX = shutil.which("tmux")
MOCK = r'''
import json, os, subprocess, sys
from pathlib import Path
name, args = Path(sys.argv[0]).name, sys.argv[1:]
root = Path(os.environ["CLOSE_TEST_ROOT"])
worktree = root / "engine-ticket"
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, args, worktree.exists()]) + "\n")
if name == "git":
    if args[:2] == ["worktree", "remove"] and os.environ.get("FAIL_GIT_REMOVE"):
        sys.exit(1)
    os.execv(os.environ["REAL_GIT"], ["git", *args])
if os.environ.get("CLOSE_TEST_SOCKET"):
    os.execv(os.environ["REAL_TMUX"], ["tmux", "-S", os.environ["CLOSE_TEST_SOCKET"], *args])
state_path = root / "tmux.json"
state = json.loads(state_path.read_text())
command = args[0]
if command == "list-sessions":
    state["inspections"] = state.get("inspections", 0) + 1
    if state["inspections"] == 2:
        mutation = state.get("mutation")
        if mutation == "dirty": (worktree / "tracked").write_text("changed")
        if mutation == "ignored": (worktree / "new.ignored").write_text("generated")
        if mutation == "branch":
            subprocess.run([os.environ["REAL_GIT"], "-C", str(worktree), "switch", "-c", "other"], check=True, capture_output=True)
        if mutation == "session": state["sessions"][0]["id"] = "$9"
    state_path.write_text(json.dumps(state))
    if state.get("server_error"):
        print(state["server_error"], file=sys.stderr)
        sys.exit(1)
    if not state["sessions"]:
        print("no server running on fixture", file=sys.stderr)
        sys.exit(1)
    for session in state["sessions"]:
        print(session["id"] if args[-1] == "#{session_id}" else str(session.get("activity", 0)) + " " + session["id"])
elif command in ("display-message", "show-options", "list-panes"):
    session = next(s for s in state["sessions"] if s["id"] == args[args.index("-t") + 1])
    if command == "display-message": print(session["name"])
    elif command == "show-options": print(session.get("metadata", ""))
    elif args[-1] == "#{pane_current_path}": print(session.get("path", str(worktree)))
    else: print("  nvim:0  nvim  " + str(worktree))
elif command == "list-clients":
    for client in state.get("clients", []): print(client)
elif command in ("switch-client", "kill-session"):
    if state.get("fail") == command: sys.exit(1)
else:
    raise SystemExit("Unexpected tmux command: " + repr(args))
'''


class SessionState(TypedDict):
    id: str
    name: str
    metadata: NotRequired[str]
    path: NotRequired[str]
    branch: NotRequired[str]
    activity: NotRequired[int]


class TmuxState(TypedDict):
    sessions: list[SessionState]
    clients: NotRequired[list[str]]
    mutation: NotRequired[str]
    inspections: NotRequired[int]
    server_error: NotRequired[str]
    fail: NotRequired[str]


class EngineTicketCloseTests(unittest.TestCase):
    def setUp(self):
        git_bin = shutil.which("git")
        if git_bin is None:
            self.skipTest("git required for worktree fixtures")
        self.git_bin = git_bin
        temporary = tempfile.TemporaryDirectory(prefix="engine-ticket-close-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.engine = self.root / "engine"
        self.worktree = self.root / "engine-ticket"
        self.git("init", "-q", str(self.engine))
        self.git("-C", str(self.engine), "config", "user.name", "Fixture")
        self.git("-C", str(self.engine), "config", "user.email", "fixture@example.invalid")
        (self.engine / "tracked").write_text("original\n")
        (self.engine / ".gitignore").write_text("*.ignored\nexternal\n")
        self.git("-C", str(self.engine), "add", ".")
        self.git("-C", str(self.engine), "commit", "-qm", "fixture")
        self.git("-C", str(self.engine), "worktree", "add", "-qb", "CE-1/developer/ticket", str(self.worktree))
        self.script = self.root / "engine-ticket-close"
        self.script.write_text((ROOT / "scripts/engine-ticket-close").read_text()
                               .replace("engine_repo=/scratch/dev/engine", "engine_repo=" + shlex.quote(str(self.engine)), 1)
                               .replace("dev_root=/scratch/dev", "dev_root=" + shlex.quote(str(self.root)), 1))
        self.script.chmod(0o755)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        mock = self.bin / "mock"
        mock.write_text(f"#!{sys.executable}\n" + MOCK)
        mock.chmod(0o755)
        for name in ("git", "tmux"):
            (self.bin / name).symlink_to(mock)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        CLOSE_TEST_ROOT=str(self.root), REAL_GIT=self.git_bin, REAL_TMUX=TMUX or "")
        self.env.pop("TMUX", None)
        self.env.pop("TMUX_PANE", None)
        self.state: TmuxState = {"sessions": [{"id": "$1", "name": "ticket", "metadata": str(self.worktree)}]}
        self.save_state()

    def git(self, *args: str) -> str:
        return subprocess.run([self.git_bin, *args], check=True, capture_output=True, text=True, timeout=10).stdout

    def save_state(self):
        (self.root / "tmux.json").write_text(json.dumps(self.state))

    def close(self, *args: str, answer="yes", interactive=True, cwd: Path | None = None, env: dict[str, str] | None = None):
        if interactive:
            master, slave = pty.openpty()
            try:
                os.write(master, (answer + "\n").encode())
                return subprocess.run([str(self.script), *args], check=False, stdin=slave, capture_output=True,
                                      text=True, cwd=cwd or self.root, env=env or self.env, timeout=10)
            finally:
                os.close(master)
                os.close(slave)
        return subprocess.run([str(self.script), *args], check=False, input=answer + "\n", capture_output=True,
                              text=True, cwd=cwd or self.root, env=env or self.env, timeout=10)

    def events(self):
        path = self.root / "calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_untouched(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.worktree.exists())
        self.assertFalse(any(args[:2] == ["worktree", "remove"] or args[0] in ("kill-session", "switch-client")
                             for _, args, _ in self.events()))

    def test_close_keeps_branch_and_removes_worktree_before_session(self):
        result = self.close("ticket")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.worktree.exists())
        self.git("-C", str(self.engine), "show-ref", "--verify", "refs/heads/CE-1/developer/ticket")
        kills = [event for event in self.events() if event[1][0] == "kill-session"]
        self.assertEqual(kills, [["tmux", ["kill-session", "-t", "$1"], False]])

    def test_resolves_current_worktree_from_subdirectory(self):
        nested = self.worktree / "nested.ignored"
        nested.mkdir()
        result = self.close(cwd=nested)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.worktree.exists())

    def test_accepts_explicit_path(self):
        self.assertEqual(self.close(str(self.worktree)).returncode, 0)

    def test_accepts_prefixed_worktree_name(self):
        result = self.close("engine-ticket")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.worktree.exists())

    def test_preserves_support_for_slugs_starting_with_engine(self):
        target = self.root / "engine-engine-prefixed"
        self.git("-C", str(self.engine), "worktree", "add", "-qb", "prefixed", str(target))
        result = self.close("engine-prefixed")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(target.exists())
        self.assertTrue(self.worktree.exists())

    def test_ambiguous_prefixed_name_requires_explicit_path(self):
        other = self.root / "engine-engine-ticket"
        self.git("-C", str(self.engine), "worktree", "add", "-qb", "other", str(other))
        result = self.close("engine-ticket")
        self.assert_untouched(result)
        self.assertIn("ambiguous", result.stderr)
        self.assertTrue(other.exists())

    def test_preview_lists_ignored_files_and_preserves_symlink_destination(self):
        outside = self.root / "shared"
        outside.mkdir()
        (outside / "keep").write_text("shared cache")
        (self.worktree / "external").symlink_to(outside, target_is_directory=True)
        (self.worktree / "compile.ignored").write_text("generated")
        result = self.close("ticket")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("compile.ignored", result.stdout)
        self.assertIn("external", result.stdout)
        self.assertTrue((outside / "keep").exists())

    def test_cancellation_and_noninteractive_use_do_nothing(self):
        for answer, interactive in (("no", True), ("YES", True), ("yes", False)):
            with self.subTest(answer=answer, interactive=interactive):
                self.assert_untouched(self.close("ticket", answer=answer, interactive=interactive))

    def test_dirty_worktrees_are_refused(self):
        for kind in ("unstaged", "staged", "untracked"):
            with self.subTest(kind=kind):
                if kind == "untracked":
                    (self.worktree / "untracked").write_text("new")
                else:
                    (self.worktree / "tracked").write_text("modified")
                    if kind == "staged":
                        self.git("-C", str(self.worktree), "add", "tracked")
                self.assert_untouched(self.close("ticket"))
                self.git("-C", str(self.worktree), "restore", "--staged", "--worktree", "tracked")
                (self.worktree / "untracked").unlink(missing_ok=True)

    def test_rejects_main_nested_unrelated_and_symlink_targets(self):
        alias = self.root / "engine-alias"
        alias.symlink_to(self.worktree, target_is_directory=True)
        nested = self.worktree / "engine-nested"
        nested.mkdir()
        unrelated = self.root / "engine-unrelated"
        self.git("init", "-q", str(unrelated))
        for path in (self.engine, nested, unrelated, alias, self.root / "engine-missing"):
            with self.subTest(path=path):
                self.assert_untouched(self.close(str(path)))

    def test_rejects_locked_worktree(self):
        self.git("-C", str(self.engine), "worktree", "lock", str(self.worktree))
        self.assert_untouched(self.close("ticket"))

    def test_rejects_initialized_submodules(self):
        self.git("-C", str(self.worktree), "-c", "protocol.file.allow=always", "submodule", "add", str(self.engine), "sub")
        self.git("-C", str(self.worktree), "commit", "-qam", "submodule fixture")
        result = self.close("ticket")
        self.assert_untouched(result)
        self.assertIn("Initialized submodules", result.stderr)

    def test_rejects_detached_head(self):
        self.git("-C", str(self.worktree), "switch", "--detach")
        self.assert_untouched(self.close("ticket"))

    def test_no_session_is_allowed(self):
        self.state["sessions"] = []
        self.save_state()
        self.assertEqual(self.close("ticket").returncode, 0)
        self.assertFalse(self.worktree.exists())

    def test_legacy_session_requires_a_matching_pane(self):
        self.state["sessions"][0].pop("metadata")
        self.state["sessions"][0]["path"] = str(self.engine)
        self.save_state()
        self.assert_untouched(self.close("ticket"))
        self.state["sessions"][0]["path"] = str(self.worktree)
        self.save_state()
        self.assertEqual(self.close("ticket").returncode, 0)

    def test_current_branch_and_renamed_session_are_supported(self):
        self.git("-C", str(self.worktree), "switch", "-c", "CE-2/developer/other")
        self.state["sessions"][0].update(name="renamed", branch="stale-branch")
        self.save_state()
        result = self.close("ticket")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CE-2/developer/other (kept)", result.stdout)

    def test_conflicting_or_multiple_sessions_are_refused(self):
        self.state["sessions"][0]["metadata"] = str(self.engine)
        self.save_state()
        self.assert_untouched(self.close("ticket"))
        self.state["sessions"][0]["metadata"] = str(self.worktree)
        self.state["sessions"].append({"id": "$2", "name": "duplicate", "metadata": str(self.worktree)})
        self.save_state()
        self.assert_untouched(self.close("ticket"))

    def test_revalidates_before_removal(self):
        for mutation in ("dirty", "ignored", "branch", "session"):
            with self.subTest(mutation=mutation):
                (self.root / "calls").unlink(missing_ok=True)
                self.state.update(mutation=mutation, inspections=0)
                self.save_state()
                result = self.close("ticket")
                self.assert_untouched(result)
                self.git("-C", str(self.worktree), "restore", "tracked")
                (self.worktree / "new.ignored").unlink(missing_ok=True)
                self.git("-C", str(self.worktree), "switch", "CE-1/developer/ticket")
                if mutation == "branch":
                    self.git("-C", str(self.engine), "branch", "-D", "other")

    def test_git_removal_failure_keeps_session_running(self):
        result = self.close("ticket", env=dict(self.env, FAIL_GIT_REMOVE="1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.worktree.exists())
        self.assertFalse(any(args[0] in ("switch-client", "kill-session") for _, args, _ in self.events()))

    def test_switches_all_target_clients_to_most_recent_session(self):
        self.state["sessions"].extend([{"id": "$2", "name": "older", "activity": 5},
                                       {"id": "$3", "name": "recent", "activity": 10}])
        self.state["clients"] = ["client-a|$1", "client-b|$2", "client-c|$1"]
        self.save_state()
        result = self.close("ticket")
        self.assertEqual(result.returncode, 0, result.stderr)
        switches = [args for _, args, _ in self.events() if args[0] == "switch-client"]
        self.assertEqual(switches, [["switch-client", "-c", "client-a", "-t", "$3"],
                                    ["switch-client", "-c", "client-c", "-t", "$3"]])

    def test_client_switch_failure_reports_partial_cleanup_without_killing(self):
        self.state["sessions"].append({"id": "$2", "name": "other"})
        self.state.update(clients=["client-a|$1"], fail="switch-client")
        self.save_state()
        result = self.close("ticket")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.worktree.exists())
        self.assertIn("Worktree removed", result.stderr)
        self.assertFalse(any(args[0] == "kill-session" for _, args, _ in self.events()))

    def test_unexpected_tmux_error_is_not_treated_as_no_session(self):
        self.state["server_error"] = "connection refused"
        self.save_state()
        self.assert_untouched(self.close("ticket"))

    def test_session_close_failure_reports_partial_cleanup(self):
        self.state["fail"] = "kill-session"
        self.save_state()
        result = self.close("ticket")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.worktree.exists())
        self.assertIn("Worktree removed", result.stderr)
        self.git("-C", str(self.engine), "show-ref", "--verify", "refs/heads/CE-1/developer/ticket")

    def test_help_and_unknown_options(self):
        self.assertEqual(self.close("--help", interactive=False).returncode, 0)
        self.assert_untouched(self.close("--yes"))

    def test_switches_client_and_closes_only_target_on_isolated_tmux_server(self):
        tmux_bin = TMUX
        if tmux_bin is None:
            self.skipTest("tmux required for isolated server test")
        socket = str(self.root / "tmux.sock")
        command = [tmux_bin, "-S", socket]
        client_pid = None
        client_pty = None
        def tmux(*args, check=True):
            result = subprocess.run([*command, *args], check=False, capture_output=True, text=True, timeout=5)
            if check:
                self.assertEqual(result.returncode, 0, repr(args) + result.stdout + result.stderr)
            return result
        try:
            session = tmux("-f", "/dev/null", "new-session", "-d", "-P", "-F", "#{session_id}",
                           "-s", "ticket", "-c", str(self.worktree), "/bin/sh").stdout.strip()
            tmux("set-option", "-t", session, "@engine_ticket_worktree", str(self.worktree))
            keep = tmux("new-session", "-d", "-P", "-F", "#{session_id}", "-s", "keep",
                        "-c", str(self.root), "/bin/sh").stdout.strip()
            client_pid, client_pty = pty.fork()
            if client_pid == 0:
                os.execve(tmux_bin, [*command, "attach-session", "-t", session], dict(self.env, TERM="xterm-256color"))
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if tmux("list-clients", "-F", "#{session_id}").stdout.strip() == session:
                    break
                time.sleep(0.05)
            else:
                self.fail("Isolated tmux client did not attach")
            result = self.close("ticket", env=dict(self.env, CLOSE_TEST_SOCKET=socket))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(self.worktree.exists())
            self.assertEqual(tmux("list-sessions", "-F", "#{session_name}").stdout.strip(), "keep")
            self.assertEqual(tmux("list-clients", "-F", "#{session_id}").stdout.strip(), keep)
        finally:
            tmux("kill-server", check=False)
            if client_pty is not None:
                os.close(client_pty)
            if client_pid is not None:
                os.waitpid(client_pid, 0)


if __name__ == "__main__":
    unittest.main()
