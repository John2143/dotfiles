"""MQTT client and workflow-start helpers for frigate-genai."""

import asyncio
import json
import logging
import os
import time

import paho.mqtt.client as mqtt
from temporalio.client import Client
from temporalio.common import TypedSearchAttributes, SearchAttributePair

from frigate_genai.config import TASK_QUEUE, _SEARCH_CAMERA, _SEARCH_LABEL
from frigate_genai.s3_helpers import _s3_get, _s3_put, _stats
from frigate_genai.worker import _temporal_client, _main_event_loop

log = logging.getLogger("frigate-genai-sidecar")


def _start_workflow_sync(event: dict) -> None:
    """Schedule a Temporal workflow start from a non-async context (MQTT thread)."""
    event_id = event.get("id", "unknown")
    camera = event.get("camera", "")
    label = event.get("label", "")

    loop = _main_event_loop
    if loop is None:
        log.warning("Event loop not yet initialized, dropping event %s", event_id)
        return

    async def _start():
        client = _temporal_client
        if client is None:
            log.error("Temporal client not initialized, dropping event %s", event_id)
            return

        try:
            input_data = _build_workflow_input(event)
            if input_data is None:
                return  # event paused
            await client.start_workflow(
                "GenAIWorkflow",
                input_data,
                id=f"genai-{event_id}",
                task_queue=TASK_QUEUE,
                search_attributes=TypedSearchAttributes([
                    SearchAttributePair(_SEARCH_CAMERA, camera),
                    SearchAttributePair(_SEARCH_LABEL, label),
                ]),
                memo={"event_id": event_id, "camera": camera, "label": label,
                      "duration": int(event.get("end_time", event.get("start_time", 0)) - event.get("start_time", 0))})
            log.info("Workflow started: genai-%s (%s/%s)", event_id, camera, label)
        except Exception as e:
            if "already" in str(e).lower() or "started" in str(e).lower():
                log.debug("Workflow genai-%s already exists (dedup)", event_id)
            else:
                log.exception("Failed to start workflow genai-%s", event_id)

    asyncio.run_coroutine_threadsafe(_start(), loop)


def _build_workflow_input(event: dict) -> dict | None:
    """Build the workflow input dict from an MQTT event. Model selection
    happens in the Temporal workflow via select_model_activity.
    Returns None if the event should be skipped (paused globally or per-label).
    """
    label = event.get("label", "")
    if _s3_get("events/_paused/genai") is not None:
        log.info("Global pause active, skipping event %s (%s/%s)", event.get("id"), event.get("camera"), label)
        return None
    if label and _s3_get(f"events/_paused/genai-{label}") is not None:
        log.info("Label pause active for '%s', skipping event %s", label, event.get("id"))
        return None
    input_data = {
        "data_box": event.get("data", {}).get("box"),
        "event_id": event["id"],
        "camera": event.get("camera", ""),
        "label": label,
        "start_time": event.get("start_time", 0),
        "end_time": event.get("end_time", event.get("start_time", 0)),
        "prompts_path": "/var/lib/frigate-genai-sidecar/prompts.json",
        "provider_path": "/var/lib/frigate-genai-sidecar/provider.json",
        "paused-ollama": _s3_get("events/_paused/ollama") is not None,
        "agentic": True,
    }
    return input_data


def build_mqtt_client(loop: asyncio.AbstractEventLoop) -> mqtt.Client:
    """Create and configure the MQTT client. Starts workflows directly via Temporal."""

    def on_connect(client, userdata, flags, reason_code, properties=None):
        if reason_code == 0:
            log.info("MQTT connected, subscribing to frigate/events")
            _stats["mqtt_connected"] = True
            client.subscribe("frigate/events")
        else:
            log.error("MQTT connection failed: rc=%d", reason_code)

    def on_disconnect(client, userdata, flags, reason_code, properties=None):
        _stats["mqtt_connected"] = False
        if reason_code != 0:
            log.warning("MQTT disconnected: rc=%d", reason_code)

    def on_message(client, userdata, msg):
        log.debug("MQTT message on %s: %s", msg.topic, msg.payload[:200])
        try:
            payload = json.loads(msg.payload.decode())
            event_type = payload.get("type", "")
            after = payload.get("after", {})
            if not after.get("id"):
                return
            eid, camera, label = after["id"], after.get("camera"), after.get("label")

            if event_type == "end" and after.get("has_clip"):
                log.info("End event: %s (%s/%s)", eid, camera, label)
                _start_workflow_sync(after)
                _stats["events_processed"] += 1
                _stats["last_event"] = eid
                _s3_put("events/_stats.json", json.dumps(_stats).encode())

            elif event_type == "update":
                before = payload.get("before", {})
                def _desc(e):
                    return ((e.get("data") or {}).get("description") or e.get("description") or "").strip().lower()
                if _desc(after) == "redo" and _desc(before) != "redo":
                    after["has_clip"] = True
                    log.info("Redo trigger: %s (%s/%s)", eid, camera, label)
                    _start_workflow_sync(after)
                    _stats["events_processed"] += 1
                    _stats["last_event"] = eid
                    _s3_put("events/_stats.json", json.dumps(_stats).encode())
        except json.JSONDecodeError:
            log.debug("Non-JSON MQTT message on %s", msg.topic)
        except Exception as e:
            log.exception("Error in MQTT message handler")

    mqtt_host = os.environ.get("MQTT_HOST", "localhost")
    mqtt_port = int(os.environ.get("MQTT_PORT", "1883"))
    mqtt_user = os.environ.get("MQTT_USER", "")
    mqtt_pass = os.environ.get("MQTT_PASSWORD", "")

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    if mqtt_user:
        client.username_pw_set(mqtt_user, mqtt_pass)
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    while True:
        try:
            client.connect(mqtt_host, mqtt_port, 60)
            break
        except Exception as e:
            log.warning("MQTT connection failed, retrying in 5s...")
            time.sleep(5)

    client.loop_start()
    return client
