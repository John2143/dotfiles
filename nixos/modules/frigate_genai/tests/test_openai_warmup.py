"""Regression test for the cold-start pydantic schema race (bug B).

Background: openai builds its response models with
`defer_build=DEFER_PYDANTIC_BUILD` (default "true"), read once at its first
import. Deferred models carry a `MockCoreSchema` until first use, and the
first `client.chat` access lazily imports `openai.resources.chat`, which
rebuilds `ParsedChatCompletion[object]` (openai/lib/streaming/chat/_types.py).
On fresh gemini/ollama pods that first use happened concurrently on activity
threads (`_run_with_heartbeat`), failing turns with
`TypeError: 'MockCoreSchema' object does not support item assignment`; since
`TypeError` is non-retryable in `_GENAI_RETRY`, the whole workflow failed.

The fix: `frigate_genai.__main__` defaults DEFER_PYDANTIC_BUILD to "false"
before anything imports openai, and `worker.async_main` calls
`warm_openai_client()` on the main thread at startup. This test checks that,
going through the real entrypoint, every model on the turn's response path has
a complete schema once the warm-up returns.

The check runs in a subprocess: the env var only matters at openai's first
import, and this test process may already have imported openai via other
test modules.
"""

import json
import os
import subprocess
import sys
import unittest

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

# The streaming-types module is read from sys.modules rather than imported, so
# the probe itself cannot do the import that warm_openai_client must trigger.
_PROBE = """
import json
import sys

import frigate_genai.__main__  # sets the env default; does not run main()
from frigate_genai.activities.genai_turn import warm_openai_client

returned = warm_openai_client()

from openai.types import CompletionUsage
from openai.types.chat import ChatCompletion, ChatCompletionMessage

streaming_types = sys.modules.get("openai.lib.streaming.chat._types")
print(json.dumps({
    "returned": returned,
    "ChatCompletion": ChatCompletion.__pydantic_complete__,
    "ChatCompletionMessage": ChatCompletionMessage.__pydantic_complete__,
    "CompletionUsage": CompletionUsage.__pydantic_complete__,
    "ParsedChatCompletion[object]": (
        None if streaming_types is None
        else streaming_types.ParsedChatCompletionSnapshot.__pydantic_complete__
    ),
}))
"""


class WarmOpenaiClientTests(unittest.TestCase):

    def test_entrypoint_warmup_completes_response_schemas(self):
        env = dict(os.environ)
        env.pop("DEFER_PYDANTIC_BUILD", None)
        env["PYTHONPATH"] = _PARENT
        env["PYTHONDONTWRITEBYTECODE"] = "1"

        proc = subprocess.run(
            [sys.executable, "-c", _PROBE],
            env=env, capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(proc.stdout.strip().splitlines()[-1])

        self.assertEqual(result, {
            "returned": True,
            "ChatCompletion": True,
            "ChatCompletionMessage": True,
            "CompletionUsage": True,
            "ParsedChatCompletion[object]": True,
        })


if __name__ == "__main__":
    unittest.main()
