# 张雪香美 · AI 陪伴聊天

一个私人用的 AI 女友聊天项目：**Spring AI + Vue + SSE 流式**，人格来自 `companion_skill/`，说话短、会撒娇、会怼人，尽量不像客服。

> 前身是一个 AI 客服演示项目，现在客服相关的 RAG、文生图、多模式演示全部删掉了，只留一条对话链路。

## 一键使用

1. 双击 **`一键配置.bat`**，选服务商、粘 API Key（只需配一次，写进 `.env`）。
2. 双击 **`一键启动.bat`**，浏览器打开 **<http://localhost:5501>**。

首次启动会自动找 JDK 17+、下载 Maven 依赖并构建，需要几分钟；之后再启动几秒就好。

## 人设怎么改

全部在仓库根目录的 **`companion_skill/`**：

| 文件 | 作用 |
|---|---|
| `persona.md` | 人物全文（档案、句长、语气、原话库）。**只有 `<!-- PROMPT:START -->` 到 `PROMPT:END` 之间的那段会注入模型**，改这里最直接。 |
| `examples.jsonl` | 60 条真实对话，"她"那侧基本是导出原句。默认每个场景取 4 条做 few-shot。 |
| `guardrails.md` | 6 条守则，后端只取编号条目拼进提示词。 |

改完**重启服务**即可生效，不用重新打包（后端优先读工作目录下的 `companion_skill/`，读不到才用 jar 里的副本）。

## 配置

只认三项，放在根目录 `.env`（已被 `.gitignore` 忽略）：

| 变量 | 说明 | 示例 |
|---|---|---|
| `AI_BASE_URL` | 服务地址 | `https://ark.cn-beijing.volces.com/api/v3` |
| `AI_API_KEY` | 对应服务商的 Key | `ark-...` |
| `AI_MODEL` | 模型名 | `doubao-seed-2-0-mini-260428` |

任何 OpenAI 兼容接口都能用：百炼、DeepSeek、Kimi、智谱、OpenAI、Ollama、火山方舟、中转站。地址带不带 `/v1`、`/v4` 会自动纠正。

启动后访问 <http://localhost:5501/api/v1/info> 可以确认当前实际在调谁（不返回 Key）。

## 接口

| 用途 | 接口 |
|---|---|
| 普通对话 | `GET /api/v1/chat/base?msg=...&conversationId=...` |
| 流式对话 | `GET /api/v1/chat/stream?msg=...&conversationId=...`（结束推 `[over]`） |
| 当前配置 | `GET /api/v1/info` |
| 连通性 | `GET /test` |

前端把回复按换行拆成多个气泡，还原"连发几条"的感觉；`conversationId` 存在浏览器里，刷新不丢记忆，"重新开始"会换一个新会话。

## token 是怎么省的

- 人设、守则、样例在启动时拼成**一份** system prompt 并缓存，每轮不再重算。
- 每轮只带 system（约 1,800 字 ≈ 1,300 tokens）+ 最近 10 条记忆（约 150）+ 用户这句话。
- 回复上限 `max-tokens: 220`——她本来就话少。
- 删掉了 RAG 向量检索、文生图、日志 Advisor、工具调用等所有演示模式。

## 目录结构

```
AI_girlfriend_Service/
├─ companion_skill/          # 人设（唯一数据源，打包时复制进 jar）
│  ├─ persona.md
│  ├─ examples.jsonl
│  └─ guardrails.md
├─ springai-server/          # 后端：Spring Boot 3.2.5 + Spring AI 1.0.0-M6
│  └─ src/main/resources/static/   # 前端构建产物
├─ springai-web/             # 前端：Vue 3 + Vite 7 + Element Plus
├─ exports/                  # 微信导出（只读，项目不碰）
├─ 一键启动.bat / 一键配置.bat
└─ .env / .env.example
```

## 隐私

- `exports/` 里的原始聊天记录**一个字节都没改**，项目运行也不会读它。
- `persona.md` 含真实姓名、城市、学校生活等私人信息，只放在本机，别提交、别分享。
- `.env` 里的 Key 是明文，同样别提交。

## 已知限制

- 对话记忆在内存里，进程重启就清空。
- 单机自用，没有用户体系、鉴权、限流。
- 只有 Windows 双击脚本；Linux/macOS 可以手动 `./mvnw package` 后 `java -jar`。
- **改 `scripts/*.ps1` 必须存成 UTF-8 with BOM**：`.bat` 调的是 Windows PowerShell 5.1，无 BOM 会把中文按 GBK 读，直接语法报错。
- 人设是抽象画像 + 真实原句，不保证每句都跟本人一致。
