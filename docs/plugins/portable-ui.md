# Portable 聊天 UI 协议（草案）

[English](en/portable-ui.md)

dsh-go 不要求每个 UI 插件都适配自己的原生组件；聊天消息里的 UI 可以由宿主按一个统一的 portable 优先级渲染：

1. `presentationMeta['dsh-go/view']` — dsh-go 原生视图，已有的 16 种组件与媒体卡优先使用。
2. `presentationMeta.ui` — intelligent-ui 的 `declarative` / `widget` / `composition` artifact，App 用 WebView renderer 渲染。
3. `presentationMeta.html` / `widget.html` — 通用 HTML 片段，App 用一个受限 WebView 卡片渲染；只允许内联 CSS、图片和受限交互。
4. `presentationMeta.card` / `kind` — 结构化字段卡（title/fields/preview），由 App 原生渲染。
5. 普通工具行 — 没有可识别 UI 时保底展示。

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
- 分享时宿主把可序列化的 envelope 转成 Markdown/离屏截图；不依赖插件的 Web 前端状态。
- 任意 React 组件、依赖宿主路由或前端全局状态的插件不应进入该协议，应改投 `dsh-go/view` 或使用 WebView 岛。

## 适配优先级

先做 `html/widget.html` 通用适配器（覆盖最多现有插件），再做 `card/kind` 结构化适配，最后把协议写入 SDK 文档和插件模板。intelligent-ui 的 `ui` artifact 是优先级 2 的特例，已有完整实现。
