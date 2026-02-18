# Changelog

## [1.0.0-rc6] - 2026-02-18

### Changed

- Model Manager：健康检查增加自动重试（3 次，间隔 1.5s）
- Model Manager：启动等待时间由 1.2s 增至 2s
- Model Manager：连接失败时显示更友好的错误提示（区分连接拒绝、超时、网络未连接）
- Model Manager：新增重试按钮（工具栏 + 错误区域）
- EngineManager：增加 stderr 输出日志，便于排查引擎启动问题
- EngineClient：增加 fetchHealth/fetchModels 重试逻辑及详细日志

## [1.0.0-rc5] - 2026-02-18

### Changed

- 依赖管理迁移至 uv（pyproject.toml，移除 requirements.txt）
- 关闭 App 沙盒（ENABLE_APP_SANDBOX = NO）
- EngineManager 优先使用 `uv run` 启动引擎
- 设置页：版本、麦克风权限状态、申请按钮、打开系统设置入口

## [1.0.0-rc4] - 2026-02-18

### Added (M5)

- 任务队列：`task_queue.py` 串行化重任务
- 内存 watchdog：`memory_watchdog.py` 监控进程内存
- `POST /models/download`：触发 huggingface_hub 下载
- `/models/loaded` 增加 `queue_size`、`memory_mb` 字段

## [1.0.0-rc3] - 2026-02-18

### Added (M3)

- `POST /stt/transcribe`：语音转文字（multipart file upload）
- VoiceChatView：录音 -> STT -> LLM -> TTS -> 播放闭环

### Added (M4)

- `POST /image/generate`：文生图（prompt、width、height）
- ImageView：prompt 输入、尺寸调节、生成、预览、保存

## [1.0.0-rc2] - 2026-02-18

### Added (M2)

- `POST /llm/generate`：文本生成（temperature、max_tokens）
- `POST /tts/generate`：文本转语音（language、speaker），返回 audio/wav
- ChatView：对话窗口、输入框、模型选择、响应展示
- TTSView：文本输入、语言/speaker 选择、播放、保存

## [1.0.0-rc1] - 2026-02-18

### Added (M1)

- Swift + Python 工程骨架
- EngineManager：启停 Python 引擎子进程
- FastAPI 引擎：`/health`、`/models`、`/models/loaded`、`/models/{id}`
- 统一版本 Header：`X-App-Version`
- SwiftUI 主界面：Sidebar（Chat、TTS、Voice Chat、Image、Model Manager、Settings）
- Model Manager 页面：健康状态、模型清单
- 国际化字符串（en / zh-Hans）
