# Support Matrix

MoonAsyncAPI intentionally implements a documented, testable subset of AsyncAPI
3.0 JSON. The matrix below is the contract for the current release.

| Area | Supported | Current boundary |
| --- | --- | --- |
| Document format | AsyncAPI 3.0 JSON | YAML and other AsyncAPI versions are not parsed |
| Document metadata | `asyncapi`, `info.title` | Additional metadata is currently ignored |
| Channels | channel names and `address` | Local channel references are accepted in operations |
| Messages | channel messages and local `#/components/messages/...` references, title, content type, payload | External message references are not supported |
| Operations | `send` and `receive`, channel and message names | Operation component references are not yet resolved |
| Schema | `type`, object `properties`, `required`, string `enum`, `minLength`/`maxLength`, arrays, numeric ranges | Unsupported composition and advanced keywords produce diagnostics; this is not a complete JSON Schema implementation |
| Schema references | local `#/components/schemas/...` payload and nested property references | External URLs and cyclic references are not supported |
| Bindings | binding name recognition for MQTT, Kafka and AMQP | Binding-specific fields are not interpreted |
| Payloads | type, required properties, string enum, array items and numeric range validation | Advanced composition and format validation are not interpreted |
| Compatibility | channel/message/schema additions and removals, channel address/binding changes, operation additions/removals/action/message changes | Deep schema evolution rules are not yet interpreted |

The library is offline. It does not establish network connections, read remote
references, implement a broker or client, or encode transport-specific packets.
For MQTT byte-level packet encoding and decoding, see the separate
`zbhzs1/moonbit-mqtt` project.
