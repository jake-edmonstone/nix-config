#!/usr/bin/env python3

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import uuid


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def private_dir(path):
    if path.is_symlink():
        raise ValueError(f"Private directory must not be a symlink: {path}")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.stat().st_uid != os.getuid():
        raise ValueError(f"Private directory belongs to another user: {path}")
    path.chmod(0o700)
    return path


def write_new(path, text):
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Record must be a regular private file: {path}")
        return
    with os.fdopen(fd, "w", errors="surrogateescape") as handle:
        handle.write(text)


def engine_workspace(args):
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode().strip())
    actual = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").decode().strip()).resolve()
    expected = Path(git(args.engine_repo, "rev-parse", "--path-format=absolute", "--git-common-dir").decode().strip()).resolve()
    if actual != expected:
        raise ValueError("This checkout is not a worktree of the configured engine repository.")
    branch = git(root, "branch", "--show-current").decode().strip()
    if not branch:
        raise ValueError("Use an existing ticket branch, not a detached HEAD.")
    return root.resolve(), branch


def ticket_dir(args):
    if not re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", args.ticket):
        raise ValueError("Invalid Jira key.")
    private_dir(args.data_dir)
    return args.data_dir / "tickets" / args.ticket


def field(text, name):
    match = re.search(rf"^- {re.escape(name)}: `(.*)`$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing {name} in status.md; reconcile the dossier before continuing.")
    return match.group(1)


def dossier(args, root, branch):
    path = ticket_dir(args)
    status = (path / "status.md").read_text()
    if Path(field(status, "Worktree")).resolve() != root or field(status, "Branch") != branch:
        raise ValueError("Ticket records belong to a different branch/worktree; reconcile with the user.")
    base = field(status, "Base commit")
    git(root, "cat-file", "-e", f"{base}^{{commit}}")
    return path, base


def fingerprint(args, root, path, base):
    digest = hashlib.sha256()

    def add(label, value):
        digest.update(label.encode() + b"\0" + len(value).to_bytes(8, "big") + value)

    add("base", base.encode())
    add("head", git(root, "rev-parse", "HEAD"))
    add("branch", git(root, "branch", "--show-current"))
    add("tracked", git(root, "diff", "HEAD", "--binary", "--no-ext-diff", "--no-textconv"))
    for raw in sorted(git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")):
        if not raw:
            continue
        relative = os.fsdecode(raw)
        source = root / relative
        content = hashlib.sha256()
        if source.is_symlink():
            content.update(os.fsencode(os.readlink(source)))
        else:
            with source.open("rb") as handle:
                for block in iter(lambda: handle.read(1024 * 1024), b""):
                    content.update(block)
        add("untracked:" + relative, str(source.lstat().st_mode).encode() + content.digest())
    for record in [args.data_dir / "preferences.md", args.data_dir / "lessons.md", path / "context.md", path / "brief.md", path / "plan.md"]:
        add(str(record), record.read_bytes())
    return digest.hexdigest()


def initialize(args, root, branch):
    if branch.split("/")[0] != args.ticket:
        raise ValueError("Jira key does not match the current ticket branch.")
    path = ticket_dir(args)
    private_dir(args.data_dir / "tickets")
    private_dir(path)
    with (path / ".record.lock").open("a") as lock:
        (path / ".record.lock").chmod(0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if (path / "status.md").exists():
            dossier(args, root, branch)
            print(f"Existing dossier preserved: {path}")
            return
        base = git(root, "merge-base", "HEAD", args.base).decode().strip()
        head = git(root, "rev-parse", "HEAD").decode().strip()
        write_new(args.data_dir / "preferences.md", "# Approved preferences\n\nAdd your approved engine working preferences here. Direct user edits are approved.\n")
        write_new(args.data_dir / "lessons.md", "# Approved lessons\n\nAdd approved lessons with their scope, source, and concrete review check.\n")
        write_new(args.data_dir / "pending-lessons.md", "# Pending lessons\n\nAgent-proposed lessons stay here until explicitly approved by the user.\n")
        private_dir(path / "reviews")
        records = {
            "context.md": "# Source context\n\nNo context supplied yet. Keep original sources and identify recollections and assumptions.\n",
            "brief.md": "# Ticket brief\n\nNot approved. Record requirements, acceptance criteria, non-goals, and open questions.\n",
            "plan.md": "# Implementation plan\n\nNot approved. Record reuse candidates, minimal changes, and verification.\n",
            "verification.md": "# Verification\n\nNo checks run yet.\n",
            "pr-draft.md": "# PR draft\n\nNot ready.\n",
        }
        for name, text in records.items():
            write_new(path / name, text)
        write_new(path / "baseline.patch", git(root, "diff", "HEAD", "--binary", "--no-ext-diff", "--no-textconv").decode(errors="surrogateescape"))
        untracked = [os.fsdecode(item) for item in git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if item]
        listing = "\n".join(f"- `{name}`" for name in untracked) or "None."
        write_new(path / "status.md", f"# Ticket status\n\n- Ticket: `{args.ticket}`\n- Worktree: `{root}`\n- Branch: `{branch}`\n- Base commit: `{base}`\n- Starting HEAD: `{head}`\n- Stage: intake; awaiting brief approval\n\n## Initial untracked files\n\n{listing}\n\n## Approvals and decisions\n\nNone. Record explicit user approvals, scope, dates, and applicable fingerprints.\n\n## Review rounds\n\nDesign: 0 unsuccessful rounds. Code: 0 unsuccessful rounds.\n")
        print(f"Dossier created: {path}")
        print(f"Candidate: {fingerprint(args, root, path, base)}")


def run_bazel(args, root, path, base):
    command = args.bazel_args
    if command[:1] == ["--"]:
        command = command[1:]
    if not command or command[0] not in {"build", "test", "cquery", "aquery"}:
        raise ValueError("Only build, test, cquery, and aquery are supported; no run/clean/deployment.")
    forbidden = ("--disk_cache", "--remote_cache", "--remote_executor", "--output_user_root", "--output_base", "--local_cpu_resources", "--local_ram_resources")
    if any(arg == "--" or any(arg == flag or arg.startswith(flag + "=") for flag in forbidden) for arg in command[1:]):
        raise ValueError("Do not override cache/execution roots or legacy resource limits through this helper.")
    limits = ["--jobs=3", "--local_resources=cpu=3", "--local_resources=memory=12288"]
    if command[0] == "test":
        limits.append("--local_test_jobs=3")
    invocation = [args.bazel_bin, *command, *limits]
    private_dir(args.log_dir)
    lock_path = args.log_dir / ".bazel.lock"
    with lock_path.open("a") as lock:
        lock_path.chmod(0o600)
        print("Waiting for the shared agent-managed Bazel lock...", flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        before = fingerprint(args, root, path, base)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        logs = private_dir(args.log_dir / args.ticket)
        log_path = logs / f"{timestamp}-{uuid.uuid4().hex[:8]}.log"
        print(f"Command: {shlex.join(invocation)}\nLog: {log_path}\nCandidate: {before}", flush=True)
        process = None
        interrupted = False
        old_handler = signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
        try:
            fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as log:
                try:
                    process = subprocess.Popen(invocation, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                    result = process.wait()
                except OSError as error:
                    log.write(str(error) + "\n")
                    result = 127
                except KeyboardInterrupt:
                    interrupted = True
                    if process is not None and process.poll() is None:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                    result = 130
        finally:
            signal.signal(signal.SIGTERM, old_handler)
        after = fingerprint(args, root, path, base)
        outcome = "interrupted" if interrupted else "passing" if result == 0 else "failing"
        if before != after:
            outcome += "; invalidated: candidate changed during execution"
        evidence = f"\n## {timestamp}\n\n- Worktree: `{root}`\n- Command: `{shlex.join(invocation)}`\n- Exit code: `{result}`\n- Result: {outcome}\n- Candidate before: `{before}`\n- Candidate after: `{after}`\n- Log: `{log_path}`\n"
        with (path / "verification.md").open("a") as record:
            record.write(evidence)
        print(f"Result: {outcome} (exit {result})", flush=True)
        return 3 if result == 0 and before != after else result if result >= 0 else 128 - result


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Private engine ticket records and serialized Bazel verification.")
    parser.add_argument("--engine-repo", type=Path, default=Path("/scratch/dev/engine"))
    parser.add_argument("--data-dir", type=Path, default=Path.home() / ".local/share/engine-tickets")
    parser.add_argument("--log-dir", type=Path, default=Path("/scratch/dev/.cache/engine-tickets"))
    parser.add_argument("--bazel-bin", default="/usr/bin/bazel")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("identify")
    init = commands.add_parser("init")
    init.add_argument("ticket")
    init.add_argument("--base", default="origin/master")
    snapshot = commands.add_parser("snapshot")
    snapshot.add_argument("ticket")
    bazel = commands.add_parser("bazel")
    bazel.add_argument("ticket")
    bazel.add_argument("bazel_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        root, branch = engine_workspace(args)
        if args.command == "identify":
            print(root)
        elif args.command == "init":
            initialize(args, root, branch)
        else:
            path, base = dossier(args, root, branch)
            if args.command == "snapshot":
                print(fingerprint(args, root, path, base))
            else:
                return run_bazel(args, root, path, base)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"engine-ticket-workflow: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
