# deepseek-harness-intelligent-ui 卡片

[English](en/intelligent-ui.md)

`deepseek-harness-intelligent-ui` 是给 DSH Web 用的第三方插件：工具可以返回一棵声明式组件树（`ui_render`）、一个自包含的 HTML widget（`ui_render_widget`），或者由 markdown / catalog / widget 块组成的 composition（`ui_compose`），后续还能用 `ui_patch` 更新。dsh-go 在聊天里把这套 presentationMeta 投影成 WebView 卡片，而不是把它翻译成 `dsh-go/view` 原生组件。

## 怎么工作

1. 工具调用和结果仍走普通会话事件；`tool/call` 的 `arguments` 和 `tool/result` 的 `meta` 会随历史记录到达 App。
2. App 的 `IntelligentUiProjector`（`app/lib/state/intelligent_ui.dart`）按 `seq` 重放事件，接受 `meta.ok === true` 的 `ui_render` / `ui_render_widget` / `ui_compose` / `ui_patch`，并支持 `tool/ptc-dispatch` 子调用。它只接受结构合法的树和 composition，保持与上游便携协议一致的版本校验。
3. 卡片由 `app/lib/ui/chat/intelligent_ui/intelligent_ui_card.dart` 显示：把本地打包的 `assets/intelligent_ui/renderer.js` 内联到带 CSP 的本地 HTML 里，再通过 `postMessage` 桥接 resize、发送、下载和错误。
4. 工具调用本身仍显示为普通工具行；展开时显示卡片，折叠时卡片留在回合过程之外，和 `dsh-go/view` 工具卡的行为一致。

## 滚动与手势

- 卡片不注册 `EagerGestureRecognizer`，只注册 `LongPressGestureRecognizer`。按 Flutter 的手势仲裁规则，纵向拖动由外层聊天列表接管，因此在卡片任意位置上下滑都会滚动聊天页；点击、长按（选中文字/系统选择工具条）交给 WebView。
- 卡片内部不做纵向滚动，也不占用横向手势：移除表格、代码块、diff 的内部 `max-height` 和横向滚动，表格固定宽度并把单元格内容自动换行。这样既避免“表格里滑不动、页面也不动”的双重滚动冲突，也避免和手机端“左右滑动打开侧栏”的手势冲突。
- 卡片内容左右边距使用 8，尽量利用手机宽度；标题行仍沿用 `ChatCard` 的 16。
- 卡片高度仍受 `maxHeight` 限制；内容超出上限时由渲染器裁剪，后续可在不改变手势策略的前提下增加展开入口。

## 安全边界

- 不下载、不执行远端代码；renderer 是随 App 打包的固定版本（`app/assets/intelligent_ui/renderer.js`）。
- CSP 为 `default-src 'none'`；脚本、样式、图片只允许本地/data/blob，`connect-src 'none'`，`frame-src` 只允许 about/data/blob。
- 页面导航只放行 `about:blank`、`about:srcdoc`、`data:`；Android 侧关闭文件访问和内容访问，跨源访问保持 WebView 默认关闭，混合内容为 never。
- 卡片的发送按钮必须经过原生确认，且只对当前主机、当前会话、当前连接生效；一次点击只发送一次。
- 卡片高度限制在 100–4000 px，避免超大页面撑爆聊天。

## 兼容性

- 需要 `deepseek-harness-intelligent-ui` 0.2.15 或兼容的便携渲染器协议；不需要在 dsh-go 里安装该插件，插件仍安装在引擎侧。
- 只有聊天界面支持；网页版里的行为由插件自己的 Web 前端负责。
- dsh-go 不实现 `ui_patch` 的全部上游 catalog 校验规则，Dart 侧只做有界结构校验，具体组件树由 renderer 解释。
