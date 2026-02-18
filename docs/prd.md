````markdown
# 📦 macOS AI Studio — 产品级本地 AI 引擎方案设计

> 目标：
>
> 构建一个 **Swift 原生 macOS App**
> - ✅ 内嵌 Python 运行环境
> - ✅ 可管理多个模型（LLM / TTS / 文生图）
> - ✅ 16GB 内存可稳定运行
> - ✅ 本地 HTTP API 引擎
> - ✅ 可视化模型管理 UI
> - ✅ 支持语音聊天
> - ✅ 支持文生图
>
> 目标机器：Apple Silicon（M 系列）16GB / 24GB

---

# 🏗 一、总体架构

```
Mac App (SwiftUI)
│
├── Engine Manager
│    ├── Python Runtime 管理
│    ├── 模型下载管理
│    ├── 进程管理
│    ├── 日志监控
│
├── UI 层
│    ├── LLM 聊天
│    ├── TTS 文本转语音
│    ├── 语音聊天
│    ├── 文生图
│
└── Local AI Engine (Python 子进程)
     ├── FastAPI 服务
     ├── LLM 模块
     ├── TTS 模块
     ├── STT 模块
     ├── Image 模块
```

---

# 🧠 二、模型选择（16GB 稳定运行）

## ✅ 1️⃣ LLM（小模型）

推荐：

- `Qwen2.5-1.5B-Instruct`
- 或 `Phi-3-mini`
- 或 `Gemma-2B`

理由：

- 内存占用约 3~4GB
- MPS 可跑
- 质量够产品级

---

## ✅ 2️⃣ TTS

```
Qwen3-TTS-12Hz-0.6B-CustomVoice
```

- 内存占用约 4~6GB
- 支持多语言
- 支持 speaker 控制
- 适合本地部署

---

## ✅ 3️⃣ 文生图

建议：

- Stable Diffusion 1.5 (fp16)
- 或 SDXL-turbo

16GB 下可运行（单张生成）

---

## ✅ 4️⃣ 语音识别（STT）

- Whisper small
- 或 faster-whisper

---

# 📁 三、目录结构设计

```
MacAIStudio.app
│
├── Contents
│   ├── MacOS
│   │    └── MacAIStudio (Swift 主程序)
│   │
│   ├── Resources
│   │
│   │   ├── python/
│   │   │    ├── bin/python3
│   │   │    ├── lib/
│   │   │    └── site-packages/
│   │   │
│   │   ├── engine/
│   │   │    ├── server.py
│   │   │    ├── llm_service.py
│   │   │    ├── tts_service.py
│   │   │    ├── stt_service.py
│   │   │    ├── image_service.py
│   │   │
│   │   ├── models/
│   │   │    ├── llm/
│   │   │    ├── tts/
│   │   │    ├── sd/
│   │
│   │   └── config/
│   │        └── models.json
```

---

# 🐍 四、Python 运行环境管理方案

## ✅ 1️⃣ 内嵌 Python

- 使用 Python 3.12
- 在开发阶段构建干净 venv
- 冻结依赖版本

依赖：

```
torch
qwen-tts
transformers
fastapi
uvicorn
diffusers
whisper
```

---

## ✅ 2️⃣ Swift 管理 Python 进程

```swift
class EngineManager {

    private var process: Process?

    func startEngine() {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["server.py"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.run()
    }

    func stopEngine() {
        process?.terminate()
    }
}
```

---

# 🌐 五、本地 HTTP API 设计

Base URL:

```
http://127.0.0.1:8001
```

---

## ✅ 1️⃣ 健康检查

```
GET /health
```

Response:

```json
{
  "status": "ok",
  "models_loaded": ["llm", "tts"]
}
```

---

## ✅ 2️⃣ LLM 接口

```
POST /llm/generate
```

Request:

```json
{
  "prompt": "Explain quantum computing",
  "temperature": 0.7,
  "max_tokens": 512
}
```

Response:

```json
{
  "text": "Quantum computing is..."
}
```

---

## ✅ 3️⃣ TTS 接口

```
POST /tts/generate
```

Request:

```json
{
  "text": "Hello world",
  "language": "English",
  "speaker": "Ryan"
}
```

Response:

```
audio/wav binary
```

---

## ✅ 4️⃣ 语音识别

```
POST /stt/transcribe
```

Form-data:

```
file: audio.wav
```

Response:

```json
{
  "text": "recognized speech"
}
```

---

## ✅ 5️⃣ 文生图

```
POST /image/generate
```

Request:

```json
{
  "prompt": "A cyberpunk city at night",
  "width": 512,
  "height": 512
}
```

Response:

```
image/png binary
```

---

# 🖥 六、UI 模块设计

使用 SwiftUI。

---

## ✅ 1️⃣ 主界面布局

```
Sidebar
 ├── Chat
 ├── TTS
 ├── Voice Chat
 ├── Image
 ├── Model Manager
 ├── Settings
```

---

## ✅ 2️⃣ LLM Chat UI

- 对话窗口
- 输入框
- 模型选择下拉框
- Streaming 输出

---

## ✅ 3️⃣ TTS 页面

- 文本输入
- 语言选择
- speaker 选择
- 播放按钮
- 保存按钮

---

## ✅ 4️⃣ 语音聊天

流程：

```
麦克风录音
   ↓
STT
   ↓
LLM
   ↓
TTS
   ↓
播放
```

实现一个连续对话系统。

---

## ✅ 5️⃣ 文生图 UI

- prompt 输入
- 生成按钮
- 图片展示
- 保存按钮

---

# 🔁 七、语音聊天完整流程

```
用户说话
   ↓
/stt/transcribe
   ↓
/llm/generate
   ↓
/tts/generate
   ↓
播放音频
```

---

# 💾 八、模型下载管理

Swift 负责：

- 调用 huggingface CLI
- 显示下载进度
- 存储到 App Support 目录

示例：

```swift
Process.run(
    python,
    arguments: [
        "-m", "huggingface_hub",
        "download",
        "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
    ]
)
```

---

# 🧯 九、稳定性策略（产品级）

✅ 单实例模型加载  
✅ 任务队列  
✅ 内存 watchdog  
✅ 崩溃自动重启  
✅ 模型懒加载  
✅ 限制最大文本长度  

---

# 🚀 十、未来扩展

- 插件式模型加载
- 远程 GPU fallback
- 用户自定义模型
- 云端同步

---

# 📊 十一、16GB 内存运行预算

| 模块 | 内存 |
|------|------|
| macOS | 4~5GB |
| LLM | 3~4GB |
| TTS | 4~6GB |
| SD | 4~6GB |
| 峰值 | ~12GB |

可稳定运行 ✅

---

# 🎯 十二、最终产品定位

一个本地 AI 工作站：

- 类似 LM Studio
- 类似 Ollama GUI
- 专注多模态
- 本地优先
- 可商用

---

# ✅ 结论

本方案：

- ✅ 16GB 可稳定运行
- ✅ Swift 管理 Python
- ✅ 支持多模型
- ✅ HTTP API 清晰
- ✅ 可扩展
- ✅ 可商业化

---


````
