// portable 卡 builder 的用例：数据形状、长度钳制、安全判定、包装器不抛错。
// 口径一律与 App 侧 app/lib/state/intelligent_ui.dart 的 PortableUiAdapter 对齐。
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  portableCard, portableHtml, portableWidget, portableFragment, portableMedia, portableMeta,
  PORTABLE_KEY, PORTABLE_MEDIA_KEY,
  PORTABLE_MAX_HTML_CHARS, PORTABLE_MAX_TITLE_CHARS, PORTABLE_MAX_CELL_CHARS,
  PORTABLE_MAX_TABLE_ROWS, PORTABLE_MAX_TABLE_COLUMNS,
} from '../lib/portable.js'
import { toLosslessJson } from '../lib/card.js'
import * as entry from '../lib/index.js'

test('常量与 App 的上限一致', () => {
  assert.equal(PORTABLE_KEY, 'dsh-go/portable')
  assert.equal(PORTABLE_MEDIA_KEY, 'dsh-go/media')
  assert.equal(PORTABLE_MAX_HTML_CHARS, 60000)
  assert.equal(PORTABLE_MAX_TITLE_CHARS, 200)
  assert.equal(PORTABLE_MAX_CELL_CHARS, 2000)
  assert.equal(PORTABLE_MAX_TABLE_ROWS, 50)
  assert.equal(PORTABLE_MAX_TABLE_COLUMNS, 12)
})

test('入口转发 portable 导出', () => {
  assert.equal(entry.portableCard, portableCard)
  assert.equal(entry.portableMeta, portableMeta)
  assert.equal(entry.PORTABLE_KEY, PORTABLE_KEY)
})

test('policy 原样进 envelope，非对象与循环引用被丢掉', () => {
  const policy = { allowMedia: true, mediaOrigins: ['https://cdn.example.com'], nested: { mapTiles: { url: 'https://tiles.example.com/{z}/{x}/{y}.png' } } }
  const html = portableHtml('<p>hi</p>', { policy })
  assert.deepEqual(html?.[PORTABLE_KEY].policy, policy)

  const card = portableCard({ title: 'T', fields: [{ label: 'a', value: 1 }] }, { policy })
  assert.deepEqual(card?.[PORTABLE_KEY].policy, policy)

  const media = portableMedia('https://cdn.example.com/a.png', { policy: { allowMedia: true } })
  assert.deepEqual(media?.[PORTABLE_KEY].policy, { allowMedia: true })

  const widget = portableWidget('<p>hi</p>', { policy: { allowMedia: true } })
  assert.deepEqual(widget?.policy, { allowMedia: true })
  assert.deepEqual(widget?.widget, { html: '<p>hi</p>' })

  const fragment = portableFragment('<p>hi</p>', { policy: { allowMedia: true } })
  assert.deepEqual(fragment?.policy, { allowMedia: true })

  // 不是普通对象 / 空对象 / 循环引用都不产生 policy，也不让 builder 挂掉。
  assert.equal(portableHtml('<p>hi</p>', { policy: 'yes' })?.[PORTABLE_KEY].policy, undefined)
  assert.equal(portableHtml('<p>hi</p>', { policy: [] })?.[PORTABLE_KEY].policy, undefined)
  assert.equal(portableHtml('<p>hi</p>', { policy: {} })?.[PORTABLE_KEY].policy, undefined)
  const cycle = { allowMedia: true }
  cycle.self = cycle
  assert.equal(portableHtml('<p>hi</p>', { policy: cycle })?.[PORTABLE_KEY].policy, undefined)
})

test('portableCard 产出结构化 envelope', () => {
  const meta = portableCard({
    title: '用量',
    fields: [{ label: '模型', value: 'flash' }],
    metrics: [{ label: '请求', value: 12, delta: '+3', trend: 'up' }],
    tables: [{ title: '按天', columns: ['日期', '次数'], rows: [['周一', 3], ['周二', 9]] }],
    items: ['一句话', { label: '备注', value: '试运行' }],
    markdown: '超过 **100** 条会限流。',
  })
  assert.deepEqual(meta, {
    'dsh-go/portable': {
      kind: 'structured',
      title: '用量',
      fields: [{ label: '模型', value: 'flash' }],
      metrics: [{ label: '请求', value: '12', delta: '+3', trend: 'up' }],
      tables: [{ columns: ['日期', '次数'], rows: [['周一', '3'], ['周二', '9']], title: '按天' }],
      items: ['一句话', { label: '备注', value: '试运行' }],
      markdown: '超过 **100** 条会限流。',
    },
  })
})

test('portableCard 的 trend 只认 up / down / flat', () => {
  const meta = portableCard({
    metrics: [
      { label: 'a', value: 1, trend: 'up' },
      { label: 'b', value: 2, trend: 'sideways' },
      { label: 'c', value: 3, trend: null },
    ],
  })
  assert.deepEqual(meta[PORTABLE_KEY].metrics, [
    { label: 'a', value: '1', trend: 'up' },
    { label: 'b', value: '2' },
    { label: 'c', value: '3' },
  ])
})

test('portableCard 钳制标题与单元格', () => {
  const long = 'x'.repeat(PORTABLE_MAX_CELL_CHARS + 500)
  const meta = portableCard({
    title: 't'.repeat(PORTABLE_MAX_TITLE_CHARS + 50),
    fields: [{ label: long, value: 'y' }],
    items: [{ label: long, value: '' }],
    markdown: 'ok',
  })
  const title = meta[PORTABLE_KEY].title
  assert.equal(title.length, PORTABLE_MAX_TITLE_CHARS)
  assert.ok(title.endsWith('…'))
  const cell = meta[PORTABLE_KEY].fields[0].label
  assert.equal(cell.length, PORTABLE_MAX_CELL_CHARS)
  assert.ok(cell.endsWith('…'))
  assert.equal(meta[PORTABLE_KEY].items[0].label.length, PORTABLE_MAX_CELL_CHARS)
})

test('portableCard 钳制表格行列', () => {
  const columns = Array.from({ length: PORTABLE_MAX_TABLE_COLUMNS + 3 }, (_, i) => 'c' + i)
  const rows = Array.from({ length: PORTABLE_MAX_TABLE_ROWS + 10 }, (_, i) => ['r' + i])
  rows.splice(2, 0, [])           // 空行既不输出也不计入 50 行
  rows.push(Array.from({ length: 20 }, (_, i) => 'z' + i))  // 超出表头的单元格丢弃
  const meta = portableCard({ tables: [{ columns, rows }] })
  const table = meta[PORTABLE_KEY].tables[0]
  assert.equal(table.columns.length, PORTABLE_MAX_TABLE_COLUMNS)
  assert.equal(table.rows.length, PORTABLE_MAX_TABLE_ROWS)
  assert.deepEqual(table.rows[0], ['r0'])
  assert.deepEqual(table.rows[1], ['r1'])
  assert.deepEqual(table.rows[2], ['r2'])
  for (const row of table.rows) assert.ok(row.length <= table.columns.length)
})

test('portableCard 丢掉空表、空字段与不合格输入', () => {
  assert.equal(portableCard(null), null)
  assert.equal(portableCard([]), null)
  assert.equal(portableCard({}), null)
  assert.equal(portableCard({ title: '   ' }), null)
  assert.equal(portableCard({ fields: [{ label: '', value: '' }] }), null)
  assert.equal(portableCard({ tables: [{ columns: [], rows: [['x']] }] }), null)
  assert.deepEqual(portableCard({ title: ' 标题 ' }), {
    'dsh-go/portable': { kind: 'structured', title: '标题' },
  })
})

test('portableCard 的文本总量超 60000 时不产卡', () => {
  assert.equal(portableCard({ markdown: 'a'.repeat(PORTABLE_MAX_HTML_CHARS + 1) }), null)
  assert.notEqual(portableCard({ markdown: 'a'.repeat(1000) }), null)
})

test('portableHtml 收口 html、css 与标题', () => {
  const meta = portableHtml('  <div>hi</div>  ', { css: '.x{color:red}', title: '标题' })
  assert.deepEqual(meta, {
    'dsh-go/portable': { kind: 'html', html: '<div>hi</div>', css: '.x{color:red}', title: '标题' },
  })
  assert.deepEqual(portableHtml('<b>x</b>'), { 'dsh-go/portable': { kind: 'html', html: '<b>x</b>' } })
})

test('portableHtml 拒绝 script、空串与超长 HTML', () => {
  for (const html of ['<div><script>alert(1)</script></div>', '<div><script/></div>', '<div><script', '<ScRiPt>']) {
    assert.equal(portableHtml(html), null, html)
  }
  assert.equal(portableHtml(''), null)
  assert.equal(portableHtml('   '), null)
  assert.equal(portableHtml(null), null)
  assert.equal(portableHtml(42), null)
  assert.equal(portableHtml('a'.repeat(PORTABLE_MAX_HTML_CHARS + 1)), null)
  assert.notEqual(portableHtml('a'.repeat(PORTABLE_MAX_HTML_CHARS)), null)
  assert.equal(portableHtml('<b>x</b>', { css: 'c'.repeat(500000) }), null)
})

test('portableWidget 产出第 5 层 widget 键位', () => {
  const meta = portableWidget('<div class="w">x</div>', { css: '.w{color:red}', title: '图表' })
  assert.deepEqual(meta, { widget: { html: '<div class="w">x</div>', css: '.w{color:red}', title: '图表' } })
  assert.equal(portableWidget('<script>x</script>'), null)
  assert.equal(portableWidget(''), null)
})

test('portableFragment 产出第 5 层 fragment 键位且不带 css', () => {
  assert.deepEqual(portableFragment('  <p>片段</p> ', { title: '片段' }), { fragment: '<p>片段</p>', title: '片段' })
  assert.deepEqual(portableFragment('<p>x</p>', { css: '.x{}' }), { fragment: '<p>x</p>' })
  assert.equal(portableFragment('<script>x</script>'), null)
})

test('portableMedia 只接受 https://', () => {
  assert.deepEqual(portableMedia(' https://example.com/a.png ', { title: '图' }), {
    'dsh-go/portable': { kind: 'media', url: 'https://example.com/a.png', title: '图' },
  })
  for (const url of ['http://example.com/a.png', 'ftp://example.com/a.png', 'https://', '  ', 'example.com/a.png', null, 42]) {
    assert.equal(portableMedia(url), null, String(url))
  }
})

test('portableMeta 永不抛错：builder 抛错给 {} 并回调 onError', () => {
  const seen = []
  const build = portableMeta(() => {
    throw new Error('boom')
  }, { onError: (error) => seen.push(error.message) })
  assert.deepEqual(build({}, {}), {})
  assert.deepEqual(seen, ['boom'])
})

test('portableMeta 合并额外 meta，卡片键优先', () => {
  const card = portableCard({ title: 'T' })
  const build = portableMeta(() => card, { meta: () => ({ 'dsh-go/portable': 'extra', tag: 1 }) })
  assert.deepEqual(build({}, {}), { tag: 1, 'dsh-go/portable': { kind: 'structured', title: 'T' } })
})

test('portableMeta 的 builder 返回 null、非对象或循环引用时只剩额外键', () => {
  assert.deepEqual(portableMeta(() => null)({}, {}), {})
  assert.deepEqual(portableMeta(() => 'nope')({}, {}), {})
  const cyclic = {}
  cyclic.self = cyclic
  assert.deepEqual(portableMeta(() => cyclic)({}, {}), {})
  assert.deepEqual(portableMeta(() => null, { meta: () => ({ extra: true }) })({}, {}), { extra: true })
})

test('产出可以完整走一遍 toLosslessJson / JSON.stringify', () => {
  const meta = {
    ...portableCard({ title: 'T', fields: [{ label: 'a', value: 1 }], metrics: [{ label: 'm', value: 2 }] }),
    ...portableMedia('https://example.com/x.png'),
  }
  const lossless = toLosslessJson(meta)
  assert.deepEqual(lossless, meta)
  const text = JSON.stringify(meta)
  assert.deepEqual(JSON.parse(text), meta)
  assert.equal(JSON.stringify(meta[PORTABLE_KEY]).includes('undefined'), false)
})
