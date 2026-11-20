# deepseek-harness-intelligent-ui 组件覆盖

[English](en/intelligent-ui-coverage.md)

`deepseek-harness-intelligent-ui` 的便携 renderer 自带全部 catalog 组件。dsh-go 在 Android WebView 里加载同一份 renderer，所以下列 39 种组件都能在手机聊天卡片中渲染；差异只在外部资源与交互上。

| 组件 | 手机渲染 | 备注 |
|---|---|---|
| Card / Stack / Grid / Tabs | 完整 | 布局、Tab 切换均可用 |
| Text / Code / Alert / Badge / Divider | 完整 | 支持 Markdown 子集 |
| Stat / Progress / List / Table | 完整 | 表格自动换行，不抢占左右手势 |
| Chart / Scatter / Heatmap / Plot | 完整 | 纯 SVG/canvas，无外部依赖 |
| CodeDiff / FileTree / JsonView | 完整 | 只读展示 |
| Button / Choice / Form | 完整 | 交互经 `sendPrompt` 桥；只读回放不发送 |
| Timeline | 完整 | 只读展示 |
| Math | 完整 | offline renderer 内置 KaTeX |
| Mermaid | 完整 | offline renderer 内置 Mermaid |
| Accordion / Steps / KeyValue / EmptyState / FollowUp / Sources / Segmented / Calendar / Audio | 完整 | 0.2.16 新增；Segmented 可驱动 computed，Calendar 支持 day/week/agenda（显式 IANA 时区），Audio 受 mediaOrigins/CSP 控制 |
| Map | 轮廓完整 | 内置世界轮廓；瓦片由 `policy.mapTiles` 控制 |
| Image / Gallery / Video | 取决于 policy | `policy.allowMedia`/`mediaOrigins` 允许时加载远程资源，否则显示占位；分享快照按同一 policy 联网，并等图片加载完再截图 |
| 自定义 `ui_render_widget` | 完整 | 任意 HTML/CSS（不含脚本）；分享用离屏 WebView 截图 |

## 交互与状态

- Choice/Form/Tab/CodeView/Plot/Table 的本地状态由 renderer 写入 `localStorage`。dsh-go 为 WebView 使用固定 origin `https://dsh.local/`，卡片重建、滚动和 App 重启后状态仍保留。
- 卡片默认全宽展示；聊天页 widget 卡使用沉浸式模式（不套外层 `ChatCard`），右上角可进入全屏查看长表格、图表和地图。
- 分享图片和链接回放使用同一份离线 renderer 的离屏 WebView 快照，字体、字号、粗细与聊天卡片一致；只读卡片不能发消息。

## 测试

`app/test/state/intelligent_ui_catalog_coverage_test.dart` 用一棵包含全部 39 种组件的树验证投影器准入；其余行为由 renderer 自身的单元测试和真机截图验证。
