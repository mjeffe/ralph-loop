#!/usr/bin/env python3
"""Turn an agent CLI's output stream into readable screen/log lines and a summary JSON file.

Usage: python3 lib/format_output.py --format FORMAT --summary PATH [--log PATH] < agent.ndjson

See specs/process/output-pipeline-python.md for the full contract.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

MAX_CHARS = 200
DETAIL_MAX_LINES = 20
DETAIL_HEAD_LINES = 5
DETAIL_TAIL_LINES = 15

SIGNAL_COMPLETE = "<promise>COMPLETE</promise>"
SIGNAL_REPLAN = "<promise>REPLAN</promise>"

TOOL_SUMMARY_KEYS = (
    "path", "file_path", "cmd", "command", "pattern", "filePattern", "query", "url", "description", "prompt",
)


def truncate(value: str) -> str:
    return value[:MAX_CHARS]


def content_lines(content) -> list[str]:
    """Non-blank lines of tool result content given as a string or a list of text blocks."""
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text") or ""))
            elif isinstance(block, str):
                parts.append(block)
        content = "\n".join(parts)
    elif content is None:
        content = ""
    elif not isinstance(content, str):
        content = json.dumps(content, separators=(",", ":"))
    return [line for line in content.splitlines() if line.strip()]


class Processor:
    """Base processor: stream loop, JSON parsing, recovery, emit helpers, summary."""

    name = ""

    def __init__(self, log_file=None):
        self.log_file = log_file
        self.stdout_broken = False
        self.tool_names: dict[str, str] = {}
        self.seen_complete = False
        self.seen_replan = False
        self.response_chars = 0
        self.is_error: bool | None = None
        self.error_message: str | None = None
        self.context_used: int | None = None
        self.context_max: int | None = None
        self.cost: float | None = None
        self.malformed_lines = 0

    # -- stream loop -----------------------------------------------------

    def run(self, stream) -> None:
        for line_no, raw in enumerate(stream, start=1):
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            if not line.strip():
                continue
            try:
                self.process_line(line)
            except Exception as exc:  # noqa: BLE001 - one bad line must not stop the stream
                self.malformed_lines += 1
                sys.stderr.write(f"format_output: skipped line {line_no}: {exc}\n")
                sys.stderr.flush()

    def process_line(self, line: str) -> None:
        try:
            obj = json.loads(line)
        except ValueError:
            obj = None
        if not isinstance(obj, dict):
            self.malformed_lines += 1
            self.write(line)
            return
        self.handle(obj)

    def handle(self, obj: dict) -> None:
        raise NotImplementedError

    # -- writer ----------------------------------------------------------

    def write(self, text: str, log_only: bool = False) -> None:
        if not log_only and not self.stdout_broken:
            try:
                sys.stdout.write(text + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                self.stdout_broken = True
                devnull = os.open(os.devnull, os.O_WRONLY)
                os.dup2(devnull, sys.stdout.fileno())
                os.close(devnull)
        if self.log_file is not None:
            self.log_file.write(text + "\n")
            self.log_file.flush()

    # -- emit helpers ----------------------------------------------------

    def text(self, text: str) -> None:
        """Assistant response text: the only signal-eligible output."""
        if not text:
            return
        self.response_chars += len(text)
        if SIGNAL_COMPLETE in text:
            self.seen_complete = True
        if SIGNAL_REPLAN in text:
            self.seen_replan = True
        self.write(text)

    def thinking(self, text: str) -> None:
        if text:
            self.write(f"[thinking] {text}")

    def tool(self, name: str, tool_input, call_id: str | None = None) -> None:
        name = name or "?"
        if call_id:
            self.tool_names[call_id] = name
        summary = None
        if isinstance(tool_input, dict):
            for key in TOOL_SUMMARY_KEYS:
                value = tool_input.get(key)
                if value not in (None, ""):
                    summary = value if isinstance(value, str) else json.dumps(value, separators=(",", ":"))
                    break
        if summary is None:
            summary = json.dumps(tool_input, separators=(",", ":"))
        summary = summary.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
        self.write(f"[tool] {name}: {truncate(summary)}")

    def tool_result(self, content, is_error: bool, call_id: str | None = None, name: str | None = None) -> None:
        name = name or self.tool_names.get(call_id or "", "?")
        lines = content_lines(content)
        if lines:
            first = truncate(lines[0])
            if len(lines) > 1:
                first += f" (+{len(lines) - 1} more lines)"
        else:
            first = "(no output)"
        if not is_error:
            self.write(f"[tool result] {name}: {first}", log_only=True)
            return
        self.write(f"[tool error] {name}: {first}")
        rest = lines[1:]
        if len(rest) > DETAIL_MAX_LINES:
            omitted = len(rest) - DETAIL_HEAD_LINES - DETAIL_TAIL_LINES
            rest = rest[:DETAIL_HEAD_LINES] + [f"... ({omitted} lines omitted)"] + rest[-DETAIL_TAIL_LINES:]
        for line in rest:
            self.write(f"    {line}", log_only=True)

    def error(self, message: str) -> None:
        self.write(f"[error] {message}")

    # -- summary ---------------------------------------------------------

    def summary(self) -> dict:
        signal = None
        if self.seen_complete:
            signal = "COMPLETE"
        elif self.seen_replan:
            signal = "REPLAN"
        context_pct = None
        if self.context_used is not None and self.context_max:
            context_pct = round(self.context_used * 100 / self.context_max)
        return {
            "format": self.name,
            "signal": signal,
            "response_chars": self.response_chars,
            "is_error": self.is_error,
            "error": self.error_message,
            "context_used": self.context_used,
            "context_max": self.context_max,
            "context_pct": context_pct,
            "cost": self.cost,
            "malformed_lines": self.malformed_lines,
        }


class TextProcessor(Processor):
    """Plain-text passthrough: every non-blank line is displayed and signal-eligible."""

    name = "text"

    def process_line(self, line: str) -> None:
        self.text(line)


class StreamJsonProcessor(Processor):
    """Claude Code / amp `--output-format stream-json` events."""

    name = "stream-json"

    def handle(self, obj: dict) -> None:
        kind = obj.get("type")
        message = obj.get("message") or {}
        if kind == "assistant":
            self.handle_assistant(message, top_level=obj.get("parent_tool_use_id") is None)
        elif kind == "user":
            for block in message.get("content") or []:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    self.tool_result(block.get("content"), block.get("is_error") is True, block.get("tool_use_id"))
        elif kind == "result":
            self.handle_result(obj)

    def handle_assistant(self, message: dict, top_level: bool) -> None:
        for block in message.get("content") or []:
            if not isinstance(block, dict):
                continue
            block_type = block.get("type")
            if block_type == "thinking":
                self.thinking(block.get("thinking") or "")
            elif block_type == "text":
                if top_level:
                    self.text(block.get("text") or "")
                elif block.get("text"):
                    self.write(block["text"])
            elif block_type == "tool_use":
                self.tool(block.get("name"), block.get("input"), block.get("id"))
        usage = message.get("usage")
        if top_level and isinstance(usage, dict):
            keys = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
            self.context_used = sum(usage.get(key) or 0 for key in keys)
            if usage.get("max_tokens"):
                self.context_max = usage["max_tokens"]

    def handle_result(self, obj: dict) -> None:
        if isinstance(obj.get("is_error"), bool):
            self.is_error = obj["is_error"]
        if self.is_error:
            errors = obj.get("errors")
            if errors:
                self.error_message = "; ".join(str(e) for e in errors)
            else:
                self.error_message = str(obj.get("error") or obj.get("subtype") or "unknown error")
            self.error(self.error_message)
        if obj.get("total_cost_usd") is not None:
            self.cost = obj["total_cost_usd"]
        windows = [
            model.get("contextWindow") for model in (obj.get("modelUsage") or {}).values()
            if isinstance(model, dict) and model.get("contextWindow")
        ]
        if windows and self.context_max is None:
            self.context_max = max(windows)


FORMATS = {
    "text": TextProcessor,
    "stream-json": StreamJsonProcessor,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Format an agent output stream and write a summary JSON file.")
    parser.add_argument("--format", required=True, choices=sorted(FORMATS), help="stream schema of stdin")
    parser.add_argument("--summary", required=True, metavar="PATH", help="summary JSON output path")
    parser.add_argument("--log", metavar="PATH", help="file to append the display and log-only detail to")
    args = parser.parse_args(argv)

    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    log_file = None
    if args.log:
        try:
            log_file = open(args.log, "a", encoding="utf-8", errors="replace")
        except OSError as exc:
            sys.stderr.write(f"format_output: cannot open log {args.log}: {exc}\n")
            return 1

    processor = FORMATS[args.format](log_file)
    status = 0
    try:
        processor.run(sys.stdin.buffer)
    finally:
        try:
            with open(args.summary, "w", encoding="utf-8") as fh:
                json.dump(processor.summary(), fh, indent=2)
                fh.write("\n")
        except OSError as exc:
            sys.stderr.write(f"format_output: cannot write summary {args.summary}: {exc}\n")
            status = 1
        if log_file is not None:
            log_file.close()
    return status


if __name__ == "__main__":
    sys.exit(main())
