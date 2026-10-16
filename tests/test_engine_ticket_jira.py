import argparse
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
SKILL = REPO / "config/codex/skills/engine-ticket-workflow"
SCRIPT = SKILL / "scripts/jira.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("engine_ticket_jira", SCRIPT)
jira = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(jira)


class JiraTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="engine-jira-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.auth_home = self.root / "codex"
        self.auth_home.mkdir()
        self.token = "test-access-token-must-not-leak"
        self.auth = self.auth_home / "auth.json"
        self.auth.write_text(json.dumps({"tokens": {"access_token": self.token, "account_id": "test-account"}}))
        self.data = self.root / "private"
        self.environ = mock.patch.dict(os.environ, {"CODEX_HOME": str(self.auth_home)})
        self.environ.start()
        self.addCleanup(self.environ.stop)
        ids = mock.patch.object(jira, "new_request_id", return_value=1)
        ids.start()
        self.addCleanup(ids.stop)
        sleep = mock.patch.object(jira.time, "sleep")
        self.sleep = sleep.start()
        self.addCleanup(sleep.stop)
        self.issue = {"key": "CE-1668", "fields": {"summary": "Fixture", "description": "Details"}}

    def args(self, *args):
        return jira.parser().parse_args(["--data-dir", str(self.data), "--cloud-id", "fixture-cloud", *args])

    def response(self, data, *, status=200, sse=False, result=None, request_id=1):
        result = result if result is not None else {"isError": False, "content": [{"type": "text", "text": json.dumps({"data": data})}]}
        body = json.dumps({"jsonrpc": "2.0", "id": request_id, "result": result})
        if sse:
            body = "event: message\ndata: " + body + "\n\n"
        return subprocess.CompletedProcess([], 0, body + jira.STATUS_MARKER + str(status) + "\n", "")

    def run_main(self, *args, response=None, side_effect=None):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(jira.subprocess, "run", return_value=response or self.response(self.issue), side_effect=side_effect) as run:
            with redirect_stdout(out), redirect_stderr(err):
                code = jira.main(["--data-dir", str(self.data), "--cloud-id", "fixture-cloud", *args])
        return code, out.getvalue(), err.getvalue(), run

    def test_operations_and_defaults(self):
        tool, args = jira.operation(self.args("resources"))
        self.assertEqual((tool, args), ("atlassian.getAccessibleAtlassianResources", {}))
        tool, args = jira.operation(self.args("issue", "CE-1668", "--fields", "summary", "description"))
        self.assertEqual(tool, "atlassian.getJiraIssue")
        self.assertEqual(args, {"cloudId": "fixture-cloud", "view": "evidence", "issueIdOrKey": "CE-1668", "fields": ["summary", "description"]})
        tool, args = jira.operation(self.args("search", "key = CE-1668", "--next-page-token", "next"))
        self.assertEqual(tool, "atlassian.searchJiraIssuesUsingJql")
        self.assertEqual(args, {"cloudId": "fixture-cloud", "view": "compact", "jql": "key = CE-1668", "maxResults": 25, "searchResultMode": "issues", "nextPageToken": "next"})
        tool, args = jira.operation(self.args("comments", "CE-1668", "--start-at", "20", "--limit", "30", "--view", "full"))
        self.assertEqual(tool, "atlassian.executeRead")
        self.assertEqual(args, {"cloudId": "fixture-cloud", "view": "full", "name": "listJiraIssueComments", "inputs": {"issueIdOrKey": "CE-1668", "startAt": 20, "maxResults": 30, "orderBy": "created"}})

    def test_invalid_keys_limits_offsets_commands_and_missing_cloud(self):
        for args in [("issue", "../CE-1668"), ("issue", "ce-1668"), ("search", "query", "--limit", "0"), ("search", "query", "--limit", "101"), ("comments", "CE-1668", "--start-at", "-1"), ("write", "CE-1668")]:
            with self.subTest(args=args), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                self.args(*args)
        with self.assertRaises(jira.JiraError):
            jira.operation(jira.parser().parse_args(["issue", "CE-1668"]))
        with self.assertRaises(jira.JiraError):
            jira.operation(self.args("search", " "))

    def test_only_allowlisted_reads_can_reach_transport(self):
        with mock.patch.object(jira.subprocess, "run") as run:
            for tool, args in [("atlassian.editJiraIssue", {}), ("atlassian.executeWrite", {}), ("atlassian.executeRead", {"name": "editJiraIssue"}), ("atlassian.executeRead", {"name": "getConfluenceContent"})]:
                with self.subTest(tool=tool), self.assertRaises(jira.JiraError):
                    jira.request(tool, args)
            run.assert_not_called()

    def test_transport_pins_proxy_endpoint_and_passes_credentials_only_on_stdin(self):
        with mock.patch.dict(os.environ, {"HTTPS_PROXY": "http://wrong.invalid", "NO_PROXY": "*"}):
            code, out, err, run = self.run_main("issue", "CE-1668")
        self.assertEqual(code, 0, err)
        command = run.call_args.args[0]
        self.assertEqual(command[:2], ["curl", "-q"])
        self.assertEqual(command[-1], jira.ENDPOINT)
        self.assertEqual(command[command.index("--proxy") + 1], jira.PROXY)
        self.assertEqual(command[command.index("--noproxy") + 1], "")
        self.assertEqual(command[command.index("--proto") + 1], "=https")
        self.assertEqual(command[command.index("--connect-timeout") + 1], "5")
        self.assertEqual(command[command.index("--max-time") + 1], "60")
        self.assertFalse(set(command) & {"-L", "--location", "-k", "--insecure", "--retry", "--verbose", "--trace"})
        self.assertNotIn(self.token, repr(command))
        self.assertNotIn(self.token, out + err)
        config = run.call_args.kwargs["input"]
        self.assertIn(self.token, config)
        self.assertEqual(run.call_args.kwargs["timeout"], 65)
        lines = [line.split(" = ", 1) for line in config.splitlines()]
        self.assertIn("ChatGPT-Account-Id: test-account", [json.loads(value) for name, value in lines if name == "header"])
        body = json.loads(next(json.loads(value) for name, value in lines if name == "data-binary"))
        self.assertEqual(body["params"]["arguments"]["issueIdOrKey"], "CE-1668")
        self.assertNotIn(self.token, (self.data / "tickets/CE-1668/jira.md").read_text())

    def test_missing_malformed_or_unsupported_auth_never_runs_curl(self):
        for document in [None, "not-json", [], {}, {"tokens": None}, {"tokens": {"access_token": 3}}, {"tokens": {"access_token": self.token, "account_id": []}}, {"tokens": {"access_token": self.token + "\n"}}]:
            if document is None:
                self.auth.unlink(missing_ok=True)
            elif document == "not-json":
                self.auth.write_text(document)
            else:
                self.auth.write_text(json.dumps(document))
            with self.subTest(document=document):
                code, out, err, run = self.run_main("issue", "CE-1668")
                self.assertEqual(code, 1)
                self.assertEqual(out, "")
                self.assertNotIn(self.token, err)
                run.assert_not_called()
                self.assertFalse(self.data.exists())

    def test_json_and_sse_decoding(self):
        for sse in [False, True]:
            with self.subTest(sse=sse):
                response = self.response(self.issue, sse=sse)
                body = response.stdout.rpartition(jira.STATUS_MARKER)[0]
                self.assertEqual(jira.decode_response(body), {"data": self.issue})
        reply = json.loads(self.response(self.issue).stdout.rpartition(jira.STATUS_MARKER)[0])
        encoded = json.dumps(reply, indent=2)
        body = ': keepalive\r\nevent: message\r\ndata: {"jsonrpc":"2.0","method":"notification"}\r\n\r\n'
        body += "\r\n".join("data: " + line for line in encoded.splitlines()) + "\r\n\r\n"
        self.assertEqual(jira.decode_response(body), {"data": self.issue})

    def test_structured_content_and_extra_warnings_are_preserved(self):
        result = {"structuredContent": {"data": self.issue}, "content": [{"type": "text", "text": "Returned HTML to avoid losing rich text."}]}
        code, out, err, _ = self.run_main("issue", "CE-1668", response=self.response(None, result=result))
        self.assertEqual(code, 0, err)
        self.assertIn("Returned HTML", json.loads(out)["_mcpExtraContent"][0]["text"])

    def test_separate_structured_metadata_does_not_hide_the_text_ticket_response(self):
        metadata = {"issues": [], "version": 1}
        result = {"isError": False, "structuredContent": metadata, "content": [{"type": "text", "text": json.dumps({"data": self.issue})}]}
        code, out, err, _ = self.run_main("issue", "CE-1668", response=self.response(None, result=result))
        self.assertEqual(code, 0, err)
        payload = json.loads(out)
        self.assertEqual(payload["data"], self.issue)
        self.assertEqual(payload["_mcpStructuredContent"], metadata)
        self.assertIn('"key": "CE-1668"', (self.data / "tickets/CE-1668/jira.md").read_text())

    def test_http_and_redirect_errors_do_not_save_or_print_error_bodies(self):
        for status in [301, 401, 403, 503]:
            response = subprocess.CompletedProcess([], 0, '<html><title>Application Blocked</title>' + self.token + jira.STATUS_MARKER + str(status) + "\n", "")
            with self.subTest(status=status):
                code, out, err, _ = self.run_main("issue", "CE-1668", response=response)
                self.assertEqual(code, 1)
                self.assertEqual(out, "")
                self.assertIn(f"HTTP {status}", err)
                self.assertNotIn(self.token, err)
                self.assertFalse(self.data.exists())

    def test_curl_failures_and_exceptions_do_not_leak_diagnostics(self):
        response = subprocess.CompletedProcess([], 7, self.token, self.token)
        code, out, err, _ = self.run_main("issue", "CE-1668", response=response)
        self.assertEqual(code, 1)
        self.assertNotIn(self.token, out + err)
        for exception in [FileNotFoundError(self.token), subprocess.TimeoutExpired([self.token], 65, output=self.token, stderr=self.token)]:
            with self.subTest(exception=type(exception).__name__):
                code, out, err, _ = self.run_main("issue", "CE-1668", side_effect=exception)
                self.assertEqual(code, 1)
                self.assertNotIn(self.token, out + err)
        self.assertFalse(self.data.exists())

    def test_empty_stream_timeout_retries_once_with_fresh_ids_and_saves_once(self):
        timeout = subprocess.CompletedProcess([], 28, jira.STATUS_MARKER + "200\n", self.token)
        success = self.response(self.issue, request_id="second")
        with mock.patch.object(jira, "new_request_id", side_effect=["first", "second"]):
            code, out, err, run = self.run_main("issue", "CE-1668", side_effect=[timeout, success])
        self.assertEqual(code, 0, err)
        self.assertEqual(run.call_count, 2)
        self.sleep.assert_called_once_with(1)
        self.assertIn("curl 28, HTTP 200, 0 body bytes", err)
        self.assertIn("without a matching reply", err)
        self.assertIn("attempt 2 of 2", err)
        self.assertEqual(err.count("Saved snapshot:"), 1)
        self.assertNotIn(self.token, out + err)
        ids = []
        for call in run.call_args_list:
            config = call.kwargs["input"]
            request = json.loads(next(json.loads(x.split(" = ", 1)[1]) for x in config.splitlines() if x.startswith("data-binary = ")))
            ids.append(request["id"])
            self.assertEqual(call.args[0][-1], jira.ENDPOINT)
            self.assertEqual(call.args[0][call.args[0].index("--proxy") + 1], jira.PROXY)
        self.assertEqual(ids, ["first", "second"])
        self.assertEqual((self.data / "tickets/CE-1668/jira.md").read_text().count("## CE-1668 —"), 1)

    def test_exhausted_timeout_reports_curl_http_bytes_and_attempt_count(self):
        timeout = subprocess.CompletedProcess([], 28, jira.STATUS_MARKER + "200\n", self.token)
        code, out, err, run = self.run_main("comments", "CE-1668", response=timeout)
        self.assertEqual(code, 1)
        self.assertEqual(run.call_count, 2)
        self.sleep.assert_called_once_with(1)
        self.assertIn("curl 28, HTTP 200, 0 body bytes", err)
        self.assertIn("Failed after 2 attempts", err)
        self.assertNotIn(self.token, out + err)
        self.assertFalse(self.data.exists())

    def test_complete_matching_reply_is_accepted_when_only_sse_close_times_out(self):
        response = self.response(self.issue, sse=True)
        response.returncode = 28
        code, out, err, run = self.run_main("issue", "CE-1668", response=response)
        self.assertEqual(code, 0, err)
        run.assert_called_once()
        self.sleep.assert_not_called()
        self.assertEqual(json.loads(out)["data"], self.issue)
        self.assertEqual(err.count("Saved snapshot:"), 1)

    def test_complete_tool_error_on_timed_out_stream_is_not_retried(self):
        response = self.response(None, result={"isError": True, "content": [{"type": "text", "text": "Tool error"}]})
        response.returncode = 28
        code, out, err, run = self.run_main("issue", "CE-1668", response=response)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        run.assert_called_once()
        self.sleep.assert_not_called()
        self.assertIn("MCP tool error", err)
        self.assertFalse(self.data.exists())

    def test_transient_http_failures_retry_but_blocked_pages_never_do(self):
        for status in [408, 502, 503, 504]:
            self.sleep.reset_mock()
            failure = subprocess.CompletedProcess([], 0, "Unavailable" + jira.STATUS_MARKER + str(status) + "\n", "")
            with self.subTest(status=status):
                code, out, err, run = self.run_main("issue", "CE-1668", side_effect=[failure, self.response(self.issue)])
                self.assertEqual(code, 0, err)
                self.assertEqual(run.call_count, 2)
                self.sleep.assert_called_once_with(1)
        for status in [301, 401, 403, 429, 503]:
            self.sleep.reset_mock()
            body = "<title>Application Blocked</title>" if status == 503 else "Authentication or rate-limit error"
            failure = subprocess.CompletedProcess([], 0, body + jira.STATUS_MARKER + str(status) + "\n", "")
            with self.subTest(blocked_status=status):
                code, _, err, run = self.run_main("issue", "CE-1668", response=failure)
                self.assertEqual(code, 1)
                run.assert_called_once()
                self.sleep.assert_not_called()

    def test_retryable_curl_failures_are_allowlisted_and_tls_errors_are_terminal(self):
        for curl_code in [5, 6, 7, 18, 28, 52, 55, 56]:
            self.sleep.reset_mock()
            failure = subprocess.CompletedProcess([], curl_code, jira.STATUS_MARKER + "000\n", self.token)
            with self.subTest(curl_code=curl_code):
                code, out, err, run = self.run_main("issue", "CE-1668", side_effect=[failure, self.response(self.issue)])
                self.assertEqual(code, 0, err)
                self.assertEqual(run.call_count, 2)
                self.assertNotIn(self.token, out + err)
        for curl_code in [1, 35, 60, 77]:
            self.sleep.reset_mock()
            failure = subprocess.CompletedProcess([], curl_code, jira.STATUS_MARKER + "000\n", self.token)
            with self.subTest(permanent_curl_code=curl_code):
                code, out, err, run = self.run_main("issue", "CE-1668", response=failure)
                self.assertEqual(code, 1)
                run.assert_called_once()
                self.sleep.assert_not_called()
                self.assertIn(f"curl {curl_code}", err)
                self.assertNotIn(self.token, out + err)

    def test_process_timeout_retries_without_logging_exception_output(self):
        timeout = subprocess.TimeoutExpired([self.token], 65, output=self.token, stderr=self.token)
        code, out, err, run = self.run_main("issue", "CE-1668", side_effect=[timeout, self.response(self.issue)])
        self.assertEqual(code, 0, err)
        self.assertEqual(run.call_count, 2)
        self.assertIn("65-second process deadline", err)
        self.assertNotIn(self.token, out + err)

    def test_invalid_reply_is_not_retried_even_if_stream_later_times_out(self):
        for body in ["<html>unexpected</html>", "data: {broken}\n\n", "{}"]:
            self.sleep.reset_mock()
            failure = subprocess.CompletedProcess([], 28, body + jira.STATUS_MARKER + "200\n", "")
            with self.subTest(body=body):
                code, out, err, run = self.run_main("issue", "CE-1668", response=failure)
                self.assertEqual(code, 1)
                run.assert_called_once()
                self.sleep.assert_not_called()
                self.assertFalse(self.data.exists())

    def test_json_rpc_error_is_terminal_even_when_the_stream_stays_open(self):
        body = json.dumps({"id": 1, "error": {"code": -32603, "message": "Operation rejected"}})
        failure = subprocess.CompletedProcess([], 28, body + jira.STATUS_MARKER + "200\n", "")
        code, out, err, run = self.run_main("comments", "CE-1668", response=failure)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("JSON-RPC error (-32603)", err)
        run.assert_called_once()
        self.sleep.assert_not_called()
        self.assertFalse(self.data.exists())

    def test_malformed_rpc_and_mcp_errors_are_sanitized(self):
        bodies = [
            "<html>unexpected</html>", "data: {broken}\n\n", "{}", 'data: {"id":2,"result":{}}\n\n',
            json.dumps({"id": 1, "error": {"code": -32603, "message": self.token}}),
            json.dumps({"id": 1, "result": None}),
            json.dumps({"id": 1, "result": {"isError": True, "content": [{"type": "text", "text": self.token}]}}),
            json.dumps({"id": 1, "result": {"content": None}}),
            json.dumps({"id": 1, "result": {"content": [None]}}),
            json.dumps({"id": 1, "result": {"content": [{"type": "text", "text": "not JSON"}]}}),
        ]
        for body in bodies:
            with self.subTest(body=body[:40]):
                response = subprocess.CompletedProcess([], 0, body + jira.STATUS_MARKER + "200\n", "")
                code, out, err, run = self.run_main("issue", "CE-1668", response=response)
                self.assertEqual(code, 1)
                self.assertEqual(out, "")
                run.assert_called_once()
                self.assertNotIn(self.token, err)
                self.assertFalse(self.data.exists())

    def test_success_response_cannot_echo_authentication_into_output_or_records(self):
        self.issue["fields"]["description"] = self.token
        code, out, err, _ = self.run_main("issue", "CE-1668")
        self.assertEqual(code, 1)
        self.assertNotIn(self.token, out + err)
        self.assertFalse(self.data.exists())

    def test_upstream_error_details_are_bounded_and_redact_encoded_credentials(self):
        detail = self.token.replace("t", "\\u0074")
        text = '{"error":{"message":"Login rejected ' + detail + '"}}'
        result = {"content": [{"type": "text", "text": text}]}
        code, out, err, _ = self.run_main("issue", "CE-1668", response=self.response(None, result=result))
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertNotIn(self.token, err)
        self.assertIn("Reported error: Login rejected [redacted]", err)
        self.assertIn("payload=dict, data=NoneType", err)
        self.assertFalse(self.data.exists())

    def test_resources_are_not_ticket_snapshots(self):
        data = {"resources": [{"cloudId": "fixture-cloud", "url": jira.SITE}]}
        code, out, err, _ = self.run_main("resources", response=self.response(data))
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["data"], data)
        self.assertEqual(err, "")
        self.assertFalse(self.data.exists())

    def test_snapshots_append_preserve_rich_content_and_do_not_initialize_workflows(self):
        directory = self.data / "tickets/CE-1668"
        directory.mkdir(parents=True)
        path = directory / "jira.md"
        path.write_text("# Existing evidence\nUser note.\n")
        self.issue.update(appliedContentFormat="html")
        self.issue["fields"]["description"] = '<p>Rich text</p>\n```\n````'
        code, out, err, _ = self.run_main("issue", "CE-1668", "--view", "full")
        self.assertEqual(code, 0, err)
        content = path.read_text()
        self.assertTrue(content.startswith("# Existing evidence\nUser note.\n"))
        self.assertIn("Rich text", content)
        self.assertIn('"appliedContentFormat": "html"', content)
        self.assertIn("`````json", content)
        self.assertIn("partial snapshot", content)
        self.assertIn("+00:00", content)
        self.assertIn(jira.SITE + "/browse/CE-1668", content)
        for directory in [self.data, self.data / "tickets", path.parent]:
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(path.parent.iterdir()), [path])
        code, _, err, _ = self.run_main("issue", "CE-1668", "--view", "compact")
        self.assertEqual(code, 0, err)
        self.assertEqual(path.read_text().count("## CE-1668 —"), 2)

    def test_search_saves_each_returned_issue_but_not_key_only_hits(self):
        data = {"issues": [self.issue, {"key": "CE-1669", "fields": {"summary": "Related"}}, {"key": "CE-1700", "id": "1"}, {"key": "CE-1701", "fields": {}}], "isLast": False, "nextPageToken": "next-page"}
        code, out, err, _ = self.run_main("search", "project = CE", response=self.response(data))
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["data"]["nextPageToken"], "next-page")
        self.assertEqual(sorted(p.name for p in (self.data / "tickets").iterdir()), ["CE-1668", "CE-1669"])
        content = (self.data / "tickets/CE-1668/jira.md").read_text()
        self.assertIn("next-page", content)
        self.assertNotIn('"key": "CE-1669"', content)
        self.assertEqual(err.count("Saved snapshot:"), 2)

    def test_comments_preserve_pagination_visibility_and_threads(self):
        data = {"comments": [{"id": "11", "body": "Discussion", "parentId": "10", "visibility": {"type": "role", "value": "Developers"}, "jsdPublic": False}], "startAt": 20, "maxResults": 20, "total": 80, "isLast": False, "appliedContentFormat": "html"}
        code, out, err, _ = self.run_main("comments", "CE-1668", "--view", "full", "--start-at", "20", response=self.response(data))
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["data"], data)
        content = (self.data / "tickets/CE-1668/jira.md").read_text()
        self.assertIn('"parentId": "10"', content)
        self.assertIn('"jsdPublic": false', content)
        self.assertIn('"maxResults": 20', content)

    def test_invalid_results_cannot_create_ticket_paths(self):
        for args, data in [(("issue", "CE-1668"), {"key": "CE-9999"}), (("search", "query"), {"issues": [{"key": "../../escape", "fields": {"summary": "Bad"}}]}), (("comments", "CE-1668"), {}), (("resources",), {})]:
            with self.subTest(args=args):
                code, out, err, _ = self.run_main(*args, response=self.response(data))
                self.assertEqual(code, 1)
                self.assertEqual(out, "")
                self.assertFalse(self.data.exists())

    def test_symlink_targets_and_ancestors_are_rejected(self):
        target = self.root / "user-file"
        target.write_text("Preserve me")
        for position in ["data", "tickets", "ticket", "record", "ancestor"]:
            base = self.root / position
            base.mkdir()
            data = base / "private"
            if position == "ancestor":
                (base / "alias").symlink_to(self.root, target_is_directory=True)
                data = base / "alias/nested/private"
            elif position == "data":
                data.symlink_to(self.root, target_is_directory=True)
            else:
                data.mkdir()
                if position == "tickets":
                    (data / "tickets").symlink_to(self.root, target_is_directory=True)
                else:
                    (data / "tickets").mkdir()
                    if position == "ticket":
                        (data / "tickets/CE-1668").symlink_to(self.root, target_is_directory=True)
                    else:
                        (data / "tickets/CE-1668").mkdir()
                        (data / "tickets/CE-1668/jira.md").symlink_to(target)
            with self.subTest(position=position), mock.patch.object(jira.subprocess, "run", return_value=self.response(self.issue)), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(jira.main(["--data-dir", str(data), "--cloud-id", "fixture-cloud", "issue", "CE-1668"]), 1)
            self.assertEqual(target.read_text(), "Preserve me")

    def test_hard_links_and_write_failures_are_not_reported_as_cached(self):
        directory = self.data / "tickets/CE-1668"
        directory.mkdir(parents=True)
        target = self.root / "user-file"
        target.write_text("Preserve me")
        target.chmod(0o640)
        (directory / "jira.md").hardlink_to(target)
        code, out, err, _ = self.run_main("issue", "CE-1668")
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(out)["data"]["key"], "CE-1668")
        self.assertNotIn("Saved snapshot:", err)
        self.assertEqual(target.read_text(), "Preserve me")
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        with mock.patch.object(jira, "save_snapshot", side_effect=OSError("no space")):
            code, out, err, _ = self.run_main("issue", "CE-1668")
        self.assertEqual(code, 1)
        self.assertIn("Could not save", err)
        self.assertNotIn("Saved snapshot:", err)
        self.assertEqual(json.loads(out)["data"]["key"], "CE-1668")

    def test_invalid_source_sites_fail_before_auth_or_network(self):
        for site in ["http://gtsjira.atlassian.net", "https://other.invalid", "https://user:password@gtsjira.atlassian.net", "https://gtsjira.atlassian.net/path", "https://gtsjira.atlassian.net?secret=1"]:
            with self.subTest(site=site), mock.patch.object(jira.subprocess, "run") as run, redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(jira.main(["--site", site, "resources"]), 1)
                run.assert_not_called()

    def test_cli_subprocesses_append_complete_snapshots_concurrently(self):
        binary = self.root / "bin"
        binary.mkdir()
        fake = binary / "curl"
        fake.write_text(
            "#!/usr/bin/env python3\n"
            "import json, sys\n"
            "a=sys.argv[1:]\n"
            "assert a[0]=='-q' and a[a.index('--proxy')+1]=='http://127.0.0.1:18181'\n"
            "config=sys.stdin.read()\n"
            "request=json.loads(next(json.loads(x.split(' = ',1)[1]) for x in config.splitlines() if x.startswith('data-binary = ')))\n"
            "assert request['params']['name']=='atlassian.getJiraIssue'\n"
            "data={'data':{'key':'CE-1668','fields':{'summary':'Concurrent fixture'}}}\n"
            "print(json.dumps({'jsonrpc':'2.0','id':request['id'],'result':{'content':[{'type':'text','text':json.dumps(data)}]}}))\n"
            "print('JIRA_HTTP_STATUS:200')\n"
        )
        fake.chmod(0o700)
        command = [sys.executable, str(SCRIPT), "--data-dir", str(self.data), "--cloud-id", "fixture-cloud", "issue", "CE-1668"]
        environment = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"]}
        processes = []
        try:
            for _ in range(4):
                processes.append(subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            for process in processes:
                out, err = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 0, err)
                self.assertEqual(json.loads(out)["data"]["key"], "CE-1668")
                self.assertNotIn(self.token, out + err)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
        content = (self.data / "tickets/CE-1668/jira.md").read_text()
        self.assertEqual(content.count("## CE-1668 —"), 4)
        self.assertEqual(content.count('"summary": "Concurrent fixture"'), 4)
        self.assertNotIn(self.token, content)

    def test_workflow_docs_select_helper_and_preserve_safety_rules(self):
        skill = (SKILL / "SKILL.md").read_text()
        records = (SKILL / "references/records.md").read_text()
        self.assertIn("scripts/jira.py", skill)
        self.assertIn("instead of built-in Jira tools", records)
        self.assertNotIn("Assume Jira is connected as a plugin", records)
        self.assertIn("Never commit, push", skill)
        self.assertIn("context.md", records)
        self.assertIn("partial", records)
        review = (SKILL / "references/review.md").read_text()
        self.assertIn("disables nested delegation, app tools, and web search", review)
        module = (REPO / "modules/engine-ticket-workflow.nix").read_text()
        self.assertIn("../config/codex/skills/engine-ticket-workflow", module)


if __name__ == "__main__":
    unittest.main()
