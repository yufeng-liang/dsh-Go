# Portable 聊天 UI 协议（草案）

[English](en/portable-ui.md)

dsh-go 不要求每个 UI 插件都适配自己的原生组件；聊天消息里的 UI 可以由宿主按一个统一的 portable 优先级渲染。本页描述协议与 App 当前实现范围。

## 优先级

宿主按以下顺序解析工具结果的 `presentationMeta`，命中即停止：

1. `presentationMeta['dsh-go/view']` — dsh-go 原生视图；已有 16 种组件与媒体卡优先使用。
2. `presentationMeta['dsh-go/media']` — dsh-go 媒体卡。
3. `presentationMeta.ui` — intelligent-ui 的 `declarative` / `widget` / `composition` artifact；App 用受限 WebView renderer 渲染。
4. `presentationMeta['dsh-go/portable']` — 本页的统一 envelope（**已实现**）。
5. `presentationMeta.html` / `presentationMeta.widget.html` / `presentationMeta.fragment` — 通用 HTML 片段（**已实现**；高于第 6 层，低于第 4 层的 envelope）。
6. `presentationMeta.card` / `presentationMeta.kind == 'card'` — 结构化卡片（**已实现**；优先级最低的可识别 UI）。
7. 普通工具行 — 没有可识别 UI 时保底展示。

解析器必须**跳过** 1–3，避免和现有原生/intelligent-ui 适配抢卡片、重复渲染。

5、6 两层的识别条件（一项不合格就继续看下一项）：

- 第 5 层依次看 `presentationMeta.html`（字符串）、`presentationMeta.widget.html`（`widget` 是 Map 时取 `html`、`css`、`title`）、`presentationMeta.fragment`（字符串）。每一项都要非空，且不含脚本开标签：实现用不区分大小写的正则 `<\s*/?\s*script`，所以 `<script>`、`<script/>`、`<script`（没有闭合 `>`）一律拒收——不要按「包含 `<script` 就算」这种弱口径理解。
- 这三处 HTML 在出卡前先经 `_sanitizeWidgetHtml`（`app/lib/state/intelligent_ui.dart`）消毒：摘掉 `on*=` 内联事件属性与 `javascript:` 协议；这是渲染前的消毒步骤。
- 第 6 层看 `presentationMeta.card`（Map 自身作数据源，`title` 取 `card.title` 或外层 `presentationMeta.title`），或 `presentationMeta.kind == 'card'`（整个 `presentationMeta` 作数据源）。
- 两层都产不出可用 HTML 时回到第 7 层，显示普通工具行。

## 建议的通用 envelope

```json
{
  "dsh-go/portable": {
    "kind": "html",
    "title": "可选标题",
    "html": "<div>…</div>",
    "css": "…",
    "policy": {
      "allowMedia": false,
      "mediaOrigins": [],
      "maxHeight": 4000
    }
  }
}
```

- `kind` 取 `html` / `structured` / `media`；宿主按 kind 选择适配器。
- HTML 必须自包含，不执行远程脚本；图片等外部资源需列入 `mediaOrigins`。
- 分享时宿主把可序列化的 envelope 转成离屏截图；只有 `policy` 放行媒体时截图 WebView 才联网，CSP 由同一 `policy` 生成；不依赖插件的 Web 前端状态。
- 任意 React 组件、依赖宿主路由或前端全局状态的插件不应进入该协议，应改投 `dsh-go/view` 或使用 WebView 岛。

## 当前 App 实现状态

`PortableUiAdapter.fromTool`（`app/lib/state/intelligent_ui.dart:156`）在投影聊天行时（`app/lib/ui/chat/chat_rows.dart:234`）识别工具结果，命中后转换成受限的智能 UI widget 卡片，与 intelligent-ui 卡片共用同一条挂载路径（按 `callId` / `seq` 合并）。识别顺序命中即停：

1. `presentationMeta` 不是 Map，或工具结果没有 `seq` → 不产卡。
2. 跳过第 1–3 层：`dsh-go/view`、`dsh-go/media`、`ui` 任一存在且非 null，或工具名是 `ui_render` / `ui_render_widget` / `ui_compose`。
3. 第 4 层：`dsh-go/portable` 是 Map → 按 `kind` 转换（见下表）；`dsh-go/portable` 存在但 `kind` 不认识或内容不合格时不产卡。
4. 第 5 层：`html` / `widget.html` / `fragment` → 通用 HTML（`widget` 是 Map 时取 `widget.html`、`widget.css`、`widget.title`）。
5. 第 6 层：`card` / `kind == 'card'` → 结构化卡片。
6. 都不命中 → 不产卡，回到普通工具行。

portable 产物不只在聊天行上画一张卡：`IntelligentUiProjection`（`app/lib/state/intelligent_ui.dart`）会把 portable 适配器的命中结果一并投影进会话的 `artifacts`（`uiId` 取 `callId`、`version` 为 1、`hostId` / `sessionId` 来自会话上下文），所以 portable 卡片同样能进分享卡片与链接回放。聊天列表里的 `PortableUiAdapter` 只作投影未命中时的兜底，并按 `callId` 去重：同一个 `callId` 只出一张卡。

| kind | 输入 | 当前转换 |
|---|---|---|
| `html` | `html`（必填，非空且不匹配 `<\s*/?\s*script`）、可选 `css`、可选 `title` | 生成 `{html, css, initialHeight: 48}` |
| `structured` | 结构化字段（见下表） | 转成结构化 HTML |
| `media` | `url`（只接受 `https://` 前缀） | 先按 HTML 属性转义再拼进 `src`（引号转成 `&quot;`），url 跳不出 `src` 属性——不要假设原始 url 的引号不会逃逸；生成 `<img>` 后外部加载仍受 `policy` 的 `allowMedia` / `mediaOrigins` 限制 |

`policy` 的取法：第 4 层用 envelope 里的 `policy`，第 5、6 层用外层 `presentationMeta['policy']`；不是 Map 时按空 map 处理。产物统一是 `IntelligentUiKind.widget`、`uiId` 取工具调用的 `callId`、`version` 为 1、`seq` 取工具结果的 `seq`、`originSeq` 取这次工具调用第一次出现的 `seq`（聊天行直接走适配器时与 `seq` 相同）；`definition` 必须通过 `IntelligentUiProjector._validWidget`（`app/lib/state/intelligent_ui.dart:920`），`html` 为空或匹配 `<\s*/?\s*script` 直接不产卡。CSS 只有两个来源：第 4 层 `kind: html` 带 envelope 自己的 `css`，第 5 层 `widget.html` 带 `widget.css`；裸 `presentationMeta.html` 与 `fragment` 不读外层 `presentationMeta.css`。

结构化渲染（`structured`、`card` 共用一套 `_structuredHtml`），所有文本先 `HtmlEscape` 转义：

| 键 | 输入 | 输出 |
|---|---|---|
| `title` | String | `<h2>` |
| `fields` | `[{label, value}]` | 一行一条 |
| `metrics` | `[{label, value, delta?, trend?}]` | 卡片式指标块，`trend` 取 `up` / `down` / `flat`，用 class 标色 |
| `tables` | `[{title?, columns: [String], rows: [[…]]}]` | `<table>`，最多 50 行 × 12 列，超出截断 |
| `items` | 元素是 String 或 `{label, value}` 的列表 | `<ul><li>` |
| `markdown` | String | 极简 Markdown：段落、`#` / `##` / `###` 标题、`**粗体**`、`*斜体*`、反引号行内代码、围栏代码块、`-` / `1.` 列表、`[文字](https://…)`；先转义再套标签，任何原始标签都不透传 |

HTML 长度上限 60000 字符对**所有** html 来源生效：envelope 的 `html`、`presentationMeta.html`、`widget.html`、`fragment` 以及结构化渲染产物都一样，超限不出卡（不截断、不出半张卡）；`_validWidget` 的 480000 字符总闸另算。一个字段都没渲染出内容也不产卡。CSS 用一段共享样式（`.dsh-portable`、`.dsh-portable-metrics`、`.dsh-portable-table` 等），`initialHeight` 仍是 48。

分享快照按卡片自己的 `policy` 决定是否联网（**已实现**）：

- `app/lib/ui/share/intelligent_ui_snapshot.dart:107` 的 `snapshotAllowsRemoteMedia(policy)` 由 `allowMedia` / `mediaOrigins` 决定是否放行网络；同一 `policy` 生成的 CSP（同文件 `:129`）再决定能访问哪些源。
- `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/intelligentui/IntelligentUiSnapshotPlugin.kt:147` 的 `blockNetworkLoads = !remoteMedia`；联网时等图用同文件的 `MEDIA_SETTLE_MS = 5000L`（`:307`），不联网时用 `PAGE_SETTLE_MS`。
- 历史提交：b30660bd（快照按 policy 联网）、3c92b37f（渲染器媒体改由 policy 放行，离线只作默认值）。

`dsh-go/portable` 生成的卡片与 intelligent-ui 卡片共用同一套：

- 聊天内卡片渲染与沉浸式 widget：portable 产物是 `widget` + `html` 定义，一律走 WebView，不参与 declarative 的原生快速路径（`Text` / `Stat` / `Table` / `Badge` / `Divider` / `List` / `Progress` / `Stack` / `Grid` / `Card`）；
- 分享面板与分享图片；
- 链接回放。

## 尚未实现

- `card` 的样式与图表扩展：现在只有基础字段渲染，`metrics` / `tables` 之外没有样式钩子和图表类型。
- SDK 文档与插件模板里的协议落地：`sdk/plugin-kit` 还没教插件作者怎么产出 `presentationMeta`。

## 适配优先级

通用 `html` / `widget.html` 自动识别已完成（覆盖最多现有插件），`card` / `kind` 结构化适配也已完成，剩下把协议写进 SDK 文档与插件模板。intelligent-ui 的 `ui` artifact 是优先级 3 的特例，已有完整实现。
