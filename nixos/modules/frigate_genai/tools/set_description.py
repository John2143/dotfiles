import json

from temporalio import activity

from frigate_genai.s3_helpers import _load_state


@activity.defn(name="tool_set_description")
async def tool_set_description_activity(arg: dict) -> dict:
    """Append the final description/confidence to messages.json."""
    msg_path = arg["msg_path"]
    state, agent_dir = _load_state(msg_path)

    outcome_messages = []

    # description and confidence are pre-validated in run_genai_turn_activity
    # and passed through the workflow — re-extract from state for safety
    assistant_msg = state["messages"][-1]
    for tc in assistant_msg.get("tool_calls", []):
        if tc.get("function", {}).get("name") == "set_description":
            args = tc.get("function", {}).get("arguments", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except json.JSONDecodeError:
                    args = {}
            description = args.get("description", "")
            confidence = args.get("confidence", "medium")
            tc_id = tc.get("id")
            tool_result = f"Description set. Confidence: {confidence}."
            if tc_id:
                outcome_messages.append({
                    "role": "tool", "tool_call_id": tc_id, "content": tool_result,
                })
            break

    return {"description_set": True, "confidence": confidence, "messages": outcome_messages}
