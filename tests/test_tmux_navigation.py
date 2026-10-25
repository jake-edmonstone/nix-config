import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAVIGATION = (ROOT / "modules/tmux.nix").read_text().split(
    "# Smart pane switching", 1)[1].split("# Pop-ups", 1)[0]
MATCH = re.search(r'is_vim="(.*?)"\n', NAVIGATION, re.DOTALL)
assert MATCH is not None
CHECK = MATCH.group(1)


class TmuxNavigationTests(unittest.TestCase):
    def setUp(self):
        directory = Path(tempfile.mkdtemp(prefix="tmux-navigation-"))
        self.directory = directory
        self.addCleanup(subprocess.run, ["trash", str(directory)], check=True,
                        capture_output=True, timeout=10)
        ps = directory / "ps"
        ps.write_text('#!/bin/sh\nprintf "%s\\n" "$NAV_PS_OUTPUT"\n')
        ps.chmod(0o755)
        self.env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])

    def detects(self, processes):
        result = subprocess.run(["sh", "-c", CHECK.replace("#{pane_tty}", "/dev/pts/test")],
                                env=dict(self.env, NAV_PS_OUTPUT=processes),
                                capture_output=True, text=True, timeout=5, check=False)
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return result.returncode == 0

    def test_fish_with_neovim_child(self):
        self.assertTrue(self.detects("Ss+ fish\nS+ nvim"))

    def test_shell_and_other_programs_use_tmux_navigation(self):
        for processes in ("Ss+ fish", "Ss+ bash\nS+ codex", "Ss+ fish\nS+ lazygit", "S+ anvim", ""):
            with self.subTest(processes=processes):
                self.assertFalse(self.detects(processes))

    def test_supported_programs_and_wrappers(self):
        for program in ("nvim", "vim", "vimdiff", "nvimdiff", "lvim", "gvim", "view", "fzf", "ssh",
                        "mosh", ".nvim-wrapped", "/nix/store/test/bin/nvim"):
            with self.subTest(program=program):
                self.assertTrue(self.detects("Ss fish\nS+ " + program))

    def test_stopped_dead_or_zombie_editors_do_not_intercept(self):
        for state in ("T", "T+", "Ts", "X", "Z", "Z+"):
            with self.subTest(state=state):
                self.assertFalse(self.detects("Ss+ fish\n" + state + " nvim"))

    def test_running_background_editor_also_matches_documented_tty_scan(self):
        self.assertTrue(self.detects("Ss+ fish\nS nvim"))

    def test_all_navigation_bindings_execute_the_process_check(self):
        bindings = [line.strip() for line in NAVIGATION.splitlines() if "bind-key -n" in line]
        self.assertEqual(len(bindings), 5)
        for binding in bindings:
            self.assertIn('if-shell "$is_vim"', binding)
            self.assertNotIn("if-shell -F", binding)

    @unittest.skipUnless(shutil.which("tmux"), "tmux is required for the configuration parse check")
    def test_tmux_accepts_all_navigation_bindings(self):
        command = ["tmux", "-S", str(self.directory / "test.sock")]
        try:
            subprocess.run([*command, "-f", "/dev/null", "new-session", "-d", "-s", "test", "/bin/sh"],
                           check=True, capture_output=True, text=True, timeout=5)
            result = subprocess.run([*command, "source-file", "-"],
                                    input="# Smart pane switching" + NAVIGATION,
                                    capture_output=True, text=True, timeout=5, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for key in ("C-h", "C-j", "C-k", "C-l", "C-\\"):
                result = subprocess.run([*command, "list-keys", "-T", "root", key],
                                        check=True, capture_output=True, text=True, timeout=5)
                self.assertIn("ps -o state=", result.stdout)
                self.assertIn("([^[:space:]]+/)?g?[.]?", result.stdout)
                self.assertNotIn("if-shell -F", result.stdout)
        finally:
            subprocess.run([*command, "kill-server"], capture_output=True, timeout=5, check=False)


if __name__ == "__main__":
    unittest.main()
