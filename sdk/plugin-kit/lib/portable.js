// Portable UI 卡：dsh-go 的 portable 协议（docs/plugins/portable-ui.md）。
// 与 App 侧 app/lib/state/intelligent_ui.dart 的 PortableUiAdapter 同口径：长度一律按
// Dart 的 String.length（UTF-16 code unit）计，JS 的 String.length 与之等价，所以下面
// 直接用它比较和截断。零依赖（只用本包的 toLosslessJson）。

import { toLosslessJson } from './card.js'

/** 第 4 层 envelope 的键：`presentationMeta['dsh-go/portable']`。 */
export const PORTABLE_KEY = 'dsh-go/portable'

/**
 * 第 2 层媒体卡的键（`packages/dsh_client/lib/src/media_meta.dart` 的 `MediaMeta` v1）。
 * 那张卡认的是 `items`，只有 `url` 会解析成 null；而且它在 `presentationMeta` 里非 null
 * 时 App 直接跳过 portable 各层（第 1–3 层优先），所以 `portableMedia` 不用这个键，
 * 改用第 4 层的 `kind: 'media'`。这里只把它作为常量给作者比对。
 */
export const PORTABLE_MEDIA_KEY = 'dsh-go/media'

/** 单份 HTML 的上限（App `_maxHtmlChars`）：超了整卡不出，不截断。 */
export const PORTABLE_MAX_HTML_CHARS = 60_000

/** 标题上限（App `_maxTitleChars`）：超了留前 199 个字符加 `…`。 */
export const PORTABLE_MAX_TITLE_CHARS = 200

/** 单元格上限（App `_maxCellChars`）：超了留前 1999 个字符加 `…`。 */
export const PORTABLE_MAX_CELL_CHARS = 2_000

/** 表格行上限（App `_maxTableRows`，只数非空行）。 */
export const PORTABLE_MAX_TABLE_ROWS = 50

/** 表格列上限（App `_maxTableColumns`）。 */
export const PORTABLE_MAX_TABLE_COLUMNS = 12

/** 一张 widget 卡的字符总量上限（App `_validWidget` 的 `_maxArgumentChars`）。 */
export const PORTABLE_MAX_WIDGET_CHARS = 480_000

/** App 判定“带脚本”的正则：`<script`、`<script>`、`<script/>` 都算。 */
const SCRIPT = /<\s*\/?\s*script/i

/** 只认普通对象（App 用 `is Map` 判断）。 */
function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/** 不是数组时当空数组，省掉每处都写 Array.isArray。 */
function asArray(value) {
  return Array.isArray(value) ? value : []
}

/**
 * 标题：去空白，空串归一为 undefined，超 200 留前 199 加 `…`（App `_clipTitle`）。
 * @param {unknown} value
 * @returns {string | undefined}
 */
function clipTitle(value) {
  if (typeof value !== 'string') return undefined
  const title = value.trim()
  if (title === '') return undefined
  return title.length <= PORTABLE_MAX_TITLE_CHARS ? title : title.slice(0, PORTABLE_MAX_TITLE_CHARS - 1) + '…'
}

/**
 * 单元格：只认字符串 / 数字 / 布尔（App `_cellText`），其余给 undefined；超 2000 留前 1999
 * 加 `…`。null 与对象、数组都算“没有值”。
 * @param {unknown} value
 * @returns {string | undefined}
 */
function cellText(value) {
  let text
  if (typeof value === 'string') text = value
  else if (typeof value === 'number') text = Number.isFinite(value) ? String(value) : ''
  else if (typeof value === 'boolean') text = String(value)
  else return undefined
  return text.length <= PORTABLE_MAX_CELL_CHARS ? text : text.slice(0, PORTABLE_MAX_CELL_CHARS - 1) + '…'
}

/** `trend` 只认 up / down / flat，其余当没给（App `_trend`）。 */
function asTrend(value) {
  return value === 'up' || value === 'down' || value === 'flat' ? value : undefined
}

/**
 * 结构化卡片（第 4 层 `kind: 'structured'`，可用键与 App `_structuredHtml` 一致：
 * title / fields / metrics / tables / items / markdown）。逐项校验并钳制，全部不合格时返回 null。
 *
 * 命名为 "card" 是因为它就是 App 的第 6 层“结构化卡片”；envelope 里写 `structured`，
 * 因为第 4 层的 kind 只认 html / structured / media，别的值会整卡不出（终局，不再往下找）。
 *
 * App 还认 charts / accent / style，本 builder 不构造这三项。
 *
 * @param {{ title?: unknown, fields?: unknown, metrics?: unknown, tables?: unknown, items?: unknown, markdown?: unknown } | null | undefined} spec
 * @param {{ title?: unknown, policy?: unknown }} [options] spec 没给标题时的兜底标题；policy 原样进 envelope
 * @returns {{ 'dsh-go/portable': Record<string, import('../types/index.js').JsonValue> } | null}
 */
export function portableCard(spec, options) {
  if (!isPlainObject(spec)) return null
  const card = { kind: 'structured' }
  const title = clipTitle(spec.title) ?? clipTitle(options?.title)
  if (title !== undefined) card.title = title

  const fields = []
  for (const field of asArray(spec.fields)) {
    if (!isPlainObject(field)) continue
    const label = cellText(field.label) ?? ''
    const value = cellText(field.value) ?? ''
    if (label === '' && value === '') continue
    fields.push({ label, value })
  }
  if (fields.length > 0) card.fields = fields

  const metrics = []
  for (const metric of asArray(spec.metrics)) {
    if (!isPlainObject(metric)) continue
    const label = cellText(metric.label) ?? ''
    const value = cellText(metric.value) ?? ''
    if (label === '' && value === '') continue
    const entry = { label, value }
    const delta = cellText(metric.delta)
    if (delta !== undefined && delta !== '') entry.delta = delta
    const trend = asTrend(metric.trend)
    if (trend !== undefined) entry.trend = trend
    metrics.push(entry)
  }
  if (metrics.length > 0) card.metrics = metrics

  const tables = []
  for (const table of asArray(spec.tables)) {
    if (!isPlainObject(table)) continue
    const columns = []
    for (const column of asArray(table.columns)) {
      if (columns.length >= PORTABLE_MAX_TABLE_COLUMNS) break
      // 不认识的列值当空表头，但仍占一列（App 也是这样）。
      columns.push(cellText(column) ?? '')
    }
    if (columns.length === 0) continue
    const rows = []
    for (const row of asArray(table.rows)) {
      if (rows.length >= PORTABLE_MAX_TABLE_ROWS) break
      const cells = asArray(row)
      // 空行既不输出也不计入 50 行。
      if (cells.length === 0) continue
      const line = []
      // 单元格按表头列数截断，表头和每行的列数才一致。
      for (let i = 0; i < cells.length && i < columns.length; i += 1) line.push(cellText(cells[i]) ?? '')
      rows.push(line)
    }
    const entry = { columns, rows }
    const heading = clipTitle(table.title)
    if (heading !== undefined) entry.title = heading
    tables.push(entry)
  }
  if (tables.length > 0) card.tables = tables

  const items = []
  for (const item of asArray(spec.items)) {
    if (typeof item === 'string') {
      // 裸字符串不套单元格钳制（App 直接转义后进 <li>），但计入总量预检。
      if (item !== '') items.push(item)
      continue
    }
    if (!isPlainObject(item)) continue
    const label = cellText(item.label) ?? ''
    const value = cellText(item.value) ?? ''
    if (label === '' && value === '') continue
    items.push({ label, value })
  }
  if (items.length > 0) card.items = items

  if (typeof spec.markdown === 'string' && spec.markdown.trim() !== '') card.markdown = spec.markdown

  // 什么都画不出来时 App 会拿到空 buffer，等于不产卡。
  if (Object.keys(card).length === 1) return null
  // App 把结构化数据渲染成 HTML 后 > 60000 就整卡丢弃。文本合计已经超了必然超；
  // 没超也可能因为标记开销被 App 丢，那一步的精确长度只有 App 侧算得出来。
  if (cardChars(card) > PORTABLE_MAX_HTML_CHARS) return null
  const policy = asPolicy(options?.policy)
  if (policy !== undefined) card.policy = policy
  return { [PORTABLE_KEY]: card }
}

/**
 * 卡片里所有文本的字符合计（UTF-16），用来做 60000 上限的保守预检。
 * @param {Record<string, any>} card
 */
function cardChars(card) {
  let total = card.title?.length ?? 0
  for (const field of card.fields ?? []) total += field.label.length + field.value.length
  for (const metric of card.metrics ?? []) total += metric.label.length + metric.value.length + (metric.delta?.length ?? 0)
  for (const table of card.tables ?? []) {
    total += table.title?.length ?? 0
    for (const column of table.columns) total += column.length
    for (const row of table.rows) for (const cell of row) total += cell.length
  }
  for (const item of card.items ?? []) total += typeof item === 'string' ? item.length : item.label.length + item.value.length
  total += card.markdown?.length ?? 0
  return total
}

/**
 * HTML 收口：必须是非空字符串、不超 60000、不带 script 标签（App `_htmlOf`）。
 * App 还会在入库前摘掉 on*= 事件属性与 javascript: 之类的 scheme；SDK 不替作者改写，
 * 这里只做“能给出去”的判定，消毒留给 App（也是唯一有效的那一层）。
 * @param {unknown} html
 * @returns {string | undefined}
 */
function htmlText(html) {
  if (typeof html !== 'string') return undefined
  const text = html.trim()
  if (text === '' || text.length > PORTABLE_MAX_HTML_CHARS) return undefined
  if (SCRIPT.test(text)) return undefined
  return text
}

/** `html + css` 不能超过一张 widget 卡的字符总量。 */
function fitsWidget(text, css) {
  return text.length + (typeof css === 'string' ? css.length : 0) <= PORTABLE_MAX_WIDGET_CHARS
}

/**
 * envelope / 外层 Meta 的 `policy`（宿主决定联网与媒体放行的地方）。
 *
 * App 只读 `allowMedia` / `mediaOrigins`（还有 `mapTiles` / `openLinkOrigins` 等），
 * 不认识的多余键一律忽略，所以这里不做键白名单，只保证给出去的是无损 JSON 的普通对象：
 * 不是普通对象、带函数、循环引用或 BigInt 时整段丢掉（`undefined`），不会让工具调用失败。
 * @param {unknown} value
 * @returns {Record<string, import('../types/index.js').JsonValue> | undefined}
 */
function asPolicy(value) {
  if (!isPlainObject(value)) return undefined
  const policy = toLosslessJson(value)
  if (!isPlainObject(policy)) return undefined
  return Object.keys(policy).length === 0 ? undefined : /** @type {any} */ (policy)
}

/**
 * 第 4 层 `kind: 'html'`：自包含 HTML，可带 css 与标题。
 * @param {unknown} html
 * @param {{ css?: unknown, title?: unknown, policy?: unknown }} [options]
 * @returns {{ 'dsh-go/portable': Record<string, import('../types/index.js').JsonValue> } | null}
 */
export function portableHtml(html, options) {
  const text = htmlText(html)
  if (text === undefined) return null
  if (!fitsWidget(text, options?.css)) return null
  const envelope = { kind: 'html', html: text }
  if (typeof options?.css === 'string' && options.css !== '') envelope.css = options.css
  const title = clipTitle(options?.title)
  if (title !== undefined) envelope.title = title
  const policy = asPolicy(options?.policy)
  if (policy !== undefined) envelope.policy = policy
  return { [PORTABLE_KEY]: envelope }
}

/**
 * 第 5 层 `widget.html`（`presentationMeta.widget`）。App 从这里读 `html` / `css` /
 * `title`，和 `kind: 'html'` 一样会带上自己的 css，区别只在键位：这一层是裸 meta。
 * @param {unknown} html
 * @param {{ css?: unknown, title?: unknown, policy?: unknown }} [options]
 * @returns {{ widget: Record<string, import('../types/index.js').JsonValue>, policy?: Record<string, import('../types/index.js').JsonValue> } | null}
 */
export function portableWidget(html, options) {
  const text = htmlText(html)
  if (text === undefined) return null
  if (!fitsWidget(text, options?.css)) return null
  const widget = { html: text }
  if (typeof options?.css === 'string' && options.css !== '') widget.css = options.css
  const title = clipTitle(options?.title)
  if (title !== undefined) widget.title = title
  const meta = { widget }
  // 这一层不产 envelope，policy 直接挂在 presentationMeta 上（App 从 meta['policy'] 读）。
  const policy = asPolicy(options?.policy)
  if (policy !== undefined) meta.policy = policy
  return meta
}

/**
 * 第 5 层 `fragment`：裸 HTML 片段。这一层 App 不读外层 css（只有 `widget.html` 和
 * `kind: html` 带 css），所以这里也不收 css。
 * @param {unknown} html
 * @param {{ title?: unknown, policy?: unknown }} [options]
 * @returns {{ fragment: string, title?: string, policy?: Record<string, import('../types/index.js').JsonValue> } | null}
 */
export function portableFragment(html, options) {
  const text = htmlText(html)
  if (text === undefined) return null
  const fragment = { fragment: text }
  const title = clipTitle(options?.title)
  if (title !== undefined) fragment.title = title
  const policy = asPolicy(options?.policy)
  if (policy !== undefined) fragment.policy = policy
  return fragment
}

/**
 * 第 4 层 `kind: 'media'`：只接受 https:// 的图片地址，App 会拼成 `<img>`（先做属性转义）。
 *
 * 聊天卡片 iframe 的 CSP 由 `policy` 决定（app/lib/ui/chat/intelligent_ui/intelligent_ui_card.dart:
 * `img-src data: blob:` 之外，只有 `policy.allowMedia === true` 才追加 `https:` 或
 * `policy.mediaOrigins` 的 https origin）。也就是说不传 policy 时 https 图片在聊天里加载不出来；
 * 要用就得自己给 `{ allowMedia: true }`（或 `mediaOrigins: ['https://cdn.example.com']`）。
 * 这个 envelope 只能表达图片；视频要用第 2 层的 `dsh-go/media` 媒体卡。
 *
 * @param {unknown} url
 * @param {{ title?: unknown, policy?: unknown }} [options]
 * @returns {{ 'dsh-go/portable': Record<string, import('../types/index.js').JsonValue> } | null}
 */
export function portableMedia(url, options) {
  if (typeof url !== 'string') return null
  // App 是“先判前缀再 trim”，SDK 先 trim 再判，收口后给出的 url 一定能过 App 那一关。
  const trimmed = url.trim()
  if (!trimmed.startsWith('https://')) return null
  if (trimmed.length <= 'https://'.length) return null
  const envelope = { kind: 'media', url: trimmed }
  const title = clipTitle(options?.title)
  if (title !== undefined) envelope.title = title
  const policy = asPolicy(options?.policy)
  if (policy !== undefined) envelope.policy = policy
  return { [PORTABLE_KEY]: envelope }
}

/**
 * 把某个 portable builder 包成 DSH 工具的 `output.presentationMeta` 工厂。
 *
 * DSH 在 presentationMeta 抛错或给出非 lossless JSON 时会判整个工具调用失败，
 * 所以这层包装永不抛错：builder 抛错、返回 null（不合格的输入）、返回非普通对象
 * 或循环引用，都退化成“只剩额外键”的结果；一个键都没有时就是 `{}`（没有卡，
 * App 回到普通工具行）。`meta` 用于附加自己的键，同名键以 builder 的结果为准。
 *
 * @template A, V
 * @param {(args: A, value: V) => Record<string, unknown> | null | undefined} build
 * @param {{ meta?: (args: A, value: V) => Record<string, unknown>, onError?: (error: unknown) => void }} [options]
 * @returns {(args: A, value: V) => Record<string, import('../types/index.js').JsonValue>}
 */
export function portableMeta(build, options = {}) {
  return (args, value) => {
    let extra = {}
    try {
      if (options.meta) extra = toLosslessJson(options.meta(args, value)) ?? {}
      if (!isPlainObject(extra)) extra = {}
    } catch (error) {
      options.onError?.(error)
      extra = {}
    }
    try {
      const built = toLosslessJson(build(args, value))
      if (!isPlainObject(built)) return extra
      return { ...extra, ...built }
    } catch (error) {
      options.onError?.(error)
      return extra
    }
  }
}
