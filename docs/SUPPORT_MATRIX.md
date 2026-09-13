# Support Matrix

MoonAsyncAPI intentionally implements a documented, testable subset of AsyncAPI
3.0 JSON. The matrix below is the contract for the current release.

| Area | Supported | Current boundary |
| --- | --- | --- |
| Document format | AsyncAPI 3.0 JSON | YAML and other AsyncAPI versions are not parsed |
| Document metadata | `asyncapi`, `info.title` | Additional metadata is currently ignored |
| Servers | host, protocol, protocol version, pathname, description, variables, endpoint rendering | Security schemes are not yet interpreted |
| Security | descriptive `apiKey` and `http` scheme fields, server security requirement names | No authentication, credential loading, TLS, or network connection is performed |
| Channels | channel names, `address`, address-template parameters, parameter enum/default validation | Local channel references are accepted in operations |
| Messages | channel messages and local `#/components/messages/...` references, title, content type, payload, headers schema and correlation ID location | External message references are not supported |
| Operations | `send` and `receive`, channel and message names | Operation component references are not yet resolved |
| Schema | `type`, object `properties`, `required`, `additionalProperties: false`, `minProperties`/`maxProperties`, typed `enum`, `const`, validated `default`/`examples`, `minLength`/`maxLength`, formats `email`/`uuid`/`date-time`, arrays, `minItems`/`maxItems`/`uniqueItems`, integer checks, `multipleOf`, inclusive and exclusive numeric ranges | Unsupported composition and advanced keywords produce diagnostics; this is not a complete JSON Schema implementation |
| Schema references | local `#/components/schemas/...` payload and nested property references, cycle detection | External URLs are not supported; cyclic references produce an error diagnostic |
| Bindings | binding name recognition for MQTT, Kafka and AMQP | Binding-specific fields are not interpreted |
| Payloads | type, required properties, property counts, string enum/length, array items/size/uniqueness and numeric range validation | Advanced composition and format validation are not interpreted |
| Compatibility | channel/message/schema additions and removals, channel address/binding changes, operation additions/removals/action/message changes, schema type/property/required/enum/constraint changes | Schema composition evolution is not interpreted |

The library is offline. It does not establish network connections, read remote
references, implement a broker or client, or encode transport-specific packets.
For MQTT byte-level packet encoding and decoding, see the separate
`zbhzs1/moonbit-mqtt` project.
