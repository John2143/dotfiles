"""AgentSessionWorkflow -- self-contained agent turn loop as Temporal child workflow."""

import asyncio
from datetime import timedelta

from temporalio import workflow
from temporalio.exceptions import ApplicationError
from temporalio.workflow import ParentClosePolicy

from frigate_genai.config import _GENAI_RETRY, _ACTIVITY_RETRY
from frigate_genai.activities.genai_turn import run_genai_turn_activity
from frigate_genai.activities.tool_apply import apply_tool_messages_activity
from frigate_genai.tools import _TOOL_ACTIVITIES, _get_tool_queue
from frigate_genai.tools.schemas import (
    _tool_find_keyframes_schema, _tool_frame_diff_schema, _tool_tag_image_schema,
    _tool_get_snapshot_schema, _tool_show_frame_schema, _tool_crop_schema,
    _tool_transcode_schema, _tool_compact_schema, _tool_set_description_schema,
    _tool_upscale_schema, _tool_spawn_schema, _tool_join_schema,
    _tool_close_subagent_schema, _tool_send_ipc_schema, _tool_wait_ipc_schema,
)


def _resolve_image_refs(refs: list[str], agent_dir: str, frames_dir: str = "") -> tuple[list[str], list[str]]:
    """Convert image refs (crop://N, frame://N) to S3 keys under agent_dir.
    Returns (resolved_keys, error_refs). Never raises.
    Supports crop://<non-negative int> and frame://<non-negative int>.
    Strips @<suffix> before parsing. Silently ignores unknown schemes.
    When frames_dir is provided, it is used for frame:// key resolution instead
    of deriving from agent_dir (important for nested subagents).
    """
    base = agent_dir.rstrip("/")
    parent = "/".join(base.split("/")[:-1]) + "/"
    keys = []
    errors = []
    for ref in refs:
        if ref.startswith("crop://"):
            idx_str = ref[len("crop://"):].split("@")[0]
            try:
                idx = int(idx_str)
                k = f"{base}/crop_{idx:03d}.jpg"
                keys.append(k)
            except ValueError:
                errors.append(ref)
        elif ref.startswith("frame://"):
            idx_str = ref[len("frame://"):].split("@")[0]
            try:
                idx = int(idx_str)
                if frames_dir:
                    k = f"{frames_dir}/frames/frame_{idx:03d}.jpg"
                else:
                    k = f"{parent}frames/frame_{idx:03d}.jpg"
                keys.append(k)
            except ValueError:
                errors.append(ref)
    return keys, errors
def _format_spawn_findings(findings: list[dict]) -> str:
    """Format subagent findings into a parent-readable message with synthesis."""
    successes = [f for f in findings if not f.get("error")]
    failures = [f for f in findings if f.get("error")]

    lines = []
    lines.append(f"JOIN RESULTS: {len(successes)} of {len(findings)} subagents completed successfully.")

    high = [f for f in successes if f.get("confidence") == "high"]
    if high:
        lines.append(f"\nHIGH confidence findings ({len(high)}):")
        for i, f in enumerate(high):
            lines.append(f"  [{i+1}] {f.get('findings', '')[:200]}")

    medium = [f for f in successes if f.get("confidence") == "medium"]
    if medium:
        lines.append(f"\nMEDIUM confidence findings ({len(medium)}):")
        for i, f in enumerate(medium):
            lines.append(f"  [{i+1}] {f.get('findings', '')[:200]}")

    low = [f for f in successes if f.get("confidence") not in ("high", "medium")]
    if low:
        lines.append(f"\nUNSURE / NOTHING FOUND ({len(low)}):")
        for i, f in enumerate(low):
            lines.append(f"  [{i+1}] [{f.get('confidence','?')}] {f.get('findings', '')[:200]}")

    if failures:
        lines.append(f"\nFAILED subagents ({len(failures)}):")
        for i, f in enumerate(failures):
            lines.append(f"  [{i+1}] {f['error'][:200]}")

    lines.append("\n--- END JOIN RESULTS ---")
    return "\n".join(lines)


def _get_tools_for_depth(depth: int, max_depth: int) -> list[dict]:
    """Return tool schemas available at given depth. Root gets set_description + spawn + join.
    Subagents get close_subagent instead of set_description. Deepest agents lose spawn/join."""
    base = [
        _tool_find_keyframes_schema(), _tool_frame_diff_schema(), _tool_tag_image_schema(),
        _tool_show_frame_schema(), _tool_crop_schema(), _tool_transcode_schema(),
        _tool_upscale_schema(),
    ]
    if depth == 0:
        return base + [
            _tool_get_snapshot_schema(), _tool_compact_schema(),
            _tool_set_description_schema(),
            _tool_spawn_schema(), _tool_join_schema(),
            _tool_send_ipc_schema(), _tool_wait_ipc_schema(),
        ]
    elif depth < max_depth:
        return base + [
            _tool_close_subagent_schema(),
            _tool_spawn_schema(), _tool_join_schema(),
            _tool_send_ipc_schema(), _tool_wait_ipc_schema(),
        ]
    else:
        return base + [
            _tool_close_subagent_schema(),
            _tool_send_ipc_schema(), _tool_wait_ipc_schema(),
        ]


# ── workflow ─────────────────────────────────────────────────────────────────

@workflow.defn
class AgentSessionWorkflow:
    """Self-contained agent turn loop. Reads/writes messages.json via activities.
    Can be run as child workflow of GenAIWorkflow or recursively.
    Supports bidirectional IPC via Signals/Updates with token-based routing."""

    def __init__(self):
        # ── IPC identity ──────────────────────────────────────────────────
        self.ipc_token: str = ""
        self.parent_ipc_token: str | None = None
        self.parent_workflow_id: str | None = None
        self.parent_run_id: str | None = None
        self._parent_handle = None

        # ── IPC state ─────────────────────────────────────────────────────
        self._pending_ipc: list[dict] = []
        self.ipc_inbox: list[dict] = []
        self.ipc_inbox_cursor: int = 0
        self.ipc_seen_ids: list[str] = []
        self.ipc_seq: int = 0
        self.ipc_reply_ready: dict[str, bool] = {}
        self.ipc_any_ready: bool = False
        self.ipc_closed: bool = False

        # ── Child registry: token -> {workflow_id, run_id, handle, status} ──
        self.child_registry: dict[str, dict] = {}

        # ── Counters ──────────────────────────────────────────────────────
        self.ipc_accepted: int = 0
        self.ipc_duplicates: int = 0
        self.ipc_rejected: int = 0

        # ── Spawn/join tracking ───────────────────────────────────────────
        self.spawn_handles: dict[str, list[tuple[dict, object]]] = {}
        self.total_subagents: int = 0
        self._spawn_count: int = 0

    # ── IPC helpers ──────────────────────────────────────────────────────────

    def _format_ipc(self, msg: dict) -> str:
        """Format an IPC message for injection into the conversation as a user message."""
        logical_id = msg.get("from_token", "?").rsplit(":", 1)[-1]
        confidence = msg.get("confidence", "")
        conf_str = f" | {confidence}" if confidence else ""
        return f"[IPC from {logical_id} | {msg.get('kind', '?')}{conf_str}]: {msg.get('content', '')}"

    def _accept_ipc(self, payload: dict) -> str:
        """Single validation/mutation path for IPC Signals and Updates.
        Returns: accepted, duplicate, rejected, closed, inbox_full, buffered."""
        # Buffer if identity not yet initialized
        if not self.ipc_token:
            self._pending_ipc.append(payload)
            return "buffered"

        # Validate IPCMessage
        try:
            from frigate_genai.models import IPCMessage
            msg = IPCMessage.model_validate(payload)
        except Exception:
            self.ipc_rejected += 1
            return "rejected"

        msg_dict = msg.model_dump()
        message_id = msg_dict["message_id"]

        # Check to_token matches
        if msg_dict["to_token"] != self.ipc_token:
            self.ipc_rejected += 1
            return "rejected"

        # Check from_token is parent or registered direct child
        from_token = msg_dict["from_token"]
        if from_token != self.parent_ipc_token and from_token not in self.child_registry:
            self.ipc_rejected += 1
            return "rejected"

        # Check closed
        if self.ipc_closed:
            return "closed"

        # Deduplicate
        if message_id in self.ipc_seen_ids:
            self.ipc_duplicates += 1
            return "duplicate"

        # Check inbox full
        if len(self.ipc_inbox) >= 100:
            self.ipc_rejected += 1
            return "inbox_full"

        # Accept
        self.ipc_inbox.append(msg_dict)
        self.ipc_seen_ids.append(message_id)
        self.ipc_accepted += 1

        # Trim dedupe window
        while len(self.ipc_seen_ids) > 200:
            self.ipc_seen_ids.pop(0)

        # Signal waiters
        self.ipc_any_ready = True
        self.ipc_reply_ready[message_id] = True
        if msg_dict.get("reply_to"):
            self.ipc_reply_ready[msg_dict["reply_to"]] = True

        return "accepted"

    # ── IPC handlers ─────────────────────────────────────────────────────────

    @workflow.signal(name="receive_ipc")
    async def receive_ipc(self, payload: dict) -> None:
        """Fire-and-forget IPC signal endpoint."""
        self._accept_ipc(payload)

    @workflow.update(name="receive_ipc_update")
    async def receive_ipc_update(self, payload: dict) -> dict:
        """External acknowledgement endpoint for IPC delivery."""
        status = self._accept_ipc(payload)
        return {"status": status, "message_id": payload.get("message_id", "")}

    @workflow.query(name="ipc_status")
    def ipc_status(self) -> dict:
        """Read-only IPC state snapshot (no message content)."""
        return {
            "ipc_token": self.ipc_token,
            "inbox_count": len(self.ipc_inbox),
            "children": {t: d.get("status", "?") for t, d in self.child_registry.items()},
            "waiter_count": len(self.ipc_reply_ready),
            "accepted": self.ipc_accepted,
            "duplicates": self.ipc_duplicates,
            "rejected": self.ipc_rejected,
        }

    # ── IPC tool dispatch ────────────────────────────────────────────────────

    async def _dispatch_send_ipc(self, tc: dict, outcomes: list[dict]) -> None:
        """Handle send_ipc tool call. Resolves route and delivers signal."""
        from frigate_genai.models import SendIPCArgs

        try:
            args = SendIPCArgs.model_validate(tc.get("args", {}))
        except Exception as e:
            outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": f"send_ipc invalid: {e}"}]})
            return

        # Validate reply_to constraint
        if args.kind != "reply" and args.reply_to is not None:
            outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": "invalid_reply: reply_to is only valid for replies"}]})
            return

        # Resolve route
        to_token = args.to_token
        is_parent = (to_token == self.parent_ipc_token)
        is_child = (to_token in self.child_registry)

        if not is_parent and not is_child:
            outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": f"stale_recipient: token {to_token} not registered"}]})
            return

        # Increment sequence
        self.ipc_seq += 1
        message_id = f"{self.ipc_token}:{self.ipc_seq}"

        payload = {
            "message_id": message_id,
            "from_token": self.ipc_token,
            "to_token": to_token,
            "kind": args.kind,
            "content": args.content,
            "confidence": args.confidence,
            "reply_to": args.reply_to,
            "seq": self.ipc_seq,
            "created_at": workflow.now().timestamp(),
        }

        # Register waiter if waiting for reply
        if args.wait_for_reply:
            self.ipc_reply_ready[message_id] = False

        # Deliver
        try:
            if is_parent:
                await self._parent_handle.signal("receive_ipc", payload)
            else:
                child_info = self.child_registry[to_token]
                await child_info["handle"].signal("receive_ipc", payload)
        except Exception:
            outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": f"recipient_closed: {to_token}"}]})
            return

        # Wait for reply if requested
        if args.wait_for_reply:
            try:
                await workflow.wait_condition(
                    lambda: self.ipc_reply_ready.get(message_id, False),
                    timeout=timedelta(seconds=args.timeout_seconds),
                )
                # Find reply
                reply_msg = None
                for m in self.ipc_inbox:
                    if m.get("kind") == "reply" and m.get("reply_to") == message_id:
                        reply_msg = m
                        break
                if reply_msg:
                    formatted = self._format_ipc(reply_msg)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": formatted}]})
                else:
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": "timeout: no reply received"}]})
            except asyncio.TimeoutError:
                outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                    "content": "timeout: no reply received"}]})
            finally:
                self.ipc_reply_ready.pop(message_id, None)
        else:
            outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": f"accepted: {message_id}"}]})

    async def _dispatch_wait_ipc(self, tc: dict, outcomes: list[dict]) -> None:
        """Handle wait_ipc tool call. Returns buffered or waits for new messages."""
        from frigate_genai.models import WaitIPCArgs

        try:
            args = WaitIPCArgs.model_validate(tc.get("args", {}))
        except Exception as e:
            outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": f"wait_ipc invalid: {e}"}]})
            return

        if args.message_id:
            # Wait for specific reply
            mid = args.message_id
            try:
                await workflow.wait_condition(
                    lambda: self.ipc_reply_ready.get(mid, False),
                    timeout=timedelta(seconds=args.timeout_seconds),
                )
                replies = [m for m in self.ipc_inbox
                           if m.get("kind") == "reply" and m.get("reply_to") == mid]
                if replies:
                    formatted = "\n\n".join(self._format_ipc(m) for m in replies)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": formatted}]})
                else:
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": "timeout: no messages received"}]})
            except asyncio.TimeoutError:
                outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                    "content": "timeout: no messages received"}]})
        else:
            # Wait for any new messages
            try:
                await workflow.wait_condition(
                    lambda: self.ipc_any_ready,
                    timeout=timedelta(seconds=args.timeout_seconds),
                )
                self.ipc_any_ready = False
                new_msgs = self.ipc_inbox[self.ipc_inbox_cursor:][:20]
                self.ipc_inbox_cursor += len(new_msgs)
                if new_msgs:
                    formatted = "\n\n".join(self._format_ipc(m) for m in new_msgs)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": formatted}]})
                else:
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": "timeout: no messages received"}]})
            except asyncio.TimeoutError:
                outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                    "content": "timeout: no messages received"}]})

    # ── run loop ──────────────────────────────────────────────────────────────

    @workflow.run
    async def run(self, session_input: dict) -> dict:
        msg_path = session_input["msg_path"]
        provider_path = session_input["provider_path"]
        model = session_input["model"]
        event_id = session_input["event_id"]
        camera = session_input["camera"]
        label = session_input["label"]
        max_turns = session_input["max_turns"]
        max_frames = session_input["max_frames"]
        start_time = session_input["start_time"]
        end_time = session_input["end_time"]
        genai_queue = session_input["genai_queue"]
        prompts_path = session_input.get("prompts_path", "")
        depth = session_input.get("depth", 0)
        max_depth = session_input.get("max_depth", 2)

        # ── Initialize IPC identity ───────────────────────────────────────
        wf_info = workflow.info()
        if depth == 0:
            # Root: derive token from current workflow info
            self.ipc_token = f"ipc-v1:{wf_info.workflow_id}:{wf_info.run_id}:root"
        else:
            # Child: use supplied token
            self.ipc_token = session_input.get("ipc_token", "")

        self.parent_ipc_token = session_input.get("parent_ipc_token")
        self.parent_workflow_id = session_input.get("parent_workflow_id")
        if session_input.get("parent_run_id"):
            self.parent_run_id = session_input["parent_run_id"]

        # Create parent handle if parent info present
        if self.parent_workflow_id and self.parent_run_id:
            self._parent_handle = workflow.get_external_workflow_handle_for(
                AgentSessionWorkflow.run,
                workflow_id=self.parent_workflow_id,
                run_id=self.parent_run_id,
            )

        # Replay buffered signals
        if self._pending_ipc:
            pending = list(self._pending_ipc)
            self._pending_ipc.clear()
            for payload in pending:
                self._accept_ipc(payload)

        # ── Turn loop state ───────────────────────────────────────────────
        turn_arg = {
            "msg_path": msg_path,
            "provider_path": provider_path,
            "model": model,
            "event_id": event_id,
            "camera": camera,
            "label": label,
        }

        total_cost = {"prompt": 0, "completion": 0, "cached": 0}
        turns_low = 0
        turns_high = 0
        turns_max = 0
        turns_transcode = 0
        tool_failures = 0
        MAX_CONCURRENT_SPAWNS = 5
        MAX_TOTAL_SUBAGENTS = 20
        trace_entries: list[dict] = []
        description = None
        confidence = None

        for turn in range(max_turns):
            turn_arg["turn_num"] = turn + 1
            turn_arg["max_turns"] = max_turns
            turn_arg["tool_names"] = [t["function"]["name"] for t in _get_tools_for_depth(depth, max_depth)]
            result = await workflow.execute_activity(
                run_genai_turn_activity,
                arg=turn_arg,
                task_queue=genai_queue,
                start_to_close_timeout=timedelta(seconds=300),
                heartbeat_timeout=timedelta(seconds=15),
                retry_policy=_GENAI_RETRY,
            )

            pt = result.get("prompt_tokens", 0)
            ct = result.get("completion_tokens", 0)
            cached = result.get("cached_tokens", 0)
            total_cost["prompt"] += pt
            total_cost["completion"] += ct
            total_cost["cached"] += cached
            trace_entries.append({
                "type": "turn", "turn": turn + 1,
                "prompt_tokens": pt, "completion_tokens": ct,
                "cached": cached > 0,
            })
            workflow.set_current_details(
                f"Turn {turn+1}/{max_turns} | "
                f"tokens: {total_cost['prompt']}+{total_cost['completion']} "
                f"(cached: {total_cost['cached']}) | "
                f"tools: {len(trace_entries)}"
            )

            if result.get("description"):
                description = result["description"]
                confidence = result.get("confidence", "medium")
                trace_entries.append({
                    "type": "tool_call", "name": "set_description",
                    "confidence": confidence,
                    "description": description[:200],
                })
                break

            if result.get("text_only"):
                trace_entries.append({"type": "nudge", "reason": "no_tool_call"})
                continue

            # IPC prefix injection at turn start
            outcomes: list[dict] = []
            ipc_snapshot: list[dict] = []
            if self.ipc_inbox_cursor > 0 or len(self.ipc_inbox) > self.ipc_inbox_cursor:
                # Snapshot claimed messages for persistence
                claimed = self.ipc_inbox[:self.ipc_inbox_cursor] if self.ipc_inbox_cursor > 0 else []
                unclaimed = self.ipc_inbox[self.ipc_inbox_cursor:] if self.ipc_inbox_cursor < len(self.ipc_inbox) else []
                all_ipc = claimed + unclaimed
                for msg in all_ipc:
                    formatted = self._format_ipc(msg)
                    ipc_snapshot.append(msg)
                    outcomes.append({"messages": [{"role": "user", "content": formatted}]})
                # Snapshot-and-swap the inbox so signals during persistence land in new list
                old_inbox = self.ipc_inbox
                self.ipc_inbox = []
                self.ipc_inbox_cursor = 0
                # Persist IPC messages
                if outcomes:
                    try:
                        await workflow.execute_activity(
                            apply_tool_messages_activity,
                            arg={"msg_path": msg_path, "outcomes": list(outcomes)},
                            task_queue=genai_queue,
                            start_to_close_timeout=timedelta(seconds=10),
                            retry_policy=_ACTIVITY_RETRY,
                        )
                        outcomes.clear()
                    except Exception:
                        # Restore snapshot on failure for retry
                        self.ipc_inbox = old_inbox + self.ipc_inbox
                        self.ipc_inbox_cursor = len(old_inbox)

            # Parallel tool dispatch
            handles: list[tuple[dict, dict, object]] = []
            for tc in result.get("tool_calls", []):
                # ── send_ipc handling ─────────────────────────────────────
                if tc["name"] == "send_ipc":
                    await self._dispatch_send_ipc(tc, outcomes)
                    continue

                # ── wait_ipc handling ─────────────────────────────────────
                if tc["name"] == "wait_ipc":
                    await self._dispatch_wait_ipc(tc, outcomes)
                    continue

                # ── spawn handling ────────────────────────────────────────────
                if tc["name"] == "spawn":
                    tasks = tc["args"].get("tasks", [])
                    if self.total_subagents + len(tasks) > MAX_TOTAL_SUBAGENTS:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Subagent limit ({MAX_TOTAL_SUBAGENTS}) reached. Conclude."}]})
                        continue
                    if len(tasks) > MAX_CONCURRENT_SPAWNS:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Max {MAX_CONCURRENT_SPAWNS} subagents per spawn(). Got {len(tasks)}."}]})
                        continue
                    if depth >= max_depth:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Already at max depth ({max_depth}). Cannot spawn further."}]})
                        continue

                    from frigate_genai.workflows.subagent import SubAgentWorkflow
                    self._spawn_count += 1
                    spawn_key = f"spawn_{self._spawn_count:08x}"
                    self.spawn_handles[spawn_key] = []
                    sd = session_input.get("subagent_dir", session_input.get("parent_agent_dir",
                         f"events/{event_id}/agent/"))

                    # ── Validate tasks ─────────────────────────────────────────
                    from frigate_genai.models import SpawnTask
                    validated_tasks = []
                    validation_errors = []
                    for i, task in enumerate(tasks):
                        try:
                            st = SpawnTask.model_validate(task)
                            validated_tasks.append(st)
                        except Exception as e:
                            validation_errors.append(f"  task[{i}]: {e}")
                    if validation_errors:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": "Spawn task validation failed:\n" + "\n".join(validation_errors)}]})
                        continue

                    # ── Resolve image refs ──────────────────────────────────────
                    all_errors: list[str] = []
                    for i, st in enumerate(validated_tasks):
                        _, errs = _resolve_image_refs(st.image_refs, sd, frames_dir=f"events/{event_id}")
                        if errs:
                            all_errors.append(f"  task[{i}]: invalid refs: {errs}")
                    if all_errors:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": "Spawn image_refs resolution failed:\n" + "\n".join(all_errors)}]})
                        continue

                    # ── Derive parent identity for child tokens ────────────────
                    parent_wf_id = wf_info.workflow_id
                    parent_run_id = wf_info.run_id

                    # ── Start child workflows ───────────────────────────────────
                    child_tokens = []
                    for i, st in enumerate(validated_tasks):
                        sub_sd = f"{sd}subagent/s{self.total_subagents + i}/"
                        s3_keys, _ = _resolve_image_refs(st.image_refs, sd, frames_dir=f"events/{event_id}")
                        child_idx = self.total_subagents + i
                        child_token = f"ipc-v1:{parent_wf_id}:{parent_run_id}:s{child_idx}"
                        child_workflow_id = f"{event_id}-{sd.rstrip('/').split('/')[-1]}-{spawn_key}-{i}"
                        agent_dir_name = sd.rstrip("/").split("/")[-1] if sd.rstrip("/").split("/") else "agent"

                        sub_input = {
                            "event_id": event_id, "camera": camera, "label": label,
                            "task": st.task, "image_refs": st.image_refs,
                            "image_s3_keys": s3_keys,
                            "parent_agent_dir": sd, "subagent_dir": sub_sd,
                            "frames_dir": f"events/{event_id}",
                            "provider_path": provider_path, "model": model,
                            "genai_queue": genai_queue,
                            "prompts_path": prompts_path,
                            "start_time": start_time, "end_time": end_time,
                            "depth": depth + 1,
                            "max_depth": max_depth,
                            "max_turns": st.max_turns,
                            "parent_workflow_id": parent_wf_id,
                            "parent_run_id": parent_run_id,
                            "parent_ipc_token": self.ipc_token,
                            "ipc_token": child_token,
                        }
                        handle = await workflow.start_child_workflow(
                            SubAgentWorkflow, arg=sub_input,
                            id=child_workflow_id,
                            task_queue=genai_queue,
                            parent_close_policy=ParentClosePolicy.TERMINATE,
                        )
                        self.spawn_handles[spawn_key].append((tc, handle))
                        self.child_registry[child_token] = {
                            "workflow_id": child_workflow_id,
                            "run_id": handle.first_execution_run_id,
                            "handle": handle,
                            "status": "running",
                        }
                        child_tokens.append(child_token)
                    self.total_subagents += len(validated_tasks)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": f"Spawned {len(validated_tasks)} subagents. Key: {spawn_key}. "
                                   f"Child tokens: {', '.join(child_tokens)}. "
                                   f"Call join(spawn_key='{spawn_key}') to collect results."}]})
                    continue

                # ── join handling ─────────────────────────────────────────────
                if tc["name"] == "join":
                    spawn_key = tc["args"]["spawn_key"]
                    if spawn_key not in self.spawn_handles:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Unknown spawn_key: {spawn_key}"}]})
                        continue

                    # Concurrent join via asyncio.gather
                    pairs = self.spawn_handles[spawn_key]
                    handles_list = [h for _, h in pairs]
                    results = await asyncio.gather(*handles_list, return_exceptions=True)

                    findings = []
                    for (orig_tc, _), sub_result in zip(pairs, results):
                        if isinstance(sub_result, Exception):
                            findings.append({"error": str(sub_result), "task": "unknown"})
                        else:
                            findings.append(dict(sub_result))

                    fmt = _format_spawn_findings(findings)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": fmt}]})
                    del self.spawn_handles[spawn_key]
                    continue

                # ── normal tool dispatch ──────────────────────────────────────
                te = {"type": "tool_call", "name": tc["name"], "args": tc.get("args", {})}
                if tc["name"] not in _TOOL_ACTIVITIES:
                    workflow.logger.warning("Unknown tool: %s", tc["name"])
                    te["error"] = f"Unknown tool: {tc['name']}"
                    trace_entries.append(te)
                    continue

                activity_fn, task_queue = _get_tool_queue(tc["name"], genai_queue)
                retry = _ACTIVITY_RETRY
                if tc["name"] == "transcode":
                    timeout = timedelta(seconds=60)
                elif tc["name"] == "upscale":
                    timeout = timedelta(seconds=180)
                else:
                    timeout = timedelta(seconds=30)

                handle = workflow.start_activity(
                    activity_fn,
                    arg={
                        "msg_path": msg_path,
                        "args": tc.get("args", {}),
                        "event_id": event_id,
                        "max_frames": max_frames,
                        "camera": camera,
                        "start_time": start_time,
                        "end_time": end_time,
                        "provider_path": provider_path,
                        "model": model,
                    },
                    task_queue=task_queue,
                    start_to_close_timeout=timeout,
                    retry_policy=retry,
                )
                handles.append((tc, te, handle))

            if handles:
                for tc, te, handle in handles:
                    try:
                        outcome = await handle
                    except Exception as e:
                        if isinstance(e, ApplicationError) and getattr(e, 'non_retryable', False):
                            workflow.logger.info("Tool %s rejected input (non-retryable): %s", tc["name"], str(e)[:120])
                        else:
                            workflow.logger.warning("Tool %s failed: %s", tc["name"], e)
                        te["error"] = str(e)[:200]
                        outcome = {
                            "messages": [
                                {"role": "tool", "tool_call_id": tc["id"],
                                 "content": f"Error: {e}"}
                            ],
                            "error": str(e)[:200],
                        }
                    # The workflow owns the exact call ID being answered. Activities
                    # may inspect stale state after another tool result is appended,
                    # so their name-based lookup cannot safely pair a response.
                    if isinstance(outcome, dict):
                        for message in outcome.get("messages", []):
                            if message.get("role") == "tool":
                                message["tool_call_id"] = tc["id"]
                    if isinstance(outcome, dict) and outcome.get("error"):
                        tool_failures += 1
                    if tc["name"] == "transcode" and isinstance(outcome, dict):
                        n = outcome.get("frames_extracted", 0)
                        turns_transcode += n
                    if isinstance(outcome, dict):
                        te.update(outcome)
                    if tc["name"] == "show_frame" and isinstance(outcome, dict):
                        res = outcome.get("resolution")
                        n_frames = outcome.get("frames_shown", 0)
                        if res in ("tiny", "low"):
                            turns_low += n_frames
                        elif res == "med":
                            turns_high += n_frames
                        elif res in ("high", "max"):
                            turns_max += n_frames
                    trace_entries.append(te)
                    outcomes.append(outcome)

            if outcomes:
                await workflow.execute_activity(
                    apply_tool_messages_activity,
                    arg={"msg_path": msg_path, "outcomes": outcomes},
                    task_queue=genai_queue,
                    start_to_close_timeout=timedelta(seconds=10),
                    retry_policy=_ACTIVITY_RETRY,
                )

            workflow.set_current_details(
                f"Turn {turn+1}/{max_turns} | "
                f"tokens: {total_cost['prompt']}+{total_cost['completion']} "
                f"(cached: {total_cost['cached']}) | "
                f"tools: {len(trace_entries)}"
            )

        if not description:
            description = f"Agentic failed: max turns ({max_turns}) exceeded without set_description"
            confidence = "low"
            workflow.logger.warning("Agent: max turns exceeded for %s", event_id)

        # ── Cleanup ────────────────────────────────────────────────────────
        self.ipc_closed = True
        # Wake all waiters
        for key in list(self.ipc_reply_ready.keys()):
            self.ipc_reply_ready[key] = True

        # Cancel running children
        cancel_handles = []
        for token, info in list(self.child_registry.items()):
            if info.get("status") == "running":
                try:
                    info["handle"].cancel()
                    cancel_handles.append(info["handle"])
                    info["status"] = "cancelled"
                except Exception:
                    info["status"] = "cancelled"

        # Await cancelled handles
        if cancel_handles:
            await asyncio.gather(*cancel_handles, return_exceptions=True)

        # Clear registries
        self.child_registry.clear()

        # Wait for all handlers to finish
        await workflow.wait_condition(workflow.all_handlers_finished)

        return {
            "description": description,
            "confidence": confidence,
            "total_cost": total_cost,
            "turns_used": turn + 1,
            "turns_low": turns_low,
            "turns_high": turns_high,
            "turns_max": turns_max,
            "turns_transcode": turns_transcode,
            "tool_failures": tool_failures,
            "trace_entries": trace_entries,
        }
