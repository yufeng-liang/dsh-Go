# deepseek-harness-intelligent-ui cards

[中文](../intelligent-ui.md)

`deepseek-harness-intelligent-ui` is a third-party plugin for DSH Web. A tool can return a declarative component tree (`ui_render`), a self-contained HTML widget (`ui_render_widget`), or a composition of markdown / catalog / widget blocks (`ui_compose`), and later update it with `ui_patch`. dsh-go projects this presentationMeta into a WebView card in chat instead of translating it into native `dsh-go/view` components.

## How it works

1. Tool calls and results remain ordinary session events; `tool/call`'s `arguments` and `tool/result`'s `meta` reach the app through history.
2. The app's `IntelligentUiProjector` (`app/lib/state/intelligent_ui.dart`) replays events by `seq`, accepts `ui_render` / `ui_render_widget` / `ui_compose` / `ui_patch` only when `meta.ok === true`, and handles `tool/ptc-dispatch` sub-calls. It validates bounded structures and version transitions matching the upstream portable protocol.
3. `app/lib/ui/chat/intelligent_ui/intelligent_ui_card.dart` shows the card: it inlines the bundled `assets/intelligent_ui/renderer.js` into local HTML with a strict CSP and bridges resize, prompt, download and error messages over `postMessage`.
4. The tool call itself remains a normal tool row; the card appears when expanded, and stays outside the folded process in collapsed turns, matching the behaviour of `dsh-go/view` tool cards.

## Scrolling and gestures

- The card does not register an `EagerGestureRecognizer`; it registers only a `LongPressGestureRecognizer`. Under Flutter's gesture arena, vertical drags stay with the outer chat list, so swiping anywhere on the card scrolls the chat; taps and long presses (text selection and the system selection toolbar) go to the WebView.
- The card does not scroll vertically and does not claim horizontal gestures: internal `max-height` and horizontal scrolling are removed from tables, code blocks and diffs. Tables use a fixed width and wrap cell content. This avoids both nested scroll conflicts and conflict with the phone's edge swipe that opens the app drawer.
- Card content uses 0px horizontal padding to make the most of the phone width; the title row keeps `ChatCard`'s 16.
- Card height is still capped by `maxHeight`; content beyond the cap is clipped by the renderer. An expand entry point can be added later without changing the gesture policy.

## Sharing

- A share card is a Flutter `RepaintBoundary` screenshot, and platform views inside the WebView are not drawn into it. Sharing therefore turns the card's title, text, lists, tables, code, stats, badges and progress into Markdown and draws it in a native Flutter card shell, so the share image never depends on the WebView.
- For `ui_render_widget`, only visible HTML text is extracted and no scripts run; interactions and live chart data are not part of the share image.
- A patched card stays attached to the turn that first showed it (via `originSeq`) and is shared at its latest version, matching the chat.
- A share link (`.dshgo` replay) writes the reply's cards into the share file as a `ui` array. Declarative cards are drawn in a native card shell from title and Markdown; `ui_render_widget` cards also carry restricted HTML/CSS and are rendered read-only in the replay page's sandboxed WebView so font family, size and weight survive, with no scripts, no network and no sending.

## Security boundary

- No remote code is downloaded or executed; the renderer is a fixed asset shipped with the app (`app/assets/intelligent_ui/renderer.js`).
- CSP is `default-src 'none'`; scripts, styles and images are limited to local/data/blob; `connect-src 'none'`; `frame-src` allows only about/data/blob.
- Navigation is limited to `about:blank`, `about:srcdoc`, and `data:`; Android file and content access are off, universal access keeps the WebView default (off), and mixed content is never allowed.
- A card's send action requires native confirmation and is scoped to the current host, session and live connection; one tap sends at most once.
- Card height is bounded to 100–4000 px so an oversized page cannot blow up the chat.

## Compatibility

- Requires `deepseek-harness-intelligent-ui` 0.2.15 or a compatible portable-renderer protocol; the plugin stays installed in the engine, not in dsh-go.
- Only the chat UI supports it; in the Web version the plugin's own web frontend handles rendering.
- dsh-go does not implement every upstream catalog validation rule; the Dart side enforces bounded structural checks and lets the renderer interpret the component tree.
