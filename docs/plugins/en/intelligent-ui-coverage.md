# deepseek-harness-intelligent-ui component coverage

[中文](../intelligent-ui-coverage.md)

The portable renderer ships the complete catalog. dsh-go loads the same offline renderer in an Android WebView, so all 39 catalog components render in phone chat cards. The only differences are external resources and interaction.

| Components | Phone rendering | Notes |
|---|---|---|
| Card / Stack / Grid / Tabs | Full | layout and tab switching |
| Text / Code / Alert / Badge / Divider | Full | Markdown subset |
| Stat / Progress / List / Table | Full | tables wrap and do not take horizontal swipe |
| Chart / Scatter / Heatmap / Plot | Full | SVG/canvas only |
| CodeDiff / FileTree / JsonView | Full | read-only |
| Button / Choice / Form | Full | actions via `sendPrompt`; read-only replay does not send |
| Timeline | Full | read-only |
| Math | Full | KaTeX bundled in offline renderer |
| Mermaid | Full | Mermaid bundled in offline renderer |
| Accordion / Steps / KeyValue / EmptyState / FollowUp / Sources / Segmented / Calendar / Audio | Full | Added in 0.2.16; Segmented can drive computed, Calendar supports day/week/agenda (explicit IANA time zone), Audio gated by mediaOrigins/CSP |
| Map | Outline | built-in world outline; tiles follow `policy.mapTiles` |
| Image / Gallery / Video | Policy-dependent | remote media only when `policy.allowMedia`/`mediaOrigins` allow it; the share snapshot opens the network for the same policy and waits for images before capturing |
| Custom `ui_render_widget` | Full | arbitrary HTML/CSS (no scripts); share uses offscreen WebView capture |

## Interaction and state

- Choice/Form/Tab/CodeView/Plot/Table state is stored by the renderer in `localStorage`. dsh-go gives the WebView a stable origin (`https://dsh.local/`) so state survives card rebuilds, scrolling and app restarts.
- Chat widget cards use an immersive full-width mode; the title row has a full-screen button for long tables, charts and maps.
- Share images and link replay use an offscreen WebView of the same offline renderer, so typography matches the chat card. Read-only cards never send prompts.

## Test

`app/test/state/intelligent_ui_catalog_coverage_test.dart` validates a tree containing all 39 component types. Remaining behavior is covered by the renderer tests and device screenshots.
