
# Portable chat UI protocol (draft)

dsh-go does not require every UI plugin to adapt its own native components. The host can render serializable UI from a tool result's `presentationMeta` through one portable priority list. This page describes the protocol and what the App currently implements.

## Priority

The host parses `presentationMeta` in this order and stops at the first match:

1. `presentationMeta['dsh-go/view']` — native dsh-go views; the 16 native components and media cards win.
2. `presentationMeta['dsh-go/media']` — dsh-go media card.
3. `presentationMeta.ui` — intelligent-ui `declarative` / `widget` / `composition` artifacts, rendered by the restricted WebView renderer.
4. `presentationMeta['dsh-go/portable']` — the envelope on this page (**implemented**).
5. `presentationMeta.html` / `widget.html` / `fragment` — generic HTML fragments (**planned, not implemented**).
6. `presentationMeta.card` / `kind` — structured cards (**planned, not implemented**).
7. Ordinary tool row — fallback when no UI is recognized.

The parser must **skip** 1–3 so the portable adapter never competes with the native view or intelligent-ui card for the same tool result.

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
- For sharing, the host converts the serializable envelope into an off-screen snapshot; it never depends on the plugin's web front-end state.
- Arbitrary React components, host routing, or front-end global state do not belong in this protocol; use `dsh-go/view` or a WebView island instead.

## Current App implementation

`PortableUiAdapter` (`app/lib/state/intelligent_ui.dart`) recognizes `presentationMeta['dsh-go/portable']` and converts it into a restricted intelligent-UI widget card:

| kind | input | current mapping |
|---|---|---|
| `html` | `html`, optional `css`, optional `title` | after the `<script>` check, emits `{html, css, initialHeight: 48}` |
| `structured` | `title`, `fields[{label,value}]` | emits simple label/value HTML |
| `media` | `url` (`https://` only) | emits `<img>`; external loading still obeys `policy.allowMedia` / `policy.mediaOrigins` |

The effective priority across all UI shapes is handled by the projector:

1. `dsh-go/view`
2. `dsh-go/media`
3. `presentationMeta.ui`
4. `dsh-go/portable`

Cards produced by `dsh-go/portable` reuse the same path as intelligent-ui cards:

- chat card rendering, immersive widget mode, and the native fast path (`Text` / `Stat` / `Table` / `Badge` / `Divider` / `List` / `Progress` / `Stack` / `Grid` / `Card`);
- share sheet and share image;
- link replay.

## Not implemented yet

- Auto-detection of raw `presentationMeta.html`, `presentationMeta.widget.html`, and `presentationMeta.fragment`.
- Raw `presentationMeta.card` / `kind` structured cards.
- `structured` `metrics`, `tables`, `items`, and `markdown` (currently only `title` + `fields`).
- Remote media inside share snapshots: the off-screen WebView blocks network by default, so `media` URLs may not load (see `plans/2026-11-13-dsh-go-intelligent-ui-handoff.md`).

## Adaptation order

Start with generic `html` / `widget.html` auto-detection (covers the most existing plugins), then `card` / `kind` structured cards, and finally standardize the protocol in SDK docs and plugin templates. The intelligent-ui `ui` artifact is the priority-3 special case and is already fully implemented.
