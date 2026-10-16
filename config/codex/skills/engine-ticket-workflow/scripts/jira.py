#!/usr/bin/env python3

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit
import uuid

sys.dont_write_bytecode = True
from workflow import private_append, private_dir


ENDPOINT = "https://chatgpt.com/backend-api/ps/mcp"
PROXY = "http://127.0.0.1:18181"
SITE = "https://gtsjira.atlassian.net"
STATUS_MARKER = "\nJIRA_HTTP_STATUS:"
TOOLS = {
    "atlassian.getAccessibleAtlassianResources",
    "atlassian.getJiraIssue",
    "atlassian.searchJiraIssuesUsingJql",
    "atlassian.executeRead",
}


class JiraError(Exception):
    pass


class MissingReply(JiraError):
    pass


class TransientReadError(JiraError):
    pass


def new_request_id():
    return uuid.uuid4().hex


def issue_key(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", value):
        raise argparse.ArgumentTypeError("Expected a Jira issue key such as CE-1668.")
    return value


def limit(value):
    number = int(value)
    if not 1 <= number <= 100:
        raise argparse.ArgumentTypeError("Limit must be between 1 and 100.")
    return number


def offset(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("Offset must be nonnegative.")
    return number


def credentials():
    auth = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "auth.json"
    try:
        document = json.loads(auth.read_text())
        tokens = document.get("tokens") if isinstance(document, dict) else None
        token = tokens.get("access_token") if isinstance(tokens, dict) else None
        account = tokens.get("account_id") if isinstance(tokens, dict) else None
    except (OSError, ValueError):
        raise JiraError("Cannot read the file-backed Codex login. Sign in with Codex normally; no credentials were changed.") from None
    if not isinstance(token, str) or not token.strip():
        raise JiraError("No file-backed Codex access token is available. Other credential backends are not supported.")
    if account is not None and (not isinstance(account, str) or not account.strip()):
        raise JiraError("The file-backed Codex account ID is invalid.")
    if any(ord(c) < 32 or ord(c) == 127 for c in token + (account or "")):
        raise JiraError("The file-backed Codex credentials contain invalid header characters.")
    return token, account


def failure_detail(payload, secrets):
    if not isinstance(payload, dict):
        return ""
    error = payload.get("error")
    message = error.get("message") if isinstance(error, dict) else error
    if not isinstance(message, str):
        message = payload.get("message") or payload.get("detail")
    if not isinstance(message, str) or "<" in message:
        return ""
    for secret in secrets:
        message = message.replace(secret, "[redacted]")
    return " Reported error: " + " ".join(message.split())[:240]


def rpc_response(body, request_id):
    try:
        messages = [json.loads(body)]
    except ValueError:
        messages = []
        for event in re.split(r"\r?\n\r?\n", body):
            lines = []
            for line in event.splitlines():
                if line.startswith("data:"):
                    value = line[5:]
                    lines.append(value[1:] if value.startswith(" ") else value)
            if lines:
                try:
                    messages.append(json.loads("\n".join(lines)))
                except ValueError:
                    raise JiraError("The Jira gateway returned malformed SSE data.") from None
        if body.strip() and not messages:
            raise JiraError("The Jira gateway returned no valid JSON-RPC messages.")
    if any(not isinstance(message, dict) or not any(k in message for k in ("method", "result", "error")) for message in messages):
        raise JiraError("The Jira gateway returned an invalid JSON-RPC message.")
    replies = [m for m in messages if isinstance(m, dict) and m.get("id") == request_id]
    if not replies:
        raise MissingReply("The Jira gateway did not return a matching JSON-RPC response.")
    if len(replies) != 1:
        raise JiraError("The Jira gateway did not return one matching JSON-RPC response.")
    return replies[0]


def decode_response(body, secrets=(), request_id=1):
    message = rpc_response(body, request_id)
    if "error" in message:
        code = message["error"].get("code") if isinstance(message["error"], dict) else None
        suffix = f" ({code})" if isinstance(code, int) else ""
        raise JiraError(f"The Jira gateway returned a JSON-RPC error{suffix}." + failure_detail(message, secrets))
    result = message.get("result")
    if not isinstance(result, dict):
        raise JiraError("The Jira gateway returned an invalid MCP result.")
    if result.get("isError"):
        raise JiraError("The Jira operation returned an MCP tool error.")
    structured = result.get("structuredContent")
    parsed = []
    extra = []
    content = result.get("content", [])
    if not isinstance(content, list):
        raise JiraError("The Jira operation returned invalid content.")
    for item in content:
        if not isinstance(item, dict):
            raise JiraError("The Jira operation returned invalid content.")
        if item.get("type") == "text":
            try:
                candidate = json.loads(item.get("text", ""))
            except (ValueError, TypeError):
                extra.append(item)
                continue
            parsed.append((candidate, item))
        else:
            extra.append(item)
    candidates = [value for value, _ in parsed if isinstance(value, dict) and isinstance(value.get("data"), dict)]
    if candidates:
        payload = candidates[0]
        if any(value != payload for value in candidates[1:]):
            raise JiraError("The Jira operation returned conflicting data objects.")
    else:
        payload = structured if structured is not None else next((value for value, _ in parsed), None)
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), dict) or payload.get("error"):
        kind = type(payload).__name__
        data_kind = type(payload.get("data")).__name__ if isinstance(payload, dict) else "missing"
        raise JiraError(f"The Jira operation did not return the expected data object (payload={kind}, data={data_kind})." + failure_detail(payload, secrets))
    for value, item in parsed:
        if value != payload:
            extra.append(item)
    if structured is not None and structured != payload:
        payload = {**payload, "_mcpStructuredContent": structured}
    if extra:
        payload = {**payload, "_mcpExtraContent": extra}
    return payload


def request(tool, arguments):
    if tool not in TOOLS or (tool == "atlassian.executeRead" and arguments.get("name") != "listJiraIssueComments"):
        raise JiraError("Only the workflow's allowlisted Jira reads are supported.")
    token, account = credentials()
    for attempt in (1, 2):
        try:
            return request_attempt(tool, arguments, token, account)
        except TransientReadError as error:
            if attempt == 2:
                raise JiraError(f"{error} Failed after 2 attempts; no direct-network or built-in-client fallback was used.") from None
            print(f"jira: {error} Retrying this read once in 1 second (attempt 2 of 2).", file=sys.stderr, flush=True)
            time.sleep(1)


def request_attempt(tool, arguments, token, account):
    headers = [
        "Authorization: Bearer " + token,
        "Content-Type: application/json",
        "Accept: text/event-stream, application/json",
        "X-OpenAI-Product-Sku: codex",
        "originator: codex_cli_rs",
    ]
    if account:
        headers.append("ChatGPT-Account-Id: " + account)
    request_id = new_request_id()
    message = {"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": {"name": tool, "arguments": arguments}}
    config = "".join("header = " + json.dumps(header) + "\n" for header in headers)
    config += "data-binary = " + json.dumps(json.dumps(message)) + "\n"
    command = [
        "curl", "-q", "--silent", "--show-error", "--proxy", PROXY, "--noproxy", "",
        "--proto", "=https", "--connect-timeout", "5", "--max-time", "60",
        "--user-agent", "codex-mcp-client/0.162.1", "--config", "-",
        "--write-out", STATUS_MARKER + "%{http_code}\n", ENDPOINT,
    ]
    try:
        completed = subprocess.run(command, input=config, text=True, capture_output=True, timeout=65)
    except subprocess.TimeoutExpired:
        raise TransientReadError("The Jira transport exceeded its 65-second process deadline.") from None
    except OSError:
        raise JiraError("Could not launch curl. Check that curl is installed.") from None
    body, marker, status = completed.stdout.rpartition(STATUS_MARKER)
    if not marker or not re.fullmatch(r"[0-9]{3}\n?", status):
        if not completed.returncode:
            raise JiraError("The Jira transport returned an invalid HTTP status.")
        body, status = completed.stdout, None
    else:
        status = int(status.strip()) or None
    if status is not None and status != 200:
        blocked = "application blocked" in body.casefold()
        reason = " (Application Blocked)" if blocked else ""
        login = " Sign in with Codex normally if the login has expired." if status == 401 else ""
        error = TransientReadError if status in {408, 502, 503, 504} and not blocked else JiraError
        raise error(f"The Jira request failed: HTTP {status}{reason}.{login}")
    if status == 200 and token in body:
        raise JiraError("The Jira response unexpectedly contained authentication material; it was not displayed or saved.")
    if completed.returncode:
        detail = f"Jira transport: curl {completed.returncode}, HTTP {status or 'unavailable'}, {len(body.encode('utf-8'))} body bytes."
        if completed.returncode == 28 and status == 200:
            try:
                rpc_response(body, request_id)
            except MissingReply:
                raise TransientReadError(detail + " Timed out at the 60-second request limit without a matching reply.") from None
        elif completed.returncode in {5, 6, 7, 18, 28, 52, 55, 56}:
            raise TransientReadError(detail)
        else:
            raise JiraError(detail + " This failure is not eligible for automatic retry.")
    if status != 200:
        raise JiraError("The Jira transport returned no successful HTTP status.")
    payload = decode_response(body, secrets=(token,), request_id=request_id)
    if token in json.dumps(payload):
        raise JiraError("The Jira response unexpectedly contained authentication material; it was not displayed or saved.")
    return payload


def operation(args):
    if args.command == "resources":
        return "atlassian.getAccessibleAtlassianResources", {}
    if not args.cloud_id or not args.cloud_id.strip():
        raise JiraError("Discover resources once, then pass the returned --cloud-id explicitly.")
    common = {"cloudId": args.cloud_id, "view": args.view}
    if args.command == "issue":
        common["issueIdOrKey"] = args.ticket
        if args.fields:
            common["fields"] = args.fields
        return "atlassian.getJiraIssue", common
    if args.command == "search":
        if not args.jql.strip():
            raise JiraError("JQL must not be empty.")
        common.update(jql=args.jql, maxResults=args.limit, searchResultMode="issues")
        if args.next_page_token:
            common["nextPageToken"] = args.next_page_token
        if args.fields:
            common["fields"] = args.fields
        return "atlassian.searchJiraIssuesUsingJql", common
    common.update(name="listJiraIssueComments", inputs={
        "issueIdOrKey": args.ticket, "startAt": args.start_at, "maxResults": args.limit, "orderBy": "created",
    })
    return "atlassian.executeRead", common


def snapshots(args, payload):
    data = payload["data"]
    if args.command == "resources":
        if not isinstance(data.get("resources"), list):
            raise JiraError("The resource response has no resources list.")
        return []
    if args.command == "issue":
        if data.get("key") != args.ticket:
            raise JiraError("The Jira response does not match the requested issue key.")
        return [(args.ticket, payload)]
    if args.command == "comments":
        if not isinstance(data.get("comments"), list):
            raise JiraError("The Jira response has no comments list.")
        return [(args.ticket, payload)]
    issues = data.get("issues")
    if not isinstance(issues, list):
        raise JiraError("The Jira search response has no issues list.")
    entries = []
    for issue in issues:
        if not isinstance(issue, dict):
            raise JiraError("The Jira search returned an invalid issue.")
        try:
            key = issue_key(issue.get("key"))
        except argparse.ArgumentTypeError:
            raise JiraError("The Jira search returned an invalid issue key.") from None
        if issue.get("fields") or any(k not in {"id", "key", "self", "fields"} for k in issue):
            entries.append((key, {**payload, "data": {**data, "issues": [issue]}}))
    return entries


def save_snapshot(args, key, payload, tool, arguments):
    data_dir = Path(os.path.abspath(args.data_dir))
    if any(path.is_symlink() for path in (data_dir, *data_dir.parents)):
        raise JiraError("The private data directory must not traverse symlinks.")
    private_dir(data_dir)
    private_dir(data_dir / "tickets")
    directory = private_dir(data_dir / "tickets" / key)
    path = directory / "jira.md"
    if path.exists() and path.lstat().st_nlink != 1:
        raise JiraError("The snapshot must not be a hard-linked file.")
    content = json.dumps(payload, ensure_ascii=False, indent=2)
    fence = "`" * max(3, 1 + max((len(m) for m in re.findall(r"`+", content)), default=0))
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    entry = (
        f"\n## {key} — {stamp}\n\n"
        f"- Source: {args.site}/browse/{key}\n"
        f"- Operation: `{tool}`; view: `{args.view}`\n"
        f"- Request: `{json.dumps(arguments, ensure_ascii=True)}`\n"
        "- Coverage: partial snapshot of the returned fields/page only; omitted content was not verified absent.\n\n"
        f"{fence}json\n{content}\n{fence}\n"
    )
    with private_append(path) as handle:
        if os.fstat(handle.fileno()).st_nlink != 1:
            raise JiraError("The snapshot must not be a hard-linked file.")
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.write(entry)
        handle.flush()
        os.fsync(handle.fileno())
    return path


def parser():
    result = argparse.ArgumentParser(description="Read Jira through the existing Codex login and GTS VDI relay; successful ticket reads are saved privately.")
    result.add_argument("--cloud-id", help="ID returned by resources; required for issue/search/comments")
    result.add_argument("--site", default=SITE, help="source site URL from resources (used for snapshot provenance only)")
    result.add_argument("--data-dir", type=Path, default=Path.home() / ".local/share/engine-tickets")
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("resources", help="discover accessible sites once per Codex session")
    for command in ("issue", "search", "comments"):
        sub = commands.add_parser(command)
        sub.add_argument("--view", choices=("compact", "evidence", "full"), default="compact" if command == "search" else "evidence")
        if command == "search":
            sub.add_argument("jql")
            sub.add_argument("--next-page-token")
        else:
            sub.add_argument("ticket", type=issue_key)
        if command in {"issue", "search"}:
            sub.add_argument("--fields", nargs="+", help="explicit Jira field names/IDs")
        if command in {"search", "comments"}:
            sub.add_argument("--limit", type=limit, default=25)
        if command == "comments":
            sub.add_argument("--start-at", type=offset, default=0)
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        site = urlsplit(args.site)
        if (site.scheme != "https" or not site.hostname or not site.hostname.endswith(".atlassian.net")
                or site.username or site.password or site.port or site.path not in {"", "/"} or site.query or site.fragment):
            raise JiraError("--site must be an HTTPS Atlassian site root from resources.")
        args.site = args.site.rstrip("/")
        tool, arguments = operation(args)
        payload = request(tool, arguments)
        entries = snapshots(args, payload)
        print(json.dumps(payload, ensure_ascii=False, indent=2), flush=True)
        for key, content in entries:
            try:
                path = save_snapshot(args, key, content, tool, arguments)
            except (OSError, ValueError):
                raise JiraError("Could not save the private Jira snapshot; the fetched JSON is on stdout. Check private directory/file ownership, permissions, and free space.") from None
            print(f"Saved snapshot: {path}", file=sys.stderr)
        return 0
    except JiraError as error:
        print(f"jira: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print("jira: Invalid local settings or inaccessible private files. No retry or fallback was attempted.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
