"""Pydantic contracts for all workflow and activity boundaries.
All models use extra="forbid" to catch typos at deserialization time.
"""

from typing import Literal, Optional

from pydantic import BaseModel, model_validator


class BaseFrigateModel(BaseModel):
    model_config = {"extra": "forbid"}


class GenAIWorkflowInput(BaseFrigateModel):
    event_id: str
    camera: str
    label: str
    start_time: float
    end_time: float
    prompts_path: str
    provider_path: str
    model: Optional[str] = None
    skip_frames: bool = False
    data_box: Optional[list[float]] = None


class AgentSessionInput(BaseFrigateModel):
    msg_path: str
    provider_path: str
    model: str
    event_id: str
    camera: str
    label: str
    max_turns: int
    max_frames: int
    start_time: float
    end_time: float
    genai_queue: str
    ipc_token: Optional[str] = None
    parent_ipc_token: Optional[str] = None
    parent_workflow_id: Optional[str] = None


class AgentSessionOutput(BaseFrigateModel):
    description: Optional[str] = None
    confidence: Optional[str] = None
    total_cost: dict[str, int]
    turns_used: int
    turns_low: int = 0
    turns_high: int = 0
    turns_max: int = 0
    turns_transcode: int = 0
    tool_failures: int = 0
    trace_entries: list[dict]


class AgentState(BaseFrigateModel):
    messages: list[dict]
    agent_dir: str
    camera: str
    start_time: float = 0
    end_time: float = 0
    max_frames: int = 0
    data_box: Optional[list[float]] = None
    trace: list = []
    stats: dict = {}


class GenAITurnArg(BaseFrigateModel):
    msg_path: str
    provider_path: str
    model: str
    event_id: str
    camera: str
    label: str
    turn_num: int = 1
    max_turns: int = 100


class GenAITurnOutput(BaseFrigateModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0
    cached_tokens: int = 0
    assistant_message: Optional[dict] = None
    tool_calls: list[dict] = []
    description: Optional[str] = None
    confidence: Optional[str] = None
    text_only: bool = False


class ToolCallArg(BaseFrigateModel):
    """Unified arg dict passed to all tool activities."""
    msg_path: str
    args: dict
    event_id: str
    max_frames: int
    camera: str
    start_time: float
    end_time: float
    provider_path: str
    model: str


class ToolOutcome(BaseFrigateModel):
    messages: list[dict] = []
    error: Optional[str] = None
    # Tool-specific stats — all optional:
    frames_shown: int = 0
    resolution: Optional[str] = None
    frames_extracted: int = 0
    fps: float = 0
    crop_region: Optional[list[int]] = None
    count: int = 0
    source: Optional[str] = None
    crops_preserved: int = 0
    upscales_preserved: int = 0
    strip_images_before: Optional[int] = None
    description_set: bool = False
    snapshot_available: bool = False
    width: int = 0
    height: int = 0


class ApplyToolMessagesArg(BaseFrigateModel):
    msg_path: str
    outcomes: list[dict]


class InitAgentStateArg(BaseFrigateModel):
    event_id: str
    camera: str
    label: str
    frames_dir: str
    prompts_path: str
    data_box: Optional[list[float]] = None
    start_time: float = 0
    end_time: float = 0


class InitAgentStateOutput(BaseFrigateModel):
    msg_path: str
    max_frames: int



class SpawnArgs(BaseFrigateModel):
    """Nested inside ToolCallArg.args for spawn() tool calls."""
    tasks: list[dict]


class SpawnTask(BaseFrigateModel):
    task: str
    image_refs: list[str] = []
class SubAgentInput(BaseFrigateModel):
    """Input to SubAgentWorkflow. Built by spawn handler."""
    event_id: str
    camera: str
    label: str
    task: str
    image_refs: list[str] = []
    image_s3_keys: list[str] = []
    parent_agent_dir: str
    subagent_dir: str
    provider_path: str
    model: str
    genai_queue: str
    prompts_path: str
    start_time: float = 0
    end_time: float = 0
    depth: int = 1
    max_depth: int = 2
    max_turns: int = 8
    frames_dir: str = ""
    parent_workflow_id: str
    parent_run_id: str
    parent_ipc_token: str
    ipc_token: str


class SubAgentOutput(BaseFrigateModel):
    findings: Optional[str] = None
    confidence: Optional[str] = None
    turns_used: int = 0
    total_cost: dict[str, int] = {}
    key_images: list[dict] = []
    tool_failures: int = 0
    subagent_id: str = ""
    task: str = ""


class CloseSubagentArgs(BaseFrigateModel):
    findings: str
    confidence: str
    show_images: list[str] = []


class JoinArgs(BaseFrigateModel):
    spawn_key: str

class IPCMessage(BaseFrigateModel):
    message_id: str
    from_token: str
    to_token: str
    kind: Literal["finding", "question", "reply", "terminate"]
    content: str
    confidence: Optional[Literal["high", "medium", "low", "nothing_found"]] = None
    reply_to: Optional[str] = None
    seq: int
    created_at: float

    @model_validator(mode="after")
    def _validate_ipc_message(self):
        content_bytes = self.content.encode("utf-8")
        if len(content_bytes) < 1 or len(content_bytes) > 8192:
            raise ValueError("content must be 1..8192 UTF-8 bytes")
        if self.seq <= 0:
            raise ValueError("seq must be positive")
        if self.kind == "reply":
            if not self.reply_to:
                raise ValueError("reply requires reply_to")
        else:
            if self.reply_to is not None:
                raise ValueError("reply_to is only valid for replies")
        return self


class SendIPCArgs(BaseFrigateModel):
    to_token: str
    kind: Literal["finding", "question", "reply", "terminate"]
    content: str
    confidence: Optional[Literal["high", "medium", "low", "nothing_found"]] = None
    reply_to: Optional[str] = None
    wait_for_reply: bool = False
    timeout_seconds: int = 30

    @model_validator(mode="after")
    def _validate_send_ipc(self):
        content_bytes = self.content.encode("utf-8")
        if len(content_bytes) < 1 or len(content_bytes) > 8192:
            raise ValueError("content must be 1..8192 UTF-8 bytes")
        if self.timeout_seconds < 0 or self.timeout_seconds > 300:
            raise ValueError("timeout_seconds must be 0..300")
        if self.kind == "reply":
            if not self.reply_to:
                raise ValueError("reply requires reply_to")
        else:
            if self.reply_to is not None:
                raise ValueError("reply_to is only valid for replies")
        return self


class WaitIPCArgs(BaseFrigateModel):
    message_id: Optional[str] = None
    timeout_seconds: int = 30

    @model_validator(mode="after")
    def _validate_wait_ipc(self):
        if self.timeout_seconds < 0 or self.timeout_seconds > 300:
            raise ValueError("timeout_seconds must be 0..300")
        return self