# deepseek-harness-intelligent-ui cards

[中文](../intelligent-ui.md)

`deepseek-harness-intelligent-ui` is a third-party plugin for DSH Web. A tool can return a declarative component tree (`ui_render`), a self-contained HTML widget (`ui_render_widget`), or a composition of markdown / catalog / widget blocks (`ui_compose`), and later update it with `ui_patch`. dsh-go projects this presentationMeta into a WebView card in chat instead of translating it into native `dsh-go/view` components.

## How it works

1. Tool calls and results remain ordinary session events; `tool/call`'s `arguments` and `tool/result`'s `meta` reach the app through history.
2. The app's `IntelligentUiProjector` (`app/lib/state/intelligent_ui.dart`) replays events by `seq`, accepts `ui_render` / `ui_render_widget` / `ui_compose` / `ui_patch` only when `meta.ok === true`, and handles `tool/ptc-dispatch` sub-calls. It validates bounded structures and version transitions matching the upstream portable protocol.
3. `app/lib/ui/chat/intelligent_ui/intelligent_ui_card.dart` shows the card: it inlines the bundled `assets/intelligent_ui/renderer.js` into local HTML with a strict CSP and bridges resize, prompt, download and error messages over `postMessage`.
4. The tool call itself remains a normal tool row; the card appears when expanded, and stays outside the folded process in collapsed turns, matching the behaviour of `dsh-go/view` tool cards.

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
