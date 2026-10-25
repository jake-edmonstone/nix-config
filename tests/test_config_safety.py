import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FISH = (ROOT / "modules/fish.nix").read_text()
LIMITS = FISH.split("interactiveShellInit = ''", 1)[1].split("set -g fish_greeting", 1)[0]


@unittest.skipUnless(shutil.which("fish"), "fish is required")
class FishTests(unittest.TestCase):
    def test_descriptor_limits(self):
        mock = """
        set -g soft $argv[1]
        set -g hard $argv[2]
        function ulimit
            switch $argv[1]
                case -Sn
                    if test (count $argv) -eq 1
                        echo $soft
                    else
                        if test "$hard" != unlimited; and test $argv[2] -gt $hard
                            exit 90
                        end
                        set -g soft $argv[2]
                    end
                case -Hn
                    echo $hard
                case '*'
                    exit 91
            end
        end
        """
        for soft, hard, expected in (
            (1024, 65536, 8192), (8192, 65536, 8192), (65536, 65536, 65536),
            (1024, 4096, 4096), (4096, 4096, 4096),
            (1024, "unlimited", 8192), ("unlimited", "unlimited", "unlimited"),
        ):
            with self.subTest(soft=soft, hard=hard):
                result = subprocess.run(
                    ["fish", "--no-config", "-c", mock + LIMITS + "\necho $soft", str(soft), str(hard)],
                    capture_output=True, text=True, timeout=10, check=True,
                )
                self.assertEqual(result.stdout.strip(), str(expected))
                self.assertEqual(result.stderr, "")

    def test_vi_initialization_uses_fish_lifecycle(self):
        self.assertIn("set -g fish_key_bindings fish_vi_key_bindings", FISH)
        self.assertNotRegex(FISH, r"(?m)^\s+fish_vi_key_bindings\s*$")
        self.assertNotRegex(FISH, r"(?m)^\s+fish_user_key_bindings\s*$")
        self.assertNotIn("ulimit", FISH.split("interactiveShellInit", 1)[0])


class WebsiteNotesTests(unittest.TestCase):
    def test_empty_courses_exit_before_any_filesystem_or_git_operations(self):
        script = (ROOT / "scripts/website-notes-update").read_text()
        # Execute only the preamble; never run compilation, cleanup or Git writes.
        preamble = script.split('tmpdir="$(mktemp -d)"', 1)[0]
        self.assertRegex(preamble, re.compile(r"COURSE_PATHS=\(\s*(?:#[^\n]*\s*)?\)"))
        result = subprocess.run(
            ["bash", "-c", preamble + "\nexit 97\n"],
            capture_output=True, text=True, timeout=10, check=True,
        )
        self.assertEqual(result.stdout.strip(), "No courses selected; nothing to update.")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
