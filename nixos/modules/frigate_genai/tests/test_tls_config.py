"""Unit tests for _temporal_tls_config() — mTLS fail-closed with full-chain construction."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Pre-import the module under test by mocking every transitive dependency
# that the test environment does not have installed.
# ---------------------------------------------------------------------------
_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

# No package mocks needed — real frigate_genai modules are available.
# Only mock external deps that aren't installed in the test venv.
_LEAF_MOCKS = [
    "paho", "paho.mqtt", "paho.mqtt.client",
    "PIL", "PIL.Image",
    "boto3",
]
# Make frigate_genai.config export the names worker.py imports
import frigate_genai.config as _cfg
_cfg.TASK_QUEUE = "frigate-genai"
_cfg.FFMPEG_TASK_QUEUE = "frigate-genai-ffmpeg"
_cfg.GEMINI_TASK_QUEUE = "frigate-genai-gemini"
_cfg.OLLAMA_TASK_QUEUE = "frigate-genai-ollama"
_cfg.DEPLOYMENT_NAME = "test-deploy"
_cfg.BUILD_ID = "test-build"
_cfg._SEARCH_CAMERA = "Camera"
_cfg._SEARCH_LABEL = "Label"
_cfg._frigate_url = "http://localhost:5000"

# Now import the real worker module — its transitives resolve to mocks.
# The side-effect modules (logging, http, paho, temporalio) are all mocked.
import frigate_genai.worker as _worker_mod
_temporal_tls_config = _worker_mod._temporal_tls_config



class FakeTLSConfig:
    """Captures constructor kwargs so tests can inspect them."""
    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)


_worker_mod.TLSConfig = FakeTLSConfig
# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TemporalTlsConfigTests(unittest.TestCase):

    # -- TLS disabled ---------------------------------------------------

    @patch.dict(os.environ, {"TEMPORAL_TLS": "false"}, clear=True)
    def test_tls_disabled_returns_none(self):
        self.assertIsNone(_temporal_tls_config())

    @patch.dict(os.environ, {}, clear=True)
    def test_tls_unset_returns_none(self):
        self.assertIsNone(_temporal_tls_config())

    # -- Missing required configuration ---------------------------------

    @patch.dict(os.environ, {"TEMPORAL_TLS": "true"}, clear=True)
    def test_missing_socket_raises(self):
        with self.assertRaises(RuntimeError) as ctx:
            _temporal_tls_config()
        self.assertIn("SPIFFE_ENDPOINT_SOCKET", str(ctx.exception))

    @patch.dict(os.environ, {
        "TEMPORAL_TLS": "true",
        "SPIFFE_ENDPOINT_SOCKET": "unix:///run/spire/socket",
    }, clear=True)
    def test_missing_ca_path_raises(self):
        with self.assertRaises(RuntimeError) as ctx:
            _temporal_tls_config()
        self.assertIn("TEMPORAL_TLS_CA_PATH", str(ctx.exception))

    # -- First-attempt success with full chain --------------------------

    @patch.dict(os.environ, {
        "TEMPORAL_TLS": "true",
        "SPIFFE_ENDPOINT_SOCKET": "unix:///run/spire/socket",
        "TEMPORAL_TLS_CA_PATH": "/etc/certs/ca.crt",
        "TEMPORAL_TLS_SERVER_NAME": "temporal.example.com",
    }, clear=True)
    def test_full_chain_construction(self):
        file_dataset = iter([
            b"-----BEGIN CERTIFICATE-----\nleaf\n-----END CERTIFICATE-----\n",
            b"-----BEGIN CERTIFICATE-----\nbundle\n-----END CERTIFICATE-----\n",
            b"-----BEGIN PRIVATE KEY-----\nkeydata\n-----END PRIVATE KEY-----\n",
            b"-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----\n",
        ])

        mock_handle = MagicMock()
        mock_handle.__enter__ = MagicMock(return_value=mock_handle)

        def _read():
            try:
                return next(file_dataset)
            except StopIteration:
                return b""

        mock_handle.read = _read

        with patch.object(_worker_mod.subprocess, "run") as mock_run, \
             patch.object(_worker_mod.tempfile, "mkdtemp", return_value="/tmp/svid-abc"), \
             patch.object(_worker_mod.shutil, "rmtree") as mock_rmtree, \
             patch("builtins.open", return_value=mock_handle):
            config = _temporal_tls_config()

        mock_run.assert_called_once()
        call_args = mock_run.call_args[0][0]
        self.assertIn("spire-agent", call_args)
        self.assertIn("/tmp/svid-abc", call_args)

        self.assertIn(b"leaf", config.client_cert)
        self.assertIn(b"bundle", config.client_cert)
        self.assertIn(b"keydata", config.client_private_key)
        self.assertIn(b"ca", config.server_root_ca_cert)
        self.assertEqual(config.domain, "temporal.example.com")

        mock_rmtree.assert_called_once_with("/tmp/svid-abc", ignore_errors=True)

    # -- Second-attempt success -----------------------------------------

    @patch.dict(os.environ, {
        "TEMPORAL_TLS": "true",
        "SPIFFE_ENDPOINT_SOCKET": "unix:///run/spire/socket",
        "TEMPORAL_TLS_CA_PATH": "/etc/certs/ca.crt",
    }, clear=True)
    def test_second_attempt_succeeds(self):
        call_count = [0]

        def _run_side_effect(*args, **kwargs):
            call_count[0] += 1
            if call_count[0] == 1:
                raise OSError("spire-agent: connection refused")

        file_dataset = iter([
            b"leaf-cert\n", b"bundle-cert\n", b"key-data\n", b"ca-cert\n",
        ])

        mock_handle = MagicMock()
        mock_handle.__enter__ = MagicMock(return_value=mock_handle)

        def _read():
            try:
                return next(file_dataset)
            except StopIteration:
                return b""

        mock_handle.read = _read

        with patch.object(_worker_mod.subprocess, "run", side_effect=_run_side_effect), \
             patch.object(_worker_mod.tempfile, "mkdtemp") as mock_mkdtemp, \
             patch.object(_worker_mod.shutil, "rmtree") as mock_rmtree, \
             patch.object(_worker_mod.time, "sleep") as mock_sleep, \
             patch("builtins.open", return_value=mock_handle):
            mock_mkdtemp.side_effect = ["/tmp/svid-1", "/tmp/svid-2"]
            config = _temporal_tls_config()

        self.assertIsNotNone(config)
        self.assertEqual(call_count[0], 2)
        mock_sleep.assert_called_once_with(5)
        self.assertEqual(mock_rmtree.call_count, 2)

    # -- Exhausted retries ----------------------------------------------

    @patch.dict(os.environ, {
        "TEMPORAL_TLS": "true",
        "SPIFFE_ENDPOINT_SOCKET": "unix:///run/spire/socket",
        "TEMPORAL_TLS_CA_PATH": "/etc/certs/ca.crt",
    }, clear=True)
    def test_three_failures_raises(self):
        with patch.object(_worker_mod.subprocess, "run",
                          side_effect=OSError("spire-agent: connection refused")) as mock_run, \
             patch.object(_worker_mod.tempfile, "mkdtemp", return_value="/tmp/svid-fail"), \
             patch.object(_worker_mod.shutil, "rmtree") as mock_rmtree, \
             patch.object(_worker_mod.time, "sleep") as mock_sleep:
            with self.assertRaises(RuntimeError) as ctx:
                _temporal_tls_config()

        self.assertIn("3 attempts", str(ctx.exception))
        self.assertEqual(mock_run.call_count, 3)
        self.assertEqual(mock_sleep.call_count, 2)
        self.assertEqual(mock_rmtree.call_count, 3)


if __name__ == "__main__":
    unittest.main()
