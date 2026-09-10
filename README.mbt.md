# MoonAsyncAPI

MoonBit library for reading and validating the core of an AsyncAPI 3.0 JSON document.

This first local prototype implements a typed document model, core channel extraction,
validation diagnostics, and channel/message compatibility checks. YAML input, full JSON
Schema support, protocol bindings, code generation, and the browser playground are planned
only after their implementations and tests exist.

## Verification

```bash
moon fmt
moon check
moon test
moon run cmd/main
```

The project complements CloudEvents, MQTT codecs, and JSON Schema libraries. It does not
establish network connections or implement a broker or message transport.
