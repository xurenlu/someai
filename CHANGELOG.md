# Changelog

## [1.1.2] - 2026-02-19

### Fixed

- 新建聊天：切换至「历史记录」或其它标签再返回时，聊天内容不再丢失，仅用户主动点击「新建聊天」时才会清空会话

## [1.1.1] - 2026-02-19

### Added

- 聊天模型未加载体验优化：发送前检查模型是否已加载，未加载时先显示「正在加载模型...」，加载完成后提示「模型已加载完成，正在发送...」，并自动重发消息

### Changed

- ChatView：发送消息前调用 fetchLoadedModels 检查，未加载则先 preload 并展示加载状态，再自动发送

## [1.1.0] - 2026-02-19

### Added

- 模型未加载自动处理：LLM/TTS 请求若返回 MODEL_NOT_LOADED，客户端自动调用预加载接口并重试一次，无需用户手动操作
- 聊天顶级菜单：左侧最左新增「聊天」入口，其下分为「历史记录」与「新建聊天」
- 聊天会话管理：支持按会话归档，历史记录按会话分组展示
- 新建聊天入口：当当前会话消息数达到 5 条时，显示「新建聊天」按钮，点击后将当前聊天归档并开启新会话

### Changed

- EngineClient：generateChat、generateTTS 统一实现 MODEL_NOT_LOADED 自动加载与一次重试，含并发去重
- 创作中心：第三栏详情区域改为贴左铺满显示，减少左侧视觉留白
- Chat：输入框默认高度增大，支持随输入内容自动增长，最大高度限制为窗体高度约一半

## [1.0.0-rc24] - 2026-02-19

### Changed

- 创作中心：第三栏详情区域改为贴左铺满显示，减少左侧视觉留白
- Chat：输入框默认高度增大，支持随输入内容自动增长，最大高度限制为窗体高度约一半

## [1.0.0-rc23] - 2026-02-19

### Added

- 内存优化：模型空闲超时自动卸载，超时时间可在设置中配置（默认 15 分钟）
- 模型需加载时提示用户，客户端自动预加载后重试
- RESTful API：POST /models/{model_id}/load 支持预加载模型

### Changed

- LLM/TTS 服务：模型缓存、空闲超时卸载、预加载支持
- 设置页：新增「模型空闲超时 (分钟)」选项

## [1.0.0-rc22] - 2026-02-19

### Added

- OCR 功能：新增独立 OCR 模型类型与能力，图片输入、输出结构化文本
- 模型：TrOCR-Base-Printed (Microsoft)，从 Hugging Face 下载，支持印刷体文字识别
- API：`POST /ocr/recognize`，multipart 上传图片，支持 format=text（默认）或 json
- 创作中心：新增 OCR 入口，选择图片→识别→复制/保存结果
- 历史中心：OCR 记录支持筛选、重发、打开结果文件

### Changed

- 模型类型：新增 ocr，模型管理支持 OCR 模型下载与管理

## [1.0.0-rc21] - 2026-02-19

### Changed

- Model Manager：模型列表改为按类型分组展示，并在分组标题显示模型数量，便于在模型增多时快速定位
- Model Manager：分组标题支持国际化（LLM/大语言模型、TTS/文字转语音、STT/语音转文字、Image/图像、Vision/视觉等）

## [1.0.0-rc20] - 2026-02-19

### Added

- 统一生成历史：Chat/TTS/Image/VoiceChat 全部接入本机 JSON 持久化历史中心，重启 App 后记录仍在
- 历史中心：跨工具时间线、按类型/状态筛选、关键字搜索、重发失败任务、重样生成成功任务、打开结果文件、查看详情
- 创作中心：侧栏重构为「创作中心 + 历史中心 + 模型管理 + 设置」，创作中心内嵌 Chat/TTS/VoiceChat/Image
- 可配置输出目录：设置页新增「输出目录」，TTS 音频、图片、语音聊天录音等生成文件保存至该目录（默认 ~/Downloads/someai）
- 统一生成调用层：EngineClient 新增 generateChat/generateTTS/generateImage/transcribe，网络错误自动重试 1~2 次
- 设计系统：DesignSystem.swift 提供 DesignTokens、ErrorBanner、LoadingState、EmptyState 等统一组件

### Changed

- 信息架构：侧栏从功能孤岛改为创作流程导向

## [1.0.0-rc19] - 2026-02-18

### Added

- 设置：新增「内存上限 (MB)」选项，可限制 Python 引擎进程最大内存占用（0 表示不限制），修改后需重启引擎

### Fixed

- 模型管理：引擎已停止时，健康状况不再显示缓存的 ok，改为显示「—」

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
