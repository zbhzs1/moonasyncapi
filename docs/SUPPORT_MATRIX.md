# Code Generation Support Matrix

MoonAsyncAPI generates MoonBit source from a documented AsyncAPI 3.0 JSON
subset. Unsupported input is either diagnosed or mapped to an explicit fallback;
the generator does not silently claim complete AsyncAPI or JSON Schema support.

| Input area | Generated result | Boundary |
| --- | --- | --- |
| AsyncAPI format | AsyncAPI 3.0 JSON | YAML and older AsyncAPI versions are not parsed |
| Object schemas | `pub(all) struct` declarations | Properties, required fields, nested objects, and local references are supported |
| String enums | MoonBit enum declarations | Enum values are normalized to constructors |
| Primitive schemas | `String`, `Bool`, `Int`, `Int64`, `Double`, `Unit`, or `Json` | Unknown schema types produce a fallback diagnostic |
| Arrays | `Array[T]`, including referenced and inline items | Tuple validation and advanced array keywords do not change the generated type |
| Optional fields | MoonBit option types | Properties absent from `required` receive `?` |
| Schema references | Local `#/components/schemas/...` references | Missing local and external references are generation errors |
| Messages | Typed payload, header, and correlation ID envelopes | Messages without schemas use `Json` or string header maps |
| Operations | Publisher or receive-handler traits | Runtime transport implementations are supplied by the application |
| Bindings | MQTT, Kafka, AMQP, and custom configuration skeletons | Binding-specific runtime clients and network I/O are not generated |
| Output layout | Complete `moon.mod`, `moon.pkg`, and source tree | Split-file and single-file layouts are supported |
| Naming | Identifier normalization, reserved-word escaping, field suffixes | Top-level schema and operation collisions are reported as errors |
| Ordering | Stable schema dependency and lexical ordering | Cycles produce a stable diagnostic and lexical fallback order |
| Reproducibility | Identical input and options produce identical files | No timestamps, host paths, or network data enter generated source |

## Parser Frontend

The retained parser understands channels, operations, messages, servers,
security declarations, local references, and a JSON Schema subset. Its validation
diagnostics are useful before code generation. Payload validation, compatibility
diffs, inventory, and report helpers remain available for existing 0.1.0 users.

These helpers are not the primary differentiator of 0.2.0. MoonAsyncAPI focuses
on turning event contracts into compilable MoonBit interfaces, while contract
governance and schema-evolution systems can operate before or alongside it.

## Deliberate Runtime Boundary

Generated code is transport-neutral. It does not open sockets, authenticate,
perform TLS, publish to a broker, manage offsets, or implement delivery retries.
Applications can implement the generated traits using their chosen MQTT, Kafka,
or AMQP runtime. This keeps contract generation deterministic and testable.
