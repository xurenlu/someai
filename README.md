# MacAIStudio

本地 AI 工作站 - Swift 原生 macOS App + Python FastAPI 引擎。

## 开发

### 1. Python 引擎（uv）

```bash
# 安装 uv: curl -LsSf https://astral.sh/uv/install.sh | sh
uv sync
uv run python run_engine.py
```

引擎地址：http://127.0.0.1:8001

### 2. Swift App

用 Xcode 打开 `someai.xcodeproj`，运行 `someai` scheme。App 启动时会自动拉起引擎（优先使用项目 `.venv`，由 `uv sync` 创建）。

### 3. API

- `GET /health` - 健康检查
- `GET /models` - 模型列表
- `GET /models/loaded` - 已加载模型
- `GET /models/{id}` - 单模型详情

## 版本

当前版本：1.0.0-rc4

## API 列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /health | 健康检查 |
| GET | /models | 模型列表 |
| GET | /models/loaded | 已加载模型与资源 |
| GET | /models/{id} | 单模型详情 |
| POST | /models/download | 触发模型下载 |
| POST | /llm/generate | 文本生成 |
| POST | /tts/generate | 文本转语音 |
| POST | /stt/transcribe | 语音转文字 |
| POST | /image/generate | 文生图 |
