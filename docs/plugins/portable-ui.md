# Portable 聊天 UI 协议（草案）

[English](en/portable-ui.md)

dsh-go 不要求每个 UI 插件都适配自己的原生组件；聊天消息里的 UI 可以由宿主按一个统一的 portable 优先级渲染。本页描述协议与 App 当前实现范围。

## 优先级

宿主按以下顺序解析工具结果的 `presentationMeta`，命中即停止：

1. `presentationMeta['dsh-go/view']` — dsh-go 原生视图；已有 16 种组件与媒体卡优先使用。
2. `presentationMeta['dsh-go/media']` — dsh-go 媒体卡。
3. `presentationMeta.ui` — intelligent-ui 的 `declarative` / `widget` / `composition` artifact；App 用受限 WebView renderer 渲染。
4. `presentationMeta['dsh-go/portable']` — 本页的统一 envelope（**已实现**）。
5. `presentationMeta.html` / `widget.html` / `fragment` — 通用 HTML 片段（**规划中，尚未实现**）。
6. `presentationMeta.card` / `kind` — 结构化卡片（**规划中，尚未实现**）。
7. 普通工具行 — 没有可识别 UI 时保底展示。

解析器必须**跳过** 1–3，避免和现有原生/intelligent-ui 适配抢卡片、重复渲染。

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
- 分享时宿主把可序列化的 envelope 转成离屏截图；不依赖插件的 Web 前端状态。
- 任意 React 组件、依赖宿主路由或前端全局状态的插件不应进入该协议，应改投 `dsh-go/view` 或使用 WebView 岛。

## 当前 App 实现状态

`PortableUiAdapter`（`app/lib/state/intelligent_ui.dart`）已识别
`presentationMeta['dsh-go/portable']`，并把它转换成受限的智能 UI widget 卡片：

| kind | 输入 | 当前转换 |
|---|---|---|
| `html` | `html`、可选 `css`、可选 `title` | `<script>` 检查通过后生成 `{html, css, initialHeight: 48}` |
| `structured` | `title`、`fields[{label,value}]` | 生成简单 label/value HTML |
| `media` | `url`（仅接受 `https://`） | 生成 `<img>`，外部加载仍受 `policy` 的 `allowMedia`/`mediaOrigins` 限制 |

同一工具命中多个 UI 形态时的实际优先级已经由投影器统一处理：

1. `dsh-go/view`
2. `dsh-go/media`
3. `presentationMeta.ui`
4. `dsh-go/portable`

`dsh-go/portable` 生成的卡片与 intelligent-ui 卡片共用同一套：

- 聊天内卡片渲染、沉浸式 widget、原生快速路径（`Text` / `Stat` / `Table` / `Badge` / `Divider` / `List` / `Progress` / `Stack` / `Grid` / `Card`）；
- 分享面板与分享图片；
- 链接回放。

## 尚未实现

- 原始 `presentationMeta.html`、`presentationMeta.widget.html`、`presentationMeta.fragment` 的自动识别。
- 原始 `presentationMeta.card` / `kind` 结构化卡片。
- `structured` 里的 `metrics`、`tables`、`items`、`markdown`（当前只读 `title` + `fields`）。
- 分享快照中的远程媒体：离屏 WebView 默认禁网络，`media` kind 的远端图片可能加载不出（见 `plans/2026-11-13-dsh-go-intelligent-ui-handoff.md`）。

## 适配优先级

先做通用 `html` / `widget.html` 自动识别（覆盖最多现有插件），再做 `card` / `kind` 结构化适配，最后把协议写入 SDK 文档和插件模板。intelligent-ui 的 `ui` artifact 是优先级 3 的特例，已有完整实现。
