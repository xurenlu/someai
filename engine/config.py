"""Engine configuration and version."""
from pathlib import Path

APP_VERSION = "1.0.0-rc18"

# Paths - resolve relative to engine directory
ENGINE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = ENGINE_DIR.parent
MODELS_DIR = PROJECT_ROOT / "models"
CONFIG_DIR = PROJECT_ROOT / "config"
MODELS_JSON = CONFIG_DIR / "models.json"
