"""Generate llms.txt manifest for LLM-friendly API documentation.

See https://txt-llms.com/documentation for the llms.txt specification.
"""

from .config import APP_VERSION


def generate_llms_txt(base_url: str = "") -> str:
    """Generate llms.txt content. base_url e.g. http://127.0.0.1:18080 (optional)."""
    prefix = base_url.rstrip("/") if base_url else ""
    p = lambda path: f"{prefix}{path}" if prefix else path
    model_id_path = "/models/{model_id}"

    return f"""# MacAIStudio Engine (v{APP_VERSION})

> Local AI engine for Mac with LLM, TTS, STT, image generation, and OCR. Ollama-style model management.

## API Endpoints

- [GET /health]({p("/health")}): Health check, returns status and loaded model types
- [GET /models]({p("/models")}): List all installed/available models
- [GET /models/loaded]({p("/models/loaded")}): List currently loaded models and resource usage
- [GET /models/{{model_id}}]({p(model_id_path)}): Get single model details by id
- [POST /models/{{model_id}}/load]({p("/models/{{model_id}}/load")}): Preload model into memory (avoids MODEL_NOT_LOADED on first generate)
- [POST /models]({p("/models")}): Add custom HuggingFace model (body: hf_repo, name?, type?, size_bytes?, capabilities?, context_length?, languages?, default_params?)
- [DELETE /models/{{model_id}}]({p(model_id_path)}): Delete local model files
- [POST /models/download]({p("/models/download")}): Trigger model download (body: model_id)
- [GET /models/download/stream]({p("/models/download/stream")}): Stream download progress via SSE (?model_id=)
- [POST /llm/generate]({p("/llm/generate")}): Text generation (body: prompt, temperature?, max_tokens?)
- [POST /tts/generate]({p("/tts/generate")}): Text-to-speech (body: text, language?, speaker?)
- [POST /stt/transcribe]({p("/stt/transcribe")}): Speech-to-text (multipart: file)
- [POST /image/generate]({p("/image/generate")}): Image generation (body: prompt, width?, height?)
- [POST /ocr/recognize]({p("/ocr/recognize")}): OCR image-to-text (multipart: file, format?: text|json)

## Supporting Context

MacAIStudio Engine is a local AI inference server. All responses include `X-App-Version` header.

- **Models**: LLM, TTS, STT, image (Stable Diffusion), vision, OCR (TrOCR). Add custom models via POST /models with HuggingFace repo.
- **LLM**: POST /llm/generate with {{"prompt": "...", "temperature": 0.7, "max_tokens": 512}}.
- **TTS**: POST /tts/generate with {{"text": "...", "language": "zh", "speaker": "default"}}.
- **STT**: POST /stt/transcribe with multipart/form-data file upload.
- **Image**: POST /image/generate with {{"prompt": "...", "width": 512, "height": 512}}.
- **OCR**: POST /ocr/recognize with multipart/form-data file upload (image). Query param format=text (default) or json.
"""
