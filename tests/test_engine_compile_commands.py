import ast
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/engine-compile-commands"
ENTRY = {"file": "source.cpp", "directory": "/engine", "arguments": ["gcc", "-c", "source.cpp"]}


class EngineCompileCommandsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="engine-compile-commands-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.engine = self.path / "engine with spaces"
        self.worktree = self.path / "engine ticket"
        self.engine.mkdir()
        self.git("init", "--quiet", str(self.engine))
        (self.engine / ".gitignore").write_text("/compile_commands.json\n")
        self.git("-C", str(self.engine), "add", ".gitignore")
        self.git("-C", str(self.engine), "-c", "user.name=Test", "-c", "user.email=test@example.com",
                 "commit", "--quiet", "--allow-empty", "-m", "fixture")
        self.git("-C", str(self.engine), "worktree", "add", "--quiet", "-b", "ticket", str(self.worktree))
        self.script = self.path / "engine-compile-commands"
        self.script.write_text(SCRIPT.read_text().replace(
            'ENGINE_REPO = Path("/scratch/dev/engine")', f"ENGINE_REPO = Path({str(self.engine)!r})", 1))
        self.bin = self.path / "bin"
        self.bin.mkdir()
        bazel = self.bin / "bazel"
        bazel.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['CALLS']).write_text(json.dumps({'cwd': os.getcwd(), 'args': sys.argv[1:]}))\n"
            "if not os.environ.get('NO_DATABASE'):\n"
            "    pathlib.Path('compile_commands.json').write_text(os.environ['DATABASE'])\n"
            "sys.exit(int(os.environ.get('BAZEL_EXIT', '0')))\n"
        )
        bazel.chmod(0o755)
        self.calls = self.path / "calls.json"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        CALLS=str(self.calls), DATABASE=json.dumps([ENTRY]))

    def git(self, *args):
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.PIPE).strip()

    def run_helper(self, *args, cwd=None, **env):
        return subprocess.run([sys.executable, str(self.script), *args], cwd=cwd or self.worktree,
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=10)

    def test_targets_flags_and_subdirectory(self):
        subdir = self.worktree / "core" / "some directory"
        subdir.mkdir(parents=True)
        result = self.run_helper("//core:one", "//core:two", "--", "--config=debug",
                                 "--define=value with spaces", cwd=subdir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.calls.read_text()), {
            "cwd": str(self.worktree),
            "args": ["run", "//.engine-local-compile-commands:refresh", "--",
                     "--config=debug", "--define=value with spaces"],
        })
        build = (self.worktree / ".engine-local-compile-commands/BUILD.bazel").read_text()
        self.assertIn('targets = ["//core:one", "//core:two"]', build)
        self.assertIn('data = ["@compile_commands//:print_args"]', build)
        self.assertIn('main = "refresh.check_python_version.py"', build)
        self.assertIn('imports = [""]', build)
        rule = (self.worktree / ".engine-local-compile-commands/refresh.bzl").read_text()
        self.assertIn('default = "@compile_commands//:print_args"', rule)
        self.assertIn('default = "@compile_commands//:refresh.template.py"', rule)
        self.assertNotIn("@hedron_compile_commands", build + rule)
        self.assertNotIn("refresh_all", build)
        self.assertEqual(self.git("-C", str(self.worktree), "status", "--porcelain"), "")

    def test_main_checkout_and_repeated_use(self):
        for _ in range(2):
            result = self.run_helper("//core:one", cwd=self.engine)
            self.assertEqual(result.returncode, 0, result.stderr)
        exclude = (self.engine / ".git/info/exclude").read_text()
        self.assertEqual(exclude.count("/.engine-local-compile-commands/"), 1)

    def test_invalid_arguments_do_not_invoke_bazel(self):
        for args in ((), ("core:one",), ("--config=debug",), ("--", "--config=debug")):
            with self.subTest(args=args):
                result = self.run_helper(*args)
                self.assertEqual(result.returncode, 2)
        self.assertFalse(self.calls.exists())

    def test_help_does_not_require_checkout(self):
        result = self.run_helper("--help", cwd=self.path)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)
        self.assertFalse(self.calls.exists())

    def test_unrelated_checkout_is_rejected(self):
        other = self.path / "unrelated"
        other.mkdir()
        self.git("init", "--quiet", str(other))
        result = self.run_helper("//core:one", cwd=other)
        self.assertEqual(result.returncode, 1)
        self.assertIn("engine checkout", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse((other / ".engine-local-compile-commands").exists())

    def test_unmanaged_package_is_preserved(self):
        package = self.worktree / ".engine-local-compile-commands"
        package.mkdir()
        build = package / "BUILD.bazel"
        build.write_text("user content")
        result = self.run_helper("//core:one")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(build.read_text(), "user content")
        self.assertFalse(self.calls.exists())

    def test_tracked_package_is_preserved(self):
        package = self.worktree / ".engine-local-compile-commands"
        package.mkdir()
        (package / ".owner").write_text("engine-compile-commands-v1\n")
        self.git("-C", str(self.worktree), "add", str(package))
        result = self.run_helper("//core:one")
        self.assertEqual(result.returncode, 1)
        self.assertIn("tracked files", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_database_restored_on_failure_or_invalid_output(self):
        database = self.worktree / "compile_commands.json"
        original = json.dumps([dict(ENTRY, file="original.cpp")])
        for env in ({"BAZEL_EXIT": "1"}, {"NO_DATABASE": "1"}, {"DATABASE": "[]"}, {"DATABASE": "[broken"},
                    {"DATABASE": "[{}]"}, {"DATABASE": json.dumps([ENTRY]) + "junk"}):
            with self.subTest(env=env):
                database.write_text(original)
                result = self.run_helper("//core:one", **env)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(database.read_text(), original)
                self.assertFalse(list((self.worktree / ".engine-local-compile-commands").glob("previous-*")))

    def test_failed_first_refresh_does_not_leave_database(self):
        result = self.run_helper("//core:one", BAZEL_EXIT="1")
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.worktree / "compile_commands.json").exists())

    def test_symlink_database_is_preserved(self):
        original = self.path / "original.json"
        original.write_text(json.dumps([ENTRY]))
        database = self.worktree / "compile_commands.json"
        database.symlink_to(original)
        result = self.run_helper("//core:one")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(database.is_symlink())
        self.assertEqual(original.read_text(), json.dumps([ENTRY]))
        self.assertFalse(self.calls.exists())

    def test_validation_streams_large_database(self):
        loader = importlib.machinery.SourceFileLoader("engine_compile_commands", str(SCRIPT))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        database = self.path / "large.json"
        database.write_text(json.dumps([dict(ENTRY, file="x" * 100000), ENTRY]))
        module.validate_database(database)
        for value in ("[]", "[", "{}", "[1]", json.dumps([ENTRY])[:-1] + ",]", "[{}]"):
            with self.subTest(value=value):
                database.write_text(value)
                with self.assertRaises(ValueError):
                    module.validate_database(database)

    def test_restore_failure_keeps_original_backup(self):
        loader = importlib.machinery.SourceFileLoader("engine_compile_commands_restore", str(self.script))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        database = self.worktree / "compile_commands.json"
        original = json.dumps([ENTRY])
        database.write_text(original)
        replace = os.replace

        def replace_except_restore(source, destination):
            if Path(source).name.startswith("previous-"):
                raise OSError("restore fixture failure")
            replace(source, destination)

        common = str(self.engine / ".git")
        with patch.object(module, "git", side_effect=[str(self.worktree), common, common, ""]), \
                patch.object(module.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "bazel")), \
                patch.object(module.os, "replace", side_effect=replace_except_restore):
            with self.assertRaisesRegex(OSError, "preserved at"):
                module.refresh(["//core:one"], [])
        backups = list((self.worktree / ".engine-local-compile-commands").glob("previous-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)

    def test_private_rule_uses_aliased_dependencies_and_expands_template(self):
        result = self.run_helper("//core:one", "//core:two")
        self.assertEqual(result.returncode, 0, result.stderr)
        package = self.worktree / ".engine-local-compile-commands"
        rules = []
        expansions = []
        attrs = SimpleNamespace(string_list=lambda **kwargs: kwargs, output=lambda **kwargs: kwargs,
                                label=lambda **kwargs: kwargs)
        namespace = {
            "load": lambda *args: None,
            "attr": attrs,
            "rule": lambda **kwargs: rules.append(kwargs),
            "find_cpp_toolchain": lambda ctx: SimpleNamespace(built_in_include_directories=["/compiler/include"]),
            "DefaultInfo": lambda **kwargs: kwargs,
            "depset": lambda values: values,
        }
        exec((package / "refresh.bzl").read_text(), namespace)
        rule = rules[0]
        self.assertEqual(rule["attrs"]["_template"]["default"], "@compile_commands//:refresh.template.py")
        self.assertEqual(rule["attrs"]["_print_args"]["default"], "@compile_commands//:print_args")
        context = SimpleNamespace(
            actions=SimpleNamespace(expand_template=lambda **kwargs: expansions.append(kwargs)),
            outputs=SimpleNamespace(out="refresh.py", launcher="refresh.check_python_version.py"),
            file=SimpleNamespace(_template="upstream.template.py", _launcher_template="version.template.py"),
            attr=SimpleNamespace(targets=["//core:one", "//core:two"]),
            executable=SimpleNamespace(_print_args=SimpleNamespace(path="external/hedron_compile_commands+/print_args")),
        )
        rule["implementation"](context)
        expansion = expansions[0]
        self.assertEqual(expansion["template"], "upstream.template.py")
        substitutions = expansion["substitutions"]
        self.assertEqual(substitutions["{exclude_headers}"], '\'\'')
        self.assertEqual(substitutions["{exclude_external_sources}"], "False")
        pairs = ast.literal_eval("[\n" + substitutions["        {target_flag_pairs}"] + "\n]")
        self.assertEqual(pairs, [("//core:one", ""), ("//core:two", "")])
        self.assertEqual(substitutions["{print_args_executable}"], "'external/hedron_compile_commands+/print_args'")
        self.assertEqual(rule["attrs"]["_launcher_template"]["default"],
                         "@compile_commands//:check_python_version.template.py")
        self.assertEqual(len(expansions), 2)
        launcher = expansions[1]
        self.assertEqual(launcher["output"], "refresh.check_python_version.py")
        self.assertEqual(launcher["template"], "version.template.py")
        self.assertEqual(launcher["substitutions"], {"{to_run}": "refresh"})
        (package / "refresh.py").write_text(
            "import json\nfrom pathlib import Path\n"
            f"def main():\n    Path('entrypoint.json').write_text(json.dumps({[ENTRY]!r}))\n"
        )
        launcher_source = "import {to_run}\n{to_run}.main()\n"
        for placeholder, value in launcher["substitutions"].items():
            launcher_source = launcher_source.replace(placeholder, value)
        entrypoint = package / launcher["output"]
        entrypoint.write_text(launcher_source)
        executed = subprocess.run([sys.executable, str(entrypoint)], cwd=self.path,
                                  capture_output=True, text=True, timeout=10)
        self.assertEqual(executed.returncode, 0, executed.stderr)
        self.assertEqual(json.loads((self.path / "entrypoint.json").read_text()), [ENTRY])


if __name__ == "__main__":
    unittest.main()
