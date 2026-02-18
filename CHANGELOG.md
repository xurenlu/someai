# Changelog

## [1.0.0-rc18] - 2026-02-18

### Added

- 设置：新增「使用中国 PyPI 镜像」开关，启用后 uv sync 使用清华源加速；新增「同步依赖」按钮可手动触发

### Fixed

- 引擎启动：将 faster_whisper、huggingface_hub、tqdm 改为惰性导入，避免启动时阻塞，/health 可在数秒内响应
- 依赖：qwen-tts 改为可选（librosa→numba→llvmlite 在 Python 3.12+ 不兼容），默认使用 edge-tts；需 Qwen3-TTS 时运行 `uv sync --extra qwen-tts`（建议 Python 3.10/3.11）

## [1.0.0-rc17] - 2026-02-18

### Added

- llms.txt：HTTP 接口 `/llms.txt` 与 `/llm.txt` 输出 LLM 友好的 API 清单
- 设置页新增「API 文档」区块，可内嵌查看 llms.txt 或于浏览器打开

## [1.0.0-rc17] - 2026-02-18

### Changed

- Model Manager：「复制诊断信息」按钮点击后显示「已复制」反馈，避免用户误以为未点击成功
- LLM：优先使用已下载的本地模型（transformers），Ollama 仅作 fallback，不再强制依赖 Ollama
- TTS：优先使用已下载的 Qwen3-TTS 本地模型，无则 fallback edge-tts（完全免费，无需 token/账号）
- 依赖：新增 qwen-tts、soundfile

## [1.0.0-rc16] - 2026-02-18

### Added

- 语音聊天完整实现：STT 使用 faster-whisper，LLM 支持 Ollama 或 transformers 本地推理，TTS 使用 edge-tts
- 依赖：faster-whisper、edge-tts、httpx、transformers、torch、accelerate

### Changed

- TTS 接口返回 MP3 格式（原为 WAV placeholder）

## [1.0.0-rc15] - 2026-02-18

### Added

- 支持添加 HuggingFace 自定义模型：Model Manager 新增「从 HuggingFace 添加」按钮，可输入任意 `org/repo` 仓库添加模型并下载
- models.json 支持 `hf_repo` 字段，可手动编辑配置指定自定义 HuggingFace 仓库

## [1.0.0-rc14] - 2026-02-18

### Added

- 模型下载：支持 SSE 流式进度条，显示已下载/总大小
- 模型下载：支持断点续传（重试时跳过已下载文件）

## [1.0.0-rc13] - 2026-02-18

### Added

- Model Manager：已安装模型支持「删除」按钮，删除后可重新下载；删除前有确认对话框

## [1.0.0-rc12] - 2026-02-18

### Added

- Model Manager：显示模型大小（预计/实际）、文件类型（.safetensors 等）
- Model Manager：已安装模型支持「在 Finder 中打开」查看本地目录
- Model Manager：下载中显示预计大小，便于判断是否在真实下载
- Model Manager：工具栏新增「模型目录」按钮，可打开 models 根目录查看存储位置

### Fixed

- 下载 API：校验 huggingface_hub 返回码，失败时返回具体错误信息
- 已安装判定：仅当目录内存在文件时才显示 installed，避免空目录误判

## [1.0.0-rc11] - 2026-02-18

### Added

- Model Manager：每个未下载模型后新增「下载」按钮，支持一键下载
- 模型列表：新增适合 16GB M2 Mac 的模型（Qwen2.5-0.5B/3B、TinyLlama-1.1B、Phi-2、Whisper Tiny 等）
- 端口占用：启动时写入 `.engine.pid`，结合 PID 文件与进程名（uvicorn + engine.server）判断是否为我们的引擎；自动终止旧引擎或提供「结束占用进程并重试」按钮

## [1.0.0-rc10] - 2026-02-18

### Fixed

- 修复 Xcode 开发时 App 与手动 uv sync 使用不同项目路径的问题：构建时写入 project_dir.txt，运行时优先使用项目目录，复用用户手动创建的 .venv，避免「自动修复中」卡住或引擎启动失败

## [1.0.0-rc9] - 2026-02-18

### Fixed

- 修复「No pyproject.toml found」错误：将 pyproject.toml 与 uv.lock 加入 App 打包资源，使 uv sync 在打包后运行时可用
- 启动前检查 pyproject.toml 是否存在，缺失时给出明确错误提示

## [1.0.0-rc8] - 2026-02-18

### Added

- Model Manager：uv sync 时显示「自动修复中（uv sync）...」进度提示
- Model Manager：错误时新增「复制诊断信息」按钮，一键复制端口、stderr、解释器路径等便于反馈

## [1.0.0-rc7] - 2026-02-18

### Changed

- EngineManager：新增启动前自检（端口占用、引擎目录、Python/uv 可用性）并返回明确错误原因
- EngineManager：检测到 `.venv` 缺失时自动执行 `uv sync` 进行环境初始化
- EngineManager：新增启动后健康等待（轮询 `/health`），避免“刚启动即请求”导致误报失败
- EngineManager：记录并上抛 stderr 关键错误，进程异常退出时在 UI 显示可诊断信息
- EngineClient：连接失败时先检查端口占用，区分“端口被占用”与“引擎未就绪/启动失败”
- Model Manager：首次进入与手动重试都会先确保引擎就绪，再发起模型接口请求
- 国际化：新增引擎目录缺失、解释器缺失、端口占用明细、引擎未就绪等错误文案

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
