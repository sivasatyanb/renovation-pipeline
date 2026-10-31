"""Studio room renovation rendering package (Nano Banana image-to-image + TTS narration)."""

from app.rendering.service import (
    DEMO_RENDER_DIR,
    GEMINI_RENOVATION_SYSTEM_PROMPT,
    MAX_IMAGE_BYTES,
    RenderRecord,
    build_default_project_fields,
    build_natural_replacement_prompt,
    build_plan_user_prompt,
    detect_image_mime,
    run_render_job,
    validate_and_decode_image,
)

__all__ = [
    "DEMO_RENDER_DIR",
    "GEMINI_RENOVATION_SYSTEM_PROMPT",
    "MAX_IMAGE_BYTES",
    "RenderRecord",
    "build_default_project_fields",
    "build_natural_replacement_prompt",
    "build_plan_user_prompt",
    "detect_image_mime",
    "run_render_job",
    "validate_and_decode_image",
]
