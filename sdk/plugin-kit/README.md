# @dsh-go/plugin-kit

[English](README.en.md) | 中文

给 dsh-go 原生插件作者的工具包。零运行时依赖，Node 22.19+。不发布到 npm：在仓库里引用，或把需要的文件拷进你的插件。

| 件 | 入口 | 用途 |
|---|---|---|
| 类型 | `types/index.d.ts`（`types/schema.d.ts` 由 schema 生成） | 视图、清单、效果、`ctx.dshGo`、`caps` 的 TypeScript 类型 |
| 组件构造函数 | `stack()` `row()` `text()` `metric()` `chart()` `list()` `keyValue()` `progress()` `table()` `actions()` `image()` … `bind()` `action()` | 产出普通 JSON 节点，去掉 `undefined` 属性 |
| 工具卡 | `toolCard(build)` | 包住 `presentationMeta`：不抛错、无损 JSON、≤ 8 KiB |
| 能力判断 | `hasComponent` `hasSurface` `appAtLeast` `localize` `adaptView` | 按 App 能力和语言降级 |
| 效果 | `effects.insert()` … `effects.deferred()`；`checkEffects` `checkPending` | 构造效果；用桥接自己的代码检查 handler 返回值 |
| 测试宿主 | `@dsh-go/plugin-kit/testing` → `createTestHost()` | 不起 DSH 跑你的 `apply(ctx)`：清单解析、invoke、视图、数据推送、延后效果，结果和桥接一致 |
| 检查 | `bin/check.mjs`；`@dsh-go/plugin-kit/check` | 清单（桥接的解析器）+ 视图（App 解析器的逐行孪生，措辞同 App）+ `--load` 加载宿主半侧 |
| portable 卡 | `@dsh-go/plugin-kit/portable` | 不绑视图的出卡协议（第 4–5 层）：结构化 / HTML / widget / 片段 / 媒体，按 App 的上限钳制，不合格给 `null` |
| Schema | `schema/*.schema.json` | 协议与视图的机器可读定义，`lib/json-schema.js` 可直接校验 |

## portable 卡（第 4–5 层）

`presentationMeta` 上有一条不绑视图的通用出卡协议（[docs/plugins/portable-ui.md](../../docs/plugins/portable-ui.md)）。App 按 7 层优先级识别，命中即停：第 1–3 层是 `dsh-go/view`、`dsh-go/media`、`ui`，只要它们存在，portable 的键就不再看。

| 层 | 键 | 本包 |
|---|---|---|
| 4 | `dsh-go/portable`，`kind` 取 `html` / `structured` / `media` | `portableHtml()` `portableCard()` `portableMedia()` |
| 5 | `html` / `widget.html` / `fragment` | `portableWidget()` `portableFragment()`（裸 `html` 键位就是字符串，直接写） |

```js
import { portableMeta, portableCard } from '@dsh-go/plugin-kit/portable'

export const meta = portableMeta((_args, value) => portableCard({
  title: '今日用量',
  metrics: [{ label: '请求', value: value.calls, delta: '+12%', trend: 'up' }],
  tables: [{ columns: ['模型', '次数'], rows: [['flash', 12], ['pro', 3]] }],
  markdown: '超过 **100** 条会限流。',
}))
// meta(...) → { 'dsh-go/portable': { kind: 'structured', … } }
```

| 函数 | 产出 |
|---|---|
| `portableCard(spec, { title, policy })` | `{ 'dsh-go/portable': { kind: 'structured', title?, fields?, metrics?, tables?, items?, markdown?, policy? } }` |
| `portableHtml(html, { css, title, policy })` | `{ 'dsh-go/portable': { kind: 'html', html, css?, title?, policy? } }` |
| `portableWidget(html, { css, title, policy })` | `{ widget: { html, css?, title? }, policy? }` |
| `portableFragment(html, { title, policy })` | `{ fragment, title?, policy? }` |
| `portableMedia(url, { title, policy })` | `{ 'dsh-go/portable': { kind: 'media', url, title?, policy? } }` |
| `portableMeta(build, { meta, onError })` | 把上面任意一个包成 `(args, value) => Record<string, JsonValue>` |

- 五个 builder 只做“能不能给出去”的判定：不合格返回 `null`，不抛错。`portableMeta` 再兜一层：builder 抛错、返回 `null` 或非普通对象（含循环引用）都退化成只有 `options.meta` 的额外键，一个键都没有时就是 `{}`（没有卡，App 回到普通工具行）。同名键以 builder 的结果为准。
- 长度口径与 App 一致（Dart `String.length`，即 UTF-16 code unit，JS 的 `String.length` 等价）：标题 200（超了留前 199 个字符加 `…`）、单元格 2000（同上）、表格 50 行 × 12 列（空行不计，超出表头的单元格丢弃）、单份 HTML 60000（超了整卡不出，**不截断**）、一张 widget 卡的 html + css 合计 480000。
- 安全口径：HTML 必须自包含，**不执行远程脚本**——带 `<script`（也拦 `<script/>`、`<ScRiPt>`）的 HTML 直接 `null`。App 入库前还会再消毒一遍：摘掉 `on*=` 事件属性（含 `…/onerror=` 这种斜杠写法）、`javascript:` / `vbscript:` / `data:text/html` scheme，删掉 `meta`/`base`/`link`/`object`/`embed`/`iframe`/`frame`/`frameset`，渲染器再加 DOMPurify 与 `default-src 'none'` 的 CSP。SDK 不替你改写内容，消毒只有 App 侧那一层有效。
- 媒体只收 `https://`。聊天卡的 iframe CSP 由 `policy` 决定：默认只有 `img-src data: blob:`，https 图片在聊天里加载不出来；给 `{ allowMedia: true }` 才追加 `https:`（或在 `mediaOrigins` 里列白名单 origin），分享快照同样按 `policy` 放行。第 4 层把 `policy` 写在 envelope 里，第 5 层写在 `presentationMeta` 上——`portableCard()` `portableHtml()` `portableWidget()` `portableFragment()` `portableMedia()` 的 `options.policy` 都已接线。App 读 `allowMedia` / `mediaOrigins` / `mapTiles` / `openLinkOrigins`，本包不设键白名单，其余键照传（不是普通对象、含函数或循环引用时整段丢掉，不影响出卡）。这个 envelope 只能表达图片，视频要用第 2 层的 `dsh-go/media` 媒体卡（那张卡认 `items`，所以本包只导出 `PORTABLE_MEDIA_KEY` 常量，不构造它）。
- App 的结构化卡还认 `charts` / `accent` / `style`，这几个 builder 不构造它们；需要时按文档手写 envelope。

## check

```sh
node sdk/plugin-kit/bin/check.mjs <插件目录 | package.json | 视图.json | -> [--load] [--json] [--lang en] [--budget toolCard|panel|strip] [--app x.y.z]
```

```
dsh-go-example-quick 0.1.0
  原生界面能显示（胶囊 2 · 菜单 2）
  已加载宿主半侧：4 项可用
```

```
broken-demo 0.0.1
  错误 /dsh/bundle/patch：找不到组合包补丁文件 ./missing.yml
  原生界面能显示（胶囊 2 · 菜单 1 · 状态条 1 · 面板 1）
    错误 /dshGo/contributes/composer.actions/1/id：id a is already used by composer.actions
    提示 /dshGo/contributes/composer.actions/0/label：exceeds 10 characters for locale en-US; truncated
    提示 /dshGo/icon：不认识的图标，已换成默认图标
  已加载宿主半侧：1 项可用
    错误 /runtime/inject：写成了 ctx.inject(['dshGo?'])：cordis 没有可选依赖语法，这个回调永远不执行，改成 ['dshGo']
  视图 views/p.json（面板）：能显示，3 处问题
    错误 view.children[0].type：未知组件 "gauge"；可用：stack, row, text, …
    错误 view.children[1].value：应该是字符串或数字
    提示 view.children[2].items[0].action：动作 id "bad id" 不合规，这个元素不可点
```

| 退出码 | 含义 |
|---|---|
| 0 | 没有错误（可以有提示） |
| 1 | 有条目不生效 |
| 2 | 原生部分整体不显示（清单无效、协议不支持），或视图整块无法显示，或宿主半侧加载失败 |
| 3 | 读不了文件 |

- 清单问题：路径是相对 `package.json` 的 JSON Pointer，说明是桥接给开发者的英文原文（App 插件详情页显示的也是它）；App 自己加的（图标不认识）是中文。
- 视图问题：路径和措辞与 App 插件详情页逐字相同（`lib/messages.json` 从 App 的 ARB 同步，`test/parity/` 里的用例 App 侧也在跑）。
- 中英文各量一遍文字长度；`--load` 在临时 `DSH_HOME` 里加载你的代码，不碰真的 DSH 主目录。

`--load` 从空配置开始，先通过插件自身 `Config` 的 Standard Schema 校验并应用默认值，再调用 `apply`；未导出 `Config` 时传入空对象。与 Host 一样，只接受同步配置校验；必填字段没有默认值、校验抛错或异步校验都会报告加载失败，不调用 `apply`。检查器不读取用户的主机配置。

参数值必须完整：`--lang zh|en`、`--budget toolCard|panel|strip`、`--app x.y.z`。参数错误返回 3；带 `--json` 时也输出可解析的诊断对象。多个目标会分别检查，标准输入读取失败不会阻止后面的文件。以 `-` 开头的文件名放在 `--` 后面，例如 `node bin/check.mjs -- --view.json`。

`package.json` 必须是 JSON 对象；错误的 `contributes.panels` 会保留桥接诊断。静态视图使用桥接的包内路径规则，拒绝的包外路径和符号链接不会再被当成 App 视图读取。这是检查行为的一致性约束，`--load` 仍会执行插件自己的代码，不是代码沙箱。

## 测试宿主

```js
import { createTestHost } from '@dsh-go/plugin-kit/testing'
import { apply } from '../lib/index.js'

const host = createTestHost({ dir: pluginDir, services: { sessions } })
apply(host.ctx)
host.contributions()                                                   // App 收到的这一行
await host.invoke('translate', { context: { clipboard: '你好' } })     // { effects, pending?, settled? }
await host.view('usage', { sessionId: 's1' })                          // { view, stats }
const feed = host.subscribe('today', { sessionId: 's1' })              // feed.data / feed.history
host.emitEvent('session/event', session, event)
```

## 维护

| 脚本 | 什么时候跑 |
|---|---|
| `node scripts/gen-types.mjs` | schema 改了 |
| `node scripts/sync-bridge.mjs` | 桥接 `runtime/bridge/dsh-go-bridge/lib/native/{limits,util,effects,manifest,capabilities}.js` 改了 |
| `node scripts/sync-messages.mjs` | App 的 `view` / `plugview` ARB 改了 |
| `node scripts/gen-parity.mjs` | 改了 `lib/view-check.js`（App 解析器改了之后）；审过差异再提交 |
| `node scripts/sync-skill.mjs` | 以上任何一项，或 `skill/` 改了：重建 App 自带的 `dsh-go-plugin` 技能 |
| `scripts/wire-check.sh` | 想用真实桥接报文验 schema：协议集成测试和示例端到端都走录制代理，逐条校验 |

`npm test`（`node --test`）会检查以上产物是否过期。类型检查需要 `npm install`（只装 devDependency `typescript`）。

## 许可

MIT © DSH-TUI (ccch1mneyyy)
