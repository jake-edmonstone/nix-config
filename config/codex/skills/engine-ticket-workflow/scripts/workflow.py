#!/usr/bin/env python3

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tomllib
import uuid


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def private_dir(path, create=True):
    if path.is_symlink():
        raise ValueError(f"Private directory must not be a symlink: {path}")
    if create:
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


def private_append(path):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError(f"Private file must be regular and owned by this user: {path}")
        os.fchmod(fd, 0o600)
        return os.fdopen(fd, "a")
    except BaseException:
        os.close(fd)
        raise


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
    private_dir(args.data_dir / "tickets", create=False)
    private_dir(path, create=False)
    records = [args.data_dir / "preferences.md", args.data_dir / "lessons.md"]
    records.extend(path / name for name in ["status.md", "context.md", "brief.md", "plan.md", "baseline.patch", "verification.md"])
    for record in records:
        if record.is_symlink() or not record.is_file():
            raise ValueError(f"Missing or non-regular private record; reconcile before continuing: {record}")
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
    with private_append(path / ".record.lock") as lock:
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
    with private_append(lock_path) as lock:
        print("Waiting for the shared agent-managed Bazel lock...", flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        root, branch = engine_workspace(args)
        path, base = dossier(args, root, branch)
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
        snapshot_error = ""
        try:
            after = fingerprint(args, root, path, base)
        except (ValueError, OSError, subprocess.CalledProcessError) as error:
            after = "unavailable"
            snapshot_error = f"- Snapshot error: {error}\n"
        outcome = "interrupted" if interrupted else "passing" if result == 0 else "failing"
        if snapshot_error:
            outcome += "; invalidated: candidate snapshot unavailable"
        elif before != after:
            outcome += "; invalidated: candidate changed during execution"
        evidence = f"\n## {timestamp}\n\n- Worktree: `{root}`\n- Command: `{shlex.join(invocation)}`\n- Exit code: `{result}`\n- Result: {outcome}\n- Candidate before: `{before}`\n- Candidate after: `{after}`\n{snapshot_error}- Log: `{log_path}`\n"
        with private_append(path / "verification.md") as record:
            record.write(evidence)
        print(f"Result: {outcome} (exit {result})", flush=True)
        return 3 if result == 0 and before != after else result if result >= 0 else 128 - result


def run_review(args, root, path, base):
    reviews = private_dir(path / "reviews", create=False)
    with private_append(reviews / f".{args.stage}-{args.role}-{args.round}.lock") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return execute_review(args, root, path, base)


def execute_review(args, root, path, base):
    role_path = args.agents_dir / f"{args.role}.toml"
    with role_path.open("rb") as source:
        role = tomllib.load(source)
    if role.get("name") != args.role or role.get("service_tier") != "default":
        raise ValueError("Reviewer configuration must match the requested role and Standard service tier.")
    for key in ("model", "model_reasoning_effort", "developer_instructions"):
        if not isinstance(role.get(key), str) or not role[key].strip():
            raise ValueError(f"Reviewer configuration is missing {key}.")
    if args.round < 1 or args.timeout <= 0:
        raise ValueError("Review round and timeout must be positive.")
    reviews = private_dir(path / "reviews", create=False)
    packet = args.packet.resolve()
    if args.packet.is_symlink() or not packet.is_relative_to(reviews.resolve()) or not packet.is_file():
        raise ValueError("Review packet must be a regular file inside this ticket's private reviews directory.")
    prompt = packet.read_bytes().decode("utf-8")
    if not prompt.strip():
        raise ValueError("Review packet is empty.")
    report = reviews / f"{args.stage}-{args.role}-{args.round}.md"
    if report.exists() or report.is_symlink():
        raise ValueError("Review report already exists; preserve it and choose a new round.")
    executable = args.codex_bin or shutil.which("codex-vdi") or shutil.which("codex")
    if not executable:
        raise ValueError("Neither codex-vdi nor codex is available on PATH.")
    invocation = [str(executable)]
    if Path(executable).name != "codex-vdi":
        invocation.append("--no-daemon")
    invocation += ["exec", "--ephemeral", "--json", "--strict-config", "--cd", str(root),
                   "--model", role["model"], "--sandbox", "read-only"]
    settings = {"model_reasoning_effort": role["model_reasoning_effort"],
                "service_tier": "default", "approval_policy": "never",
                "developer_instructions": role["developer_instructions"],
                "agents.enabled": False, "features.apps": False, "web_search": "disabled"}
    for key, value in settings.items():
        invocation += ["-c", f"{key}={json.dumps(value)}"]
    invocation.append("-")
    before = fingerprint(args, root, path, base)
    attempt = private_dir(reviews / f"{args.stage}-{args.role}-{args.round}-{uuid.uuid4().hex[:8]}")
    events_path, stderr_path = attempt / "events.jsonl", attempt / "stderr.log"
    metadata = {"role": args.role, "stage": args.stage, "round": args.round,
                "model": role["model"], "effort": role["model_reasoning_effort"],
                "configured_service_tier": "default", "worktree": str(root),
                "candidate_before": before, "packet_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
                "started_at": datetime.now(timezone.utc).isoformat()}
    write_new(attempt / "settings.json", json.dumps(metadata, indent=2) + "\n")
    print(f"Starting fresh {args.role}: {role['model']}/{role['model_reasoning_effort']}, Standard", flush=True)
    print(f"Review logs: {attempt}", flush=True)
    process = None
    old_handler = signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        with private_append(events_path) as events, private_append(stderr_path) as stderr:
            process = subprocess.Popen(invocation, cwd=root, stdin=subprocess.PIPE,
                                       stdout=events, stderr=stderr, text=True, start_new_session=True)
            process.communicate(prompt, timeout=args.timeout)
        result = process.returncode
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        raise ValueError(f"Review interrupted or timed out; no report accepted. Logs: {attempt}")
    finally:
        signal.signal(signal.SIGTERM, old_handler)
    after = fingerprint(args, root, path, base)
    final_message, completed = "", False
    for line in events_path.read_text().splitlines():
        event = json.loads(line)
        if event.get("type") == "item.completed" and event.get("item", {}).get("type") == "agent_message":
            final_message = event["item"].get("text", "")
        if event.get("type") == "turn.completed":
            completed = True
        elif event.get("type") == "turn.failed":
            completed = False
    outcome = {"exit_code": result, "candidate_after": after,
               "packet_sha256_after": hashlib.sha256(packet.read_bytes()).hexdigest(),
               "completed": completed, "finished_at": datetime.now(timezone.utc).isoformat()}
    write_new(attempt / "result.json", json.dumps(outcome, indent=2) + "\n")
    if result != 0 or not completed or not final_message.strip():
        raise ValueError(f"Reviewer did not finish successfully; no report accepted. Logs: {attempt}")
    if before != after:
        raise ValueError(f"Candidate changed during review; no report accepted. Logs: {attempt}")
    if metadata["packet_sha256"] != outcome["packet_sha256_after"]:
        raise ValueError(f"Review packet changed during review; no report accepted. Logs: {attempt}")
    write_new(attempt / "report.md", final_message.rstrip() + "\n")
    os.link(attempt / "report.md", report)
    print(f"Review report: {report}", flush=True)
    return 0


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Private engine ticket records, Standard-speed reviews, and serialized Bazel verification.")
    parser.add_argument("--engine-repo", type=Path, default=Path("/scratch/dev/engine"))
    parser.add_argument("--data-dir", type=Path, default=Path.home() / ".local/share/engine-tickets")
    parser.add_argument("--log-dir", type=Path, default=Path("/scratch/dev/.cache/engine-tickets"))
    parser.add_argument("--bazel-bin", default="/usr/bin/bazel")
    parser.add_argument("--codex-bin")
    parser.add_argument("--agents-dir", type=Path, default=Path.home() / ".codex/agents")
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
    review = commands.add_parser("review")
    review.add_argument("ticket")
    review.add_argument("--role", required=True, choices=("engine_correctness_reviewer", "engine_patterns_reviewer"))
    review.add_argument("--stage", required=True, choices=("design", "code"))
    review.add_argument("--round", required=True, type=int)
    review.add_argument("--packet", required=True, type=Path)
    review.add_argument("--timeout", type=int, default=600)
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
            elif args.command == "review":
                return run_review(args, root, path, base)
            else:
                return run_bazel(args, root, path, base)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"engine-ticket-workflow: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
