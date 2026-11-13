
## App implementation status

dsh-Go's `PortableUiAdapter` (`app/lib/state/intelligent_ui.dart`) recognizes
`presentationMeta['dsh-go/portable']` for the `html` / `structured` / `media`
kinds and maps them to a restricted intelligent-UI widget card. HTML containing
`<script>` or unknown kinds is ignored and the normal tool row remains. Plugins
only need to emit the envelope above; no intelligent-ui-specific payload is
required.
