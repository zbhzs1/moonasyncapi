# MoonAsyncAPI

MoonBit library for reading and validating a documented subset of AsyncAPI 3.0 JSON.
It turns event-driven API contracts into typed channel, operation, message, and payload
diagnostics that can be used before an MQTT or other message adapter sends data.

The current release implements local references, server/channel/message extraction,
address parameter checks, a documented JSON Schema subset, MQTT/Kafka/AMQP binding-name
recognition, descriptive security scheme parsing, payload validation, and stable
compatibility diagnostics. Batch operation reports are available for CI consumers.
Strict validation, schema inspection, and human-readable validation reports are also
available for tooling. See
`docs/SUPPORT_MATRIX.md` for the exact boundary.

## Verification

```bash
moon fmt
moon check --deny-warn
moon test
moon run cmd/main
```

The repository includes `examples/temperature.json`, an MQTT-oriented contract fixture.
The runnable command uses the same shape to validate a document and a payload without
network access. The project complements CloudEvents and `zbhzs1/moonbit-mqtt`; it does not
establish network connections or implement a broker, client, or message transport.
