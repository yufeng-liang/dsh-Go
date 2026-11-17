// 手写的 portable 卡类型（不是 gen-types.mjs 生成物）：对应 lib/portable.js。
// 协议：docs/plugins/portable-ui.md；实现口径：app/lib/state/intelligent_ui.dart 的 PortableUiAdapter。
import type { JsonValue } from './index.js'

/** 第 4 层 envelope 的键。 */
export const PORTABLE_KEY: 'dsh-go/portable'
/** 第 2 层媒体卡的键；portableMedia 不用它（那张卡认 items，不认裸 url）。 */
export const PORTABLE_MEDIA_KEY: 'dsh-go/media'

/** 单份 HTML 上限，超了不产卡。 */
export const PORTABLE_MAX_HTML_CHARS: 60000
/** 标题上限，超了留前 199 个字符加 `…`。 */
export const PORTABLE_MAX_TITLE_CHARS: 200
/** 单元格上限，超了留前 1999 个字符加 `…`。 */
export const PORTABLE_MAX_CELL_CHARS: 2000
/** 表格行上限，只数非空行。 */
export const PORTABLE_MAX_TABLE_ROWS: 50
/** 表格列上限。 */
export const PORTABLE_MAX_TABLE_COLUMNS: 12
/** 一张 widget 卡的字符总量上限。 */
export const PORTABLE_MAX_WIDGET_CHARS: 480000

/** 单元格能表达的值：字符串、数字、布尔。其他类型按空串处理。 */
export type PortableCell = string | number | boolean

/** 指标的趋势；只影响颜色，其他值被丢掉。 */
export type PortableTrend = 'up' | 'down' | 'flat'

/** 一条 `label` / `value` 行，fields、metrics、items 共用。 */
export interface PortableField {
  label?: PortableCell | null
  value?: PortableCell | null
}

/** 一张指标卡：`label` + 大字 `value`，可带 `delta` 与趋势。 */
export interface PortableMetric extends PortableField {
  delta?: PortableCell | null
  trend?: PortableTrend | null
}

/** 一张表：表头列最多 12，数据行最多 50（空行不计），单元格按表头列数截断。 */
export interface PortableTable {
  title?: string | null
  columns?: readonly (PortableCell | null)[] | null
  rows?: readonly (readonly (PortableCell | null)[])[] | null
}

/** 列表项：字符串，或 `label` / `value` 对（两者都空时丢掉）。 */
export type PortableItem = string | PortableField

/** 结构化卡片的输入。全部为空时不产卡。 */
export interface PortableCardSpec {
  title?: string | null
  fields?: readonly PortableField[] | null
  metrics?: readonly PortableMetric[] | null
  tables?: readonly PortableTable[] | null
  items?: readonly PortableItem[] | null
  markdown?: string | null
}

/**
 * 宿主 policy（第 4 层写在 envelope 里，第 5 层写在 presentationMeta 上）。
 * 键不完备：App 读 `allowMedia` / `mediaOrigins` / `mapTiles` / `openLinkOrigins`，
 * 其他键照传不管——原样交给宿主总比 SDK 猜白名单安全。
 */
export type PortablePolicy = Record<string, JsonValue>

/** 只带标题与 policy 的选项。 */
export interface PortableTitleOptions {
  /** 标题；去空白、空串丢掉、超 200 留 `…`。 */
  title?: string | null
  /** 非普通对象、含函数 / 循环引用 / BigInt 时整段丢掉，不影响出卡。 */
  policy?: PortablePolicy | null
}

/** HTML 类 builder 的选项：除标题外还能带 css。 */
export interface PortableHtmlOptions extends PortableTitleOptions {
  css?: string | null
}

/** `portableMeta` 的选项，与 `toolCard` 同款。 */
export interface PortableMetaOptions<A, V> {
  /** 和卡片并列的额外 meta 键；卡片自己的键优先。 */
  meta?: (args: A, value: V) => Record<string, unknown>
  /** 只看错误，不改输出：包装器本身永不抛错。 */
  onError?: (error: unknown) => void
}

/** 第 4 层 envelope：`kind` 取 html / structured / media（App 只认这三个）。 */
export type PortableEnvelopeMeta = { 'dsh-go/portable': Record<string, JsonValue> }

/** 第 5 层 `widget.html`。 */
export interface PortableWidgetMeta {
  widget: { html: string; css?: string; title?: string }
  policy?: PortablePolicy
}

/** 第 5 层 `fragment`。 */
export interface PortableFragmentMeta {
  fragment: string
  title?: string
  policy?: PortablePolicy
}

/**
 * 结构化卡片：`{ 'dsh-go/portable': { kind: 'structured', … } }`。
 * 逐项钳制，全部不合格或文本总量超 60000 时为 null。
 */
export function portableCard(spec: PortableCardSpec | null | undefined, options?: PortableTitleOptions): PortableEnvelopeMeta | null

/** 第 4 层 `kind: 'html'`：非空、≤ 60000、不含 script，否则 null。 */
export function portableHtml(html: string | null | undefined, options?: PortableHtmlOptions): PortableEnvelopeMeta | null

/** 第 5 层 `widget.html`：同 `portableHtml` 的校验，键位是裸 `presentationMeta.widget`。 */
export function portableWidget(html: string | null | undefined, options?: PortableHtmlOptions): PortableWidgetMeta | null

/** 第 5 层 `fragment`：裸 HTML 片段，不带 css。 */
export function portableFragment(html: string | null | undefined, options?: PortableTitleOptions): PortableFragmentMeta | null

/** 第 4 层 `kind: 'media'`：只接受 https:// 的图片地址。 */
export function portableMedia(url: string | null | undefined, options?: PortableTitleOptions): PortableEnvelopeMeta | null

/**
 * 包住 builder 产出 `presentationMeta`。永不抛错：builder 抛错、返回 null 或非对象时给出
 * `meta` 的额外键（默认 `{}`），卡片自己的键优先。
 */
export function portableMeta<A, V>(
  build: (args: A, value: V) => PortableEnvelopeMeta | PortableWidgetMeta | PortableFragmentMeta | Record<string, unknown> | null | undefined,
  options?: PortableMetaOptions<A, V>,
): (args: A, value: V) => Record<string, JsonValue>
