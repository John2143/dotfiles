"""Select the LLM model for this workflow."""

import logging

from temporalio import activity

from frigate_genai.s3_helpers import _s3_get, load_json

log = logging.getLogger("frigate-genai-sidecar")

DEFAULT_MODEL = "ollama/gemma4:12b"


@activity.defn(name="select_model")
async def select_model_activity(input_data: dict) -> str:
    """Return the model for this workflow from the baked provider list.

    Order: the workflow input's explicit `model` (dashboard "Reprocess w/
    model"), else the small model while the host is busy, else the first
    configured model. There is no cloud fallback: an empty list is a
    deployment error, not a reason to reach for another provider.
    """
    provider_cfg = load_json(input_data.get("provider_path",
        "/var/lib/frigate-genai-sidecar/provider.json"))
    models = provider_cfg.get("model", [])
    if not isinstance(models, list):
        models = [models]
    if not models:
        raise RuntimeError("no local model configured")

    requested = input_data.get("model")
    if requested:
        if requested in models:
            log.info("Selected model %s (requested)", requested)
            return requested
        log.warning("Requested model %s is not configured; ignoring", requested)

    if _s3_get("_state/paused/ollama") is not None and DEFAULT_MODEL in models:
        log.info("Selected model %s (host busy)", DEFAULT_MODEL)
        return DEFAULT_MODEL

    log.info("Selected model %s (first configured)", models[0])
    return models[0]
