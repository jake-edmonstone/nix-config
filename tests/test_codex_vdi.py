import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "scripts/gts/codex-vdi"
PROXY_VARIABLES = (
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy",
)


class CodexVdiTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="codex-vdi-test-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.calls = self.path / "calls.jsonl"
        mock = self.path / "mock-command"
        mock.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "name = Path(sys.argv[0]).name\n"
            f"variables = {PROXY_VARIABLES!r}\n"
            "with open(os.environ['MOCK_CALLS'], 'a') as log:\n"
            "    log.write(json.dumps({'command': name, 'args': sys.argv[1:], "
            "'env': {key: os.environ.get(key) for key in variables}}) + '\\n')\n"
            "sys.exit(int(os.environ.get('MOCK_' + name.upper() + '_EXIT', '0')))\n"
        )
        mock.chmod(0o700)
        for command in ("systemctl", "curl", "codex"):
            (self.path / command).symlink_to(mock)
        self.env = {
            key: value
            for key, value in os.environ.items()
            if key not in PROXY_VARIABLES
        }
        self.env["PATH"] = str(self.path) + os.pathsep + self.env["PATH"]
        self.env["MOCK_CALLS"] = str(self.calls)

    def run_launcher(self, *args, **env):
        return subprocess.run(
            ["bash", str(LAUNCHER), *args],
            env=self.env | env,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )

    def read_calls(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_help_and_version_do_not_need_a_tunnel(self):
        for argument in ("--help", "-h", "help", "--version", "-V"):
            with self.subTest(argument=argument):
                if self.calls.exists():
                    self.calls.unlink()
                result = self.run_launcher(argument)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.read_calls()
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0]["command"], "codex")
                self.assertEqual(calls[0]["args"], [argument])
                self.assertTrue(
                    all(value is None for value in calls[0]["env"].values())
                )

    def test_starts_service_before_checking_and_launching(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.read_calls()
        self.assertEqual(
            [call["command"] for call in calls], ["systemctl", "curl", "codex"]
        )
        self.assertEqual(
            calls[0]["args"], ["--user", "start", "codex-vdi-proxy.service"]
        )
        self.assertTrue(all(value is None for value in calls[0]["env"].values()))

    def test_service_failure_stops_before_network_or_codex(self):
        result = self.run_launcher(MOCK_SYSTEMCTL_EXIT="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual([call["command"] for call in self.read_calls()], ["systemctl"])
        self.assertIn("journalctl --user", result.stderr)

    def test_network_failure_stops_before_codex(self):
        result = self.run_launcher(MOCK_CURL_EXIT="7")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            [call["command"] for call in self.read_calls()], ["systemctl", "curl"]
        )
        self.assertIn("SSH tunnel in your Windows VDI terminal", result.stderr)

    def test_tls_failure_does_not_fall_back_to_direct_access(self):
        result = self.run_launcher(MOCK_CURL_EXIT="60")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("codex", [call["command"] for call in self.read_calls()])

    def test_probe_uses_proxy_but_keeps_tls_checks_and_accepts_http_challenge(self):
        self.assertEqual(self.run_launcher().returncode, 0)
        arguments = self.read_calls()[1]["args"]
        self.assertEqual(
            arguments[arguments.index("--proxy") + 1], "http://127.0.0.1:18181"
        )
        self.assertEqual(arguments[arguments.index("--noproxy") + 1], "")
        self.assertEqual(arguments[-1], "https://chatgpt.com/")
        for forbidden in ("--fail", "--insecure", "-k"):
            self.assertNotIn(forbidden, arguments)
        self.assertIn("--retry-connrefused", arguments)

    def test_sets_uppercase_and_lowercase_proxy_variables(self):
        self.assertEqual(self.run_launcher().returncode, 0)
        env = self.read_calls()[-1]["env"]
        for key in PROXY_VARIABLES:
            if key.upper() != "NO_PROXY":
                self.assertEqual(env[key], "http://127.0.0.1:18181")
        self.assertEqual(env["NO_PROXY"], env["no_proxy"])
        self.assertIn(".striketechnologies.com", env["NO_PROXY"].split(","))

    def test_preserves_existing_bypass_entries(self):
        result = self.run_launcher(
            NO_PROXY="internal.example", no_proxy="another.example"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        bypass = self.read_calls()[-1]["env"]["NO_PROXY"].split(",")
        self.assertIn("internal.example", bypass)
        self.assertIn("another.example", bypass)

    def test_rejects_global_bypass_before_starting_service(self):
        for value in ("*", "localhost,*,example.com"):
            with self.subTest(value=value):
                result = self.run_launcher(NO_PROXY=value)
                self.assertEqual(result.returncode, 1)
                self.assertIn('NO_PROXY contains "*"', result.stderr)
                self.assertEqual(self.read_calls(), [])

    def test_uses_private_app_server_and_proxy_exclusions(self):
        self.assertEqual(self.run_launcher().returncode, 0)
        arguments = self.read_calls()[-1]["args"]
        self.assertEqual(arguments[0], "--no-daemon")
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"):
            self.assertIn(
                f'shell_environment_policy.filters.{key}="exclude"', arguments
            )

    def test_preserves_resume_arguments_and_quoting(self):
        args = (
            "resume",
            "a-session-id",
            "a prompt with spaces",
            "--model",
            "gpt-6.1-sol",
        )
        result = self.run_launcher(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_calls()[-1]["args"][-len(args) :], list(args))

    def test_preserves_codex_exit_code(self):
        self.assertEqual(self.run_launcher(MOCK_CODEX_EXIT="23").returncode, 23)

    def test_does_not_modify_callers_environment(self):
        before = dict(os.environ)
        self.assertEqual(self.run_launcher().returncode, 0)
        self.assertEqual(dict(os.environ), before)

    def test_shell_syntax(self):
        result = subprocess.run(
            ["bash", "-n", str(LAUNCHER)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
