"""Unit tests for the --all export helpers in analyze_jobs.py:
- parse_agent_stats (memo string flattening)
- decode_payload (Temporal payload decoding, memo guard)
- _event_id_from_summary (event id resolution incl. re-run suffix)
- write_all_csv (25-column export contract)

analyze_jobs.py imports only stdlib, so no stubs are needed.
"""

import base64
import csv
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.analyze_jobs import (
    ALL_CSV_COLUMNS,
    WorkflowSummary,
    _event_id_from_summary,
    decode_payload,
    parse_agent_stats,
    write_all_csv,
)


def _summary(workflow_id="genai-123", **kw) -> WorkflowSummary:
    base = dict(
        workflow_id=workflow_id,
        run_id="run-1",
        workflow_type="GenAIWorkflow",
        status="WORKFLOW_EXECUTION_STATUS_COMPLETED",
        start_time="2026-08-01T00:00:00Z",
        close_time="2026-08-01T00:00:30Z",
        task_queue="genai-tasks",
        history_length=10,
    )
    base.update(kw)
    return WorkflowSummary(**base)


class TestParseAgentStats(unittest.TestCase):
    def test_full_memo(self):
        memo = {
            "AgentTurns": "turns=3 low=0 high=0 max=1 transcode=0",
            "AgentTokens": "in=10059 out=159 cached=2002",
            "AgentConfidence": "high",
            "AgentSummary": "Turn 1: look\nset_description: done",
        }
        stats = parse_agent_stats(memo)
        self.assertEqual(stats["turns"], "3")
        self.assertEqual(stats["turns_low"], "0")
        self.assertEqual(stats["turns_high"], "0")
        self.assertEqual(stats["turns_max"], "1")
        self.assertEqual(stats["turns_transcode"], "0")
        self.assertEqual(stats["tokens_in"], "10059")
        self.assertEqual(stats["tokens_out"], "159")
        self.assertEqual(stats["tokens_cached"], "2002")
        self.assertEqual(stats["confidence"], "high")
        self.assertEqual(stats["agent_summary"], "Turn 1: look\nset_description: done")

    def test_empty_memo(self):
        stats = parse_agent_stats({})
        self.assertEqual(stats, {
            "turns": "", "turns_low": "", "turns_high": "", "turns_max": "",
            "turns_transcode": "", "tokens_in": "", "tokens_out": "",
            "tokens_cached": "", "confidence": "", "agent_summary": "",
        })

    def test_malformed_turns_missing_keys(self):
        memo = {"AgentTurns": "turns=2 low=1"}
        stats = parse_agent_stats(memo)
        self.assertEqual(stats["turns"], "2")
        self.assertEqual(stats["turns_low"], "1")
        self.assertEqual(stats["turns_high"], "")
        self.assertEqual(stats["turns_max"], "")
        self.assertEqual(stats["turns_transcode"], "")


class TestDecodePayload(unittest.TestCase):
    def test_json_plain_payload_decodes_to_string(self):
        # Temporal stores memo strings as base64(json.dumps(value)).
        data_b64 = base64.b64encode(
            json.dumps("turns=2 low=1").encode("utf-8")
        ).decode("utf-8")
        payload = {
            "metadata": {
                "encoding": base64.b64encode(b"json/plain").decode("utf-8"),
            },
            "data": data_b64,
        }
        self.assertEqual(decode_payload(payload), "turns=2 low=1")


class TestEventIdFromSummary(unittest.TestCase):
    def test_memo_event_id_wins(self):
        s = _summary(memo={"event_id": "999.123-abcd"})
        self.assertEqual(_event_id_from_summary(s), "999.123-abcd")

    def test_re_run_suffix_stripped(self):
        s = _summary(workflow_id="genai-1786232489.794502-zg5581-re-1786233535302")
        self.assertEqual(_event_id_from_summary(s), "1786232489.794502-zg5581")

    def test_plain_prefix_stripped(self):
        s = _summary(workflow_id="genai-1786232489.794502-zg5581")
        self.assertEqual(_event_id_from_summary(s), "1786232489.794502-zg5581")


class TestWriteAllCsv(unittest.TestCase):
    def test_25_column_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            s = _summary(
                memo={
                    "AgentTurns": "turns=3 low=0 high=0 max=1 transcode=0",
                    "AgentTokens": "in=10059 out=159 cached=2002",
                    "AgentConfidence": "high",
                },
                search_attributes={
                    "Camera": "cam03",
                    "Label": "dog",
                    "Model": "gemini/gemini-2.5-flash-lite",
                    "Duration": 1145,
                    "ToolFailures": 2,
                    "Transcode": 1,
                    "Confidence": "high",
                },
            )
            write_all_csv([s], {"genai-123": "No dog detected."}, out)
            csv_file = out / "temporal_all_workflows.csv"
            lines = csv_file.read_text().strip().splitlines()
            self.assertEqual(len(lines), 2)
            header = lines[0].split(",")
            self.assertEqual(header, ALL_CSV_COLUMNS)
            self.assertEqual(len(header), 25)
            row = dict(zip(header, next(csv.reader([lines[1]]))))
            self.assertEqual(row["workflow_id"], "genai-123")
            self.assertEqual(row["workflow_type"], "GenAIWorkflow")
            self.assertEqual(row["status"], "WORKFLOW_EXECUTION_STATUS_COMPLETED")
            self.assertEqual(row["duration_seconds"], "30.0")
            self.assertEqual(row["camera"], "cam03")
            self.assertEqual(row["label"], "dog")
            self.assertEqual(row["model"], "gemini/gemini-2.5-flash-lite")
            self.assertEqual(row["event_duration_seconds"], "1145")
            self.assertEqual(row["tool_failures"], "2")
            self.assertEqual(row["transcode"], "1")
            self.assertEqual(row["confidence"], "high")
            self.assertEqual(row["turns"], "3")
            self.assertEqual(row["tokens_in"], "10059")
            self.assertEqual(row["tokens_out"], "159")
            self.assertEqual(row["tokens_cached"], "2002")
            self.assertEqual(row["description"], "No dog detected.")

    def test_summary_json_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            s = _summary(
                memo={
                    "AgentTurns": "turns=2 low=0",
                    "AgentTokens": "in=5 out=1",
                },
            )
            write_all_csv([s], {}, out)
            summary = json.loads((out / "temporal_summary.json").read_text())
            self.assertEqual(summary["total_workflows"], 1)
            self.assertEqual(summary["by_status"], {"COMPLETED": 1})
            self.assertEqual(summary["completed_roots"]["count"], 1)
            self.assertEqual(summary["completed_roots"]["mean_turns"], 2.0)
            self.assertEqual(summary["completed_roots"]["median_turns"], 2.0)
            self.assertEqual(summary["completed_roots"]["mean_tokens_in"], 5.0)
            self.assertEqual(summary["completed_roots"]["mean_tokens_out"], 1.0)
