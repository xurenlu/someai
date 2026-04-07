"""单元测试：LLM 后端检测（Gemma 4 vs 因果 LM）。"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from engine.llm_service import _llm_backend_for_path


class TestLlmBackendForPath(unittest.TestCase):
    def test_gemma4_architecture(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / "config.json").write_text(
                json.dumps({"architectures": ["Gemma4ForConditionalGeneration"]}),
                encoding="utf-8",
            )
            self.assertEqual(_llm_backend_for_path(p), "gemma4")

    def test_causal_lm_other_arch(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / "config.json").write_text(
                json.dumps({"architectures": ["Qwen2ForCausalLM"]}),
                encoding="utf-8",
            )
            self.assertEqual(_llm_backend_for_path(p), "causal_lm")

    def test_missing_config_defaults_causal(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(_llm_backend_for_path(Path(d)), "causal_lm")


if __name__ == "__main__":
    unittest.main()
