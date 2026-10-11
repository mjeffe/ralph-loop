"""Tests for lib/format_output.py. Every test drives the CLI as a subprocess.

Run from the project root:
    python3 -m unittest discover -s tests -p 'test_format_output.py'
"""
import json
import os
import select
import subprocess
import sys
import tempfile
import threading
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(PROJECT_ROOT, "lib", "format_output.py")

COMPLETE = "<promise>COMPLETE</promise>"
REPLAN = "<promise>REPLAN</promise>"
NULL_FIELDS = ("is_error", "error", "context_used", "context_max", "context_pct", "cost")


class FormatOutputTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.summary_path = os.path.join(self.tmp.name, "summary.json")
        self.log_path = os.path.join(self.tmp.name, "session.log")

    def tearDown(self):
        self.tmp.cleanup()

    def command(self, fmt="text", summary=None, log=None):
        cmd = [sys.executable, SCRIPT, "--format", fmt, "--summary", summary or self.summary_path]
        if log:
            cmd += ["--log", log]
        return cmd

    def run_cli(self, stdin=b"", **kwargs):
        if isinstance(stdin, str):
            stdin = stdin.encode("utf-8")
        return subprocess.run(self.command(**kwargs), input=stdin, capture_output=True, timeout=30, cwd=PROJECT_ROOT)

    def read_summary(self):
        with open(self.summary_path, encoding="utf-8") as fh:
            return json.load(fh)

    def read_log(self):
        with open(self.log_path, encoding="utf-8") as fh:
            return fh.read()


class TestTextFormat(FormatOutputTestCase):
    def test_empty_stdin(self):
        result = self.run_cli(b"")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = self.read_summary()
        self.assertEqual(summary["format"], "text")
        self.assertIsNone(summary["signal"])
        self.assertEqual(summary["response_chars"], 0)
        for key in NULL_FIELDS:
            self.assertIn(key, summary)
            self.assertIsNone(summary[key], key)
        self.assertEqual(summary["malformed_lines"], 0)

    def test_complete_wins_over_replan(self):
        result = self.run_cli(f"first {REPLAN}\nthen {COMPLETE}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_summary()["signal"], "COMPLETE")
        self.assertEqual(result.stdout.decode(), f"first {REPLAN}\nthen {COMPLETE}\n")

    def test_replan_only(self):
        result = self.run_cli(f"need to {REPLAN}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_summary()["signal"], "REPLAN")

    def test_no_signal_counts_response_chars(self):
        result = self.run_cli("hello\n\n   \nworld\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = self.read_summary()
        self.assertIsNone(summary["signal"])
        self.assertEqual(summary["response_chars"], len("hello") + len("world"))
        self.assertEqual(result.stdout.decode(), "hello\nworld\n")

    def test_invalid_utf8_does_not_crash(self):
        result = self.run_cli(b"bad \xff\xfe bytes\n" + COMPLETE.encode() + b"\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = self.read_summary()
        self.assertEqual(summary["signal"], "COMPLETE")
        self.assertGreater(summary["response_chars"], 0)


class TestCli(FormatOutputTestCase):
    def test_unknown_format_is_usage_error(self):
        result = self.run_cli(b"hello\n", fmt="bogus")
        self.assertEqual(result.returncode, 2)
        self.assertIn("text", result.stderr.decode())
        self.assertIn("bogus", result.stderr.decode())

    def test_summary_in_missing_directory(self):
        result = self.run_cli(b"hello\n", summary=os.path.join(self.tmp.name, "missing", "summary.json"))
        self.assertEqual(result.returncode, 1)

    def test_log_appends(self):
        with open(self.log_path, "w", encoding="utf-8") as fh:
            fh.write("PRE-EXISTING\n")
        result = self.run_cli(b"hello\nworld\n", log=self.log_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_log(), "PRE-EXISTING\nhello\nworld\n")

    def test_log_in_missing_directory(self):
        result = self.run_cli(b"hello\n", log=os.path.join(self.tmp.name, "missing", "session.log"))
        self.assertEqual(result.returncode, 1)


class TestStreaming(FormatOutputTestCase):
    def test_line_is_written_before_stdin_closes(self):
        proc = subprocess.Popen(self.command(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0, cwd=PROJECT_ROOT)
        try:
            proc.stdin.write(b"streamed line\n")
            proc.stdin.flush()
            ready, _, _ = select.select([proc.stdout], [], [], 5)
            self.assertTrue(ready, "no output within 5 seconds while stdin is still open")
            self.assertEqual(os.read(proc.stdout.fileno(), 4096), b"streamed line\n")
        finally:
            proc.stdin.close()
            proc.wait(timeout=10)
            proc.stdout.close()
            proc.stderr.close()
        self.assertEqual(proc.returncode, 0)

    def test_broken_pipe_keeps_reading_and_logging(self):
        total = 10000
        lines = [f"line {i:05d} padding to make the output exceed the pipe buffer" for i in range(1, total)]
        lines.append(f"line {total:05d} {COMPLETE}")
        payload = ("\n".join(lines) + "\n").encode()

        proc = subprocess.Popen(self.command(log=self.log_path), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0, cwd=PROJECT_ROOT)

        def feed():
            proc.stdin.write(payload)
            proc.stdin.close()

        writer = threading.Thread(target=feed)
        writer.start()
        first = proc.stdout.readline()
        proc.stdout.close()
        writer.join(timeout=30)
        stderr = proc.stderr.read()
        proc.stderr.close()
        proc.wait(timeout=30)

        self.assertEqual(first, (lines[0] + "\n").encode())
        self.assertEqual(proc.returncode, 0, stderr)
        self.assertEqual(self.read_summary()["signal"], "COMPLETE")
        self.assertEqual(self.read_log().splitlines(), lines)


FIXTURES = os.path.join(PROJECT_ROOT, "tests", "fixtures", "format_output")


def read_fixture(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as fh:
        return fh.read()


def ndjson(*objs):
    return "".join((obj if isinstance(obj, str) else json.dumps(obj)) + "\n" for obj in objs)


def assistant(*blocks, usage=None, parent=None):
    obj = {"type": "assistant", "message": {"role": "assistant", "content": list(blocks)}}
    if usage is not None:
        obj["message"]["usage"] = usage
    if parent is not None:
        obj["parent_tool_use_id"] = parent
    return obj


def tool_call(call_id, name, tool_input):
    return assistant({"type": "tool_use", "id": call_id, "name": name, "input": tool_input})


def tool_result(call_id, content, is_error=None):
    block = {"type": "tool_result", "tool_use_id": call_id, "content": content}
    if is_error is not None:
        block["is_error"] = is_error
    return {"type": "user", "message": {"role": "user", "content": [block]}}


class TestStreamJsonAmpFixture(FormatOutputTestCase):
    PROMPT_LINE = "You are an expert software architect and planner working in Ralph plan mode."

    def run_amp(self):
        result = self.run_cli(read_fixture("amp.ndjson"), fmt="stream-json", log=self.log_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.decode(), self.read_log()

    def test_summary(self):
        self.run_amp()
        self.assertEqual(self.read_summary(), {
            "format": "stream-json",
            "signal": "COMPLETE",
            "response_chars": 2082,
            "is_error": False,
            "error": None,
            "context_used": 130615,
            "context_max": 300000,
            "context_pct": 44,
            "cost": None,
            "malformed_lines": 0,
        })

    def test_display(self):
        screen, log = self.run_amp()
        self.assertIn("[thinking] Let me start by reading the key files", screen)
        self.assertIn("[tool] Read: /home/mjeffe/src/mrj/ralph-loop/AGENTS.md", screen)
        screen_lines = screen.splitlines()
        log_lines = log.splitlines()
        self.assertFalse([line for line in screen_lines if line.startswith(("[tool result] ", "[tool error] "))])
        self.assertEqual(len([line for line in log_lines if line.startswith("[tool result] ")]), 56)
        self.assertFalse([line for line in log_lines if line.startswith("[tool error] ")])
        self.assertNotIn(self.PROMPT_LINE, screen)
        self.assertNotIn(self.PROMPT_LINE, log)
        self.assertEqual(screen.count("All other specs are satisfied."), 1)

    def test_signal_ignores_prompt_and_tool_results(self):
        lines = read_fixture("amp.ndjson").splitlines()
        types = [json.loads(line).get("type") for line in lines]
        last_assistant = len(types) - 1 - types[::-1].index("assistant")
        reduced = [line for i, line in enumerate(lines) if i != last_assistant and types[i] != "result"]
        self.assertTrue(any(COMPLETE in line for line in reduced))
        result = self.run_cli("\n".join(reduced) + "\n", fmt="stream-json")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = self.read_summary()
        self.assertIsNone(summary["signal"])
        self.assertGreater(summary["response_chars"], 0)


class TestStreamJsonShapes(FormatOutputTestCase):
    def run_stream(self, *objs):
        result = self.run_cli(ndjson(*objs), fmt="stream-json", log=self.log_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.decode(), self.read_log()

    def test_text_block_tool_result_is_log_only(self):
        content = [{"type": "text", "text": "Task completed"}]
        screen, log = self.run_stream(tool_call("toolu_2", "Task", {"description": "sub"}),
                                      tool_result("toolu_2", content))
        self.assertIn("[tool result] Task: Task completed", log)
        self.assertNotIn("Task completed", screen)

    def test_text_block_tool_error_is_on_screen(self):
        content = [{"type": "text", "text": "Task failed"}]
        screen, log = self.run_stream(tool_call("toolu_2", "Task", {}), tool_result("toolu_2", content, True))
        self.assertIn("[tool error] Task: Task failed\n", screen)
        self.assertIn("[tool error] Task: Task failed\n", log)

    def test_unknown_tool_id_uses_question_mark(self):
        _, log = self.run_stream(tool_result("toolu_missing", "out"))
        self.assertIn("[tool result] ?: out\n", log)

    def test_failed_result_detail_block(self):
        content = "\n".join(f"line {i}" for i in range(1, 31))
        screen, log = self.run_stream(tool_call("toolu_3", "Bash", {"cmd": "make"}),
                                      tool_result("toolu_3", content, True))
        error_line = "[tool error] Bash: line 1 (+29 more lines)"
        self.assertIn(error_line + "\n", screen)
        self.assertNotIn("    line", screen)
        expected = (
            [error_line]
            + [f"    line {i}" for i in range(2, 7)]
            + ["    ... (9 lines omitted)"]
            + [f"    line {i}" for i in range(16, 31)]
        )
        log_lines = log.splitlines()
        start = log_lines.index(error_line)
        self.assertEqual(log_lines[start:], expected)

    def test_result_cost_and_model_context_window(self):
        usage = {"input_tokens": 100, "cache_creation_input_tokens": 2000, "cache_read_input_tokens": 47000,
                 "output_tokens": 900}
        self.run_stream(
            assistant({"type": "text", "text": "Done."}, usage=usage),
            {"type": "result", "subtype": "success", "is_error": False, "result": "Done.", "total_cost_usd": 0.0123,
             "modelUsage": {"m": {"contextWindow": 200000}}},
        )
        summary = self.read_summary()
        self.assertEqual(summary["cost"], 0.0123)
        self.assertEqual(summary["context_used"], 50000)
        self.assertEqual(summary["context_max"], 200000)
        self.assertEqual(summary["context_pct"], 25)
        self.assertIs(summary["is_error"], False)

    def test_result_error(self):
        screen, _ = self.run_stream(
            assistant({"type": "text", "text": "working"}),
            {"type": "result", "subtype": "error_max_turns", "is_error": True,
             "errors": ["Reached maximum number of turns"], "total_cost_usd": 0.001},
        )
        summary = self.read_summary()
        self.assertIs(summary["is_error"], True)
        self.assertIn("Reached maximum number of turns", summary["error"])
        self.assertIn("[error] Reached maximum number of turns\n", screen)

    def test_no_result_leaves_is_error_null(self):
        self.run_stream(assistant({"type": "text", "text": "hi"}))
        self.assertIsNone(self.read_summary()["is_error"])

    def test_subagent_text_is_displayed_not_scanned(self):
        text = f"sub done {COMPLETE}"
        screen, _ = self.run_stream(assistant({"type": "text", "text": text}, parent="toolu_x"))
        self.assertIn(text, screen)
        summary = self.read_summary()
        self.assertIsNone(summary["signal"])
        self.assertEqual(summary["response_chars"], 0)

    def test_non_json_line_between_valid_lines(self):
        screen, _ = self.run_stream(
            assistant({"type": "text", "text": "before"}),
            "not json at all",
            assistant({"type": "text", "text": "after"}),
        )
        self.assertEqual(screen, "before\nnot json at all\nafter\n")
        self.assertEqual(self.read_summary()["malformed_lines"], 1)


if __name__ == "__main__":
    unittest.main()
