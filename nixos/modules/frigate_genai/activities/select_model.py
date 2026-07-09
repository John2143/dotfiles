"""Select the LLM model for this workflow."""

import logging
import os
import random

from temporalio import activity

from frigate_genai.activities.genai_turn import _model_weights
from frigate_genai.s3_helpers import load_json

log = logging.getLogger("frigate-genai-sidecar")


@activity.defn(name="select_model")
async def select_model_activity(input_data: dict) -> str:
    """Select the LLM model for this workflow. Activity so it's visible
    in Temporal history and can run on any worker (distributed-safe)."""
    provider_cfg = load_json(input_data.get("provider_path",
        "/var/lib/frigate-genai-sidecar/provider.json"))
    models = provider_cfg.get("model", ["gemini/gemini-2.5-flash"])
    if not isinstance(models, list):
        models = [models]

    paused = input_data.get("paused-ollama", False)
    if paused:
        # Ollama is paused — always use a gemini model (weighted selection)
        gemini_models = [m for m in models if m.startswith("gemini/")]
        if not gemini_models:
            model = "gemini/gemini-2.5-flash"
        else:
            weights = _model_weights(gemini_models)
            model = random.choices(gemini_models, weights=weights, k=1)[0]
            log.info("Selected model %s (paused ollama, weighted)", model)
    else:
        ollama_models = [m for m in models if not m.startswith("gemini/")]
        gemini_models = [m for m in models if m.startswith("gemini/")]
        ratio = float(os.environ.get("GENAI_OLLAMA_RATIO", "0.3"))
        if ollama_models and random.random() < ratio:
            model = random.choice(ollama_models)
        elif gemini_models:
            weights = _model_weights(gemini_models)
            model = random.choices(gemini_models, weights=weights, k=1)[0]
        else:
            model = "gemini/gemini-2.5-flash"

    log.info("Selected model %s (paused=%s, ratio=%.2f)", model, paused,
             float(os.environ.get("GENAI_OLLAMA_RATIO", "0.3")))
    return model
