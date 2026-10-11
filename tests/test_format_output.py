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


if __name__ == "__main__":
    unittest.main()
