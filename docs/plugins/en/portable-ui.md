
# Portable chat UI protocol (draft)

dsh-go does not require every UI plugin to adapt its own native components. The host can render serializable UI from a tool result's `presentationMeta` through one portable priority list. This page describes the protocol and what the App currently implements.

## Priority

The host parses `presentationMeta` in this order and stops at the first match:

1. `presentationMeta['dsh-go/view']` — native dsh-go views; the 16 native components and media cards win.
2. `presentationMeta['dsh-go/media']` — dsh-go media card.
3. `presentationMeta.ui` — intelligent-ui `declarative` / `widget` / `composition` artifacts, rendered by the restricted WebView renderer.
4. `presentationMeta['dsh-go/portable']` — the envelope on this page (**implemented**).
5. `presentationMeta.html` / `presentationMeta.widget.html` / `presentationMeta.fragment` — generic HTML fragments (**implemented**; above layer 6, below the layer-4 envelope).
6. `presentationMeta.card` / `presentationMeta.kind == 'card'` — structured cards (**implemented**; the lowest recognizable UI layer).
7. Ordinary tool row — fallback when no UI is recognized.

The parser must **skip** 1–3 so the portable adapter never competes with the native view or intelligent-ui card for the same tool result.

Layers 5 and 6 recognition (an item that does not qualify falls through to the next one):

- Layer 5 tries `presentationMeta.html` (string), `presentationMeta.widget.html` (when `widget` is a Map, take `html`, `css`, `title`), then `presentationMeta.fragment` (string). Each candidate must be non-empty and free of `<script`.
- Layer 6 tries `presentationMeta.card` (the Map itself is the data source; `title` comes from `card.title` or the outer `presentationMeta.title`), or `presentationMeta.kind == 'card'` (the whole `presentationMeta` is the data source).
- When neither layer yields usable HTML, the tool row falls back to layer 7.

## Suggested envelope

```json
{
  "dsh-go/portable": {
    "kind": "html",
    "title": "Optional title",
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

- `kind` is `html` / `structured` / `media`; the host picks the adapter by kind.
- HTML must be self-contained and must not execute remote scripts; external resources must be listed in `mediaOrigins`.
- For sharing, the host converts the serializable envelope into an off-screen snapshot; the capture WebView only opens the network when `policy` allows media, and the CSP comes from the same `policy`; it never depends on the plugin's web front-end state.
- Arbitrary React components, host routing, or front-end global state do not belong in this protocol; use `dsh-go/view` or a WebView island instead.

## Current App implementation

`PortableUiAdapter.fromTool` (`app/lib/state/intelligent_ui.dart:153`) reads tool results while chat rows are projected (`app/lib/ui/chat/chat_rows.dart:228`) and turns a match into a restricted intelligent-UI widget card that mounts through the same path as intelligent-ui cards (keyed by `callId` / `seq`). The first match wins:

1. `presentationMeta` is not a Map, or the tool result has no `seq` → no card.
2. Skip layers 1–3: any non-null `dsh-go/view`, `dsh-go/media`, or `ui`, or a tool named `ui_render` / `ui_render_widget` / `ui_compose`.
3. Layer 4: `dsh-go/portable` is a Map → map by `kind` (table below); a `dsh-go/portable` with an unknown `kind` or unusable content produces no card.
4. Layer 5: `html` / `widget.html` / `fragment` → generic HTML (`widget` as a Map contributes `widget.html`, `widget.css`, `widget.title`).
5. Layer 6: `card` / `kind == 'card'` → structured card.
6. No match → no card; the tool stays an ordinary row.

| kind | input | current mapping |
|---|---|---|
| `html` | `html` (required, non-empty, no `<script`), optional `css`, optional `title` | emits `{html, css, initialHeight: 48}` |
| `structured` | structured fields (table below) | emits structured HTML |
| `media` | `url` (`https://` only) | emits `<img>`; external loading still obeys `policy.allowMedia` / `policy.mediaOrigins` |

`policy` comes from the envelope for layer 4 and from the outer `presentationMeta['policy']` for layers 5 and 6; anything that is not a Map becomes an empty map. Every artifact is `IntelligentUiKind.widget`, `uiId` is the tool call's `callId`, `version` is 1, `seq` and `originSeq` are the tool result's `seq`, and `definition` must pass `IntelligentUiProjector._validWidget` (`app/lib/state/intelligent_ui.dart:888`); empty HTML or `<script` produces no card.

Structured rendering (`structured` and `card` share `_structuredHtml`); every text is `HtmlEscape`d first:

| key | input | output |
|---|---|---|
| `title` | String | `<h2>` |
| `fields` | `[{label, value}]` | one row per entry |
| `metrics` | `[{label, value, delta?, trend?}]` | metric tiles; `trend` is `up` / `down` / `flat`, colored by class |
| `tables` | `[{title?, columns: [String], rows: [[…]]}]` | `<table>`, at most 50 rows × 12 columns, truncated beyond that |
| `items` | list of String or `{label, value}` | `<ul><li>` |
| `markdown` | String | minimal Markdown: paragraphs, `#` / `##` / `###` headings, `**bold**`, `*italic*`, backtick code spans, fenced code blocks, `-` / `1.` lists, `[text](https://…)`; escape first, then wrap, so no raw tag survives |

Structured HTML longer than 60000 characters produces no card, and so does a card where no field rendered anything. Raw HTML from layers 4 and 5 is not subject to that limit; only the 480000-character gate in `_validWidget` applies. CSS is one shared block (`.dsh-portable`, `.dsh-portable-metrics`, `.dsh-portable-table`, …) and `initialHeight` stays 48.

Share snapshots follow the card's own `policy` (**implemented**):

- `snapshotAllowsRemoteMedia(policy)` in `app/lib/ui/share/intelligent_ui_snapshot.dart:107` lets `allowMedia` / `mediaOrigins` decide whether the network opens; the CSP built from the same `policy` (same file, `:129`) then decides which origins are reachable.
- `blockNetworkLoads = !remoteMedia` in `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/intelligentui/IntelligentUiSnapshotPlugin.kt:147`; when the network is on, the capture waits `MEDIA_SETTLE_MS = 5000L` (same file, `:307`) instead of `PAGE_SETTLE_MS`.
- History: b30660bd (snapshots open the network per policy) and 3c92b37f (renderer media allowed by policy, offline only as the default).

Cards produced by `dsh-go/portable` reuse the same path as intelligent-ui cards:

- chat card rendering and immersive widget mode: a portable artifact is a `widget` with an `html` definition, so it always renders through the WebView and never takes the declarative native fast path (`Text` / `Stat` / `Table` / `Badge` / `Divider` / `List` / `Progress` / `Stack` / `Grid` / `Card`);
- share sheet and share image;
- link replay.

## Not implemented yet

- `card` styling and chart extensions: only the base fields render today; there are no style hooks or chart types beyond `metrics` / `tables`.
- The protocol in SDK docs and plugin templates: `sdk/plugin-kit` does not yet show plugin authors how to emit `presentationMeta`.

## Adaptation order

Generic `html` / `widget.html` auto-detection is done (it covers the most existing plugins) and `card` / `kind` structured cards are done; what remains is standardizing the protocol in SDK docs and plugin templates. The intelligent-ui `ui` artifact is the priority-3 special case and is already fully implemented.
