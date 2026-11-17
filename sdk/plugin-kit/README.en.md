# @dsh-go/plugin-kit

English | [中文](README.md)

The author kit for dsh-go native plugins. Zero runtime dependencies, Node 22.19+. Not published to npm: use it from this repository, or copy the files you need into your plugin.

| Part | Entry | For |
|---|---|---|
| Types | `types/index.d.ts` (`types/schema.d.ts` is generated from the schemas) | Views, manifest, effects, `ctx.dshGo`, `caps` |
| Component builders | `stack()` `row()` `text()` `metric()` `chart()` `list()` `keyValue()` `progress()` `table()` `actions()` `image()` … `bind()` `action()` | Plain JSON nodes, `undefined` props dropped |
| Tool cards | `toolCard(build)` | Wraps `presentationMeta`: never throws, lossless JSON, ≤ 8 KiB |
| Capabilities | `hasComponent` `hasSurface` `appAtLeast` `localize` `adaptView` | Degrade by app capability and language |
| Effects | `effects.insert()` … `effects.deferred()`; `checkEffects` `checkPending` | Build effects; check handler results with the bridge's own code |
| Test host | `@dsh-go/plugin-kit/testing` → `createTestHost()` | Run your `apply(ctx)` without DSH: manifest, invoke, views, data, deferred results — answers like the bridge |
| Checker | `bin/check.mjs`; `@dsh-go/plugin-kit/check` | Manifest (the bridge's parser) + views (a line-by-line twin of the app's parser, the app's words) + `--load` for the host half |
| Schemas | `schema/*.schema.json` | Machine-readable protocol and view definitions; `lib/json-schema.js` validates against them |
| Portable cards | `@dsh-go/plugin-kit/portable` | The view-free card protocol (layers 4–5): structured / HTML / widget / fragment / media, clamped to the app's limits, `null` when an input cannot ship |

## Portable cards (layers 4–5)

`presentationMeta` also carries a view-free card protocol ([docs/plugins/portable-ui.md](../../docs/plugins/portable-ui.md)). The app recognises seven layers and stops at the first hit: layers 1–3 are `dsh-go/view`, `dsh-go/media` and `ui`; when one of them is present the portable keys are not read at all.

| Layer | Key | Here |
|---|---|---|
| 4 | `dsh-go/portable`, `kind` is `html` / `structured` / `media` | `portableHtml()` `portableCard()` `portableMedia()` |
| 5 | `html` / `widget.html` / `fragment` | `portableWidget()` `portableFragment()` (the bare `html` key is just a string) |

```js
import { portableMeta, portableCard } from '@dsh-go/plugin-kit/portable'

export const meta = portableMeta((_args, value) => portableCard({
  title: 'Usage today',
  metrics: [{ label: 'Requests', value: value.calls, delta: '+12%', trend: 'up' }],
  tables: [{ columns: ['Model', 'Calls'], rows: [['flash', 12], ['pro', 3]] }],
  markdown: 'Over **100** requests get rate limited.',
}))
// meta(...) → { 'dsh-go/portable': { kind: 'structured', … } }
```

| Function | Produces |
|---|---|
| `portableCard(spec, { title, policy })` | `{ 'dsh-go/portable': { kind: 'structured', title?, fields?, metrics?, tables?, items?, markdown?, policy? } }` |
| `portableHtml(html, { css, title, policy })` | `{ 'dsh-go/portable': { kind: 'html', html, css?, title?, policy? } }` |
| `portableWidget(html, { css, title, policy })` | `{ widget: { html, css?, title? }, policy? }` |
| `portableFragment(html, { title, policy })` | `{ fragment, title?, policy? }` |
| `portableMedia(url, { title, policy })` | `{ 'dsh-go/portable': { kind: 'media', url, title?, policy? } }` |
| `portableMeta(build, { meta, onError })` | Wraps any of the above as `(args, value) => Record<string, JsonValue>` |

- The five builders only decide whether an input can ship: anything unusable gives `null`, never a throw. `portableMeta` adds the last safety net: a builder that throws, returns `null`, or returns a non-plain object (cycles included) degrades to just the extra keys from `options.meta`, and `{}` when there are none (no card, the app shows its generic tool row). On a key clash the builder wins.
- Lengths match the app exactly (Dart `String.length`, i.e. UTF-16 code units — the same number as JS `String.length`): title 200 (keep the first 199 characters plus `…`), cell 2000 (same), tables 50 rows × 12 columns (empty rows do not count, cells past the header are dropped), one HTML document 60000 (over that the whole card is dropped, **never truncated**), and html + css of one widget card 480000.
- Security: HTML must be self-contained and **never runs remote scripts** — any HTML containing `<script` (also `<script/>`, `<ScRiPt>`) gives `null`. The app sanitises again before storing: `on*=` event attributes are stripped (including the slash form `…/onerror=`), `javascript:` / `vbscript:` / `data:text/html` schemes are removed, `meta`/`base`/`link`/`object`/`embed`/`iframe`/`frame`/`frameset` are deleted, and the renderer adds DOMPurify plus a `default-src 'none'` CSP. The SDK never rewrites your markup; only the app's pass protects the reader.
- Media accepts `https://` only. The chat card iframe builds its CSP from `policy`: by default only `img-src data: blob:` is allowed, so https images do not load in chat; `{ allowMedia: true }` adds `https:`, or list explicit origins in `mediaOrigins`. Share snapshots follow the same `policy`. Layer 4 writes `policy` inside the envelope, layer 5 puts it on `presentationMeta` — `options.policy` is wired on `portableCard()`, `portableHtml()`, `portableWidget()`, `portableFragment()` and `portableMedia()`. The app reads `allowMedia` / `mediaOrigins` / `mapTiles` / `openLinkOrigins`; the kit applies no key whitelist and passes the rest through (a non-plain object, a function or a cycle drops the whole policy without affecting the card). This envelope expresses images only — for video use the layer-2 `dsh-go/media` media card, which wants `items`, so this kit exports `PORTABLE_MEDIA_KEY` as a constant and never builds it.
- Structured cards also accept `charts` / `accent` / `style`; these builders do not construct them — write the envelope by hand when you need them.

## check

```sh
node sdk/plugin-kit/bin/check.mjs <plugin dir | package.json | view.json | -> [--load] [--json] [--lang en] [--budget toolCard|panel|strip] [--app x.y.z]
```

| Exit | Meaning |
|---|---|
| 0 | No errors (notes allowed) |
| 1 | Some items do not apply |
| 2 | The native part does not show at all (invalid manifest, unsupported protocol), a view does not render, or the host half fails to load |
| 3 | Cannot read the input |

- Manifest problems: JSON Pointers from `package.json`, with the bridge's English developer message (the app's plugin details page shows the same); the app's own findings (unknown icon) are localized.
- View problems: the same paths and words as the app's plugin details page (`lib/messages.json` is synced from the app's ARB files; the app runs the `test/parity/` cases too).
- Labels are measured in Chinese and English; `--load` loads your code with a temporary `DSH_HOME`.

`--load` starts with an empty config, validates it and applies defaults through the plugin's own `Config` Standard Schema, then calls `apply`. Without `Config`, it passes an empty object. Like the Host, it accepts synchronous config validation only; missing required values, thrown validation errors, and async validators report a load failure without calling `apply`. The checker does not read the user's Host config.

Option values must be complete: `--lang zh|en`, `--budget toolCard|panel|strip`, and `--app x.y.z`. Invalid arguments return 3; with `--json`, the diagnostic remains a JSON object. Multiple targets are checked separately, and an unreadable stdin does not prevent later files from being checked. Put filenames beginning with `-` after `--`, for example `node bin/check.mjs -- --view.json`.

`package.json` must contain a JSON object. Malformed `contributes.panels` retains the bridge's diagnostic. Static views use the bridge's package path policy, so rejected outside paths and symlinks are not read again as App views. This keeps checking consistent; `--load` still executes the plugin's own code and is not a code sandbox.

## Test host

```js
import { createTestHost } from '@dsh-go/plugin-kit/testing'
import { apply } from '../lib/index.js'

const host = createTestHost({ dir: pluginDir, services: { sessions } })
apply(host.ctx)
host.contributions()                                                  // the row the app gets
await host.invoke('translate', { context: { clipboard: 'hi' } })      // { effects, pending?, settled? }
await host.view('usage', { sessionId: 's1' })                         // { view, stats }
const feed = host.subscribe('today', { sessionId: 's1' })             // feed.data / feed.history
host.emitEvent('session/event', session, event)
```

## Maintenance

| Script | Run when |
|---|---|
| `node scripts/gen-types.mjs` | A schema changed |
| `node scripts/sync-bridge.mjs` | The bridge's `lib/native/{limits,util,effects,manifest,capabilities}.js` changed |
| `node scripts/sync-messages.mjs` | The app's `view` / `plugview` ARB files changed |
| `node scripts/gen-parity.mjs` | `lib/view-check.js` changed (after the app's parser did); review the diff |
| `node scripts/sync-skill.mjs` | Any of the above, or `skill/`: rebuilds the app's bundled `dsh-go-plugin` skill |
| `scripts/wire-check.sh` | To validate the schemas against real bridge traffic |

`npm test` (`node --test`) fails when any of these outputs is stale. Type checks need `npm install` (devDependency `typescript` only).

## License

MIT © DSH-TUI (ccch1mneyyy)
