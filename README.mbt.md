# MoonAsyncAPI Codegen

MoonAsyncAPI is an AsyncAPI 3.0 JSON to MoonBit code generator. It reads an
event-driven API contract and emits a compilable MoonBit project containing
schema types, typed message envelopes, transport-neutral operation ports, and
MQTT, Kafka, or AMQP binding configuration skeletons.

The generator is deterministic and offline. It does not connect to a broker,
send messages, or fetch remote references. The parser and validator introduced
in 0.1.0 remain available as the generator frontend and for input diagnostics;
the primary 0.2.0 workflow is project generation.

## Generated Output

Given an AsyncAPI document, MoonAsyncAPI can generate:

- MoonBit structs for object schemas and enums for string enumerations
- primitive, array, optional, nested object, and local `$ref` type mappings
- typed payload, header, and correlation ID message envelopes
- publisher or receive-handler traits for AsyncAPI operations
- MQTT, Kafka, AMQP, and custom binding configuration types
- `moon.mod`, `moon.pkg`, and either split or single-file source layouts
- stable diagnostics for unresolved references, cycles, unsupported types, and
  normalized identifier collisions

See [`docs/SUPPORT_MATRIX.md`](docs/SUPPORT_MATRIX.md) for exact coverage and
[`docs/CODEGEN_DESIGN.md`](docs/CODEGEN_DESIGN.md) for the generation pipeline.

## Install

```bash
moon add zbhzs1/moonasyncapi
```

Add the library import to `moon.pkg`:

```moonbit nocheck
///|
import {
  "zbhzs1/moonasyncapi",
}
```

## Library Usage

```moonbit nocheck
let source =
  "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Events\"},\"channels\":{}}"
match @moonasyncapi.generate_from_json(source) {
  Ok(plan) => {
    for file in plan.files {
      println(file.path)
    }
  }
  Err(message) => println("parse error: " + message)
}
```

`generate_project` accepts `CodegenOptions` for module name, source directory,
split-file output, binding skeletons, and operation stubs. Generated files are
returned in memory so applications can write them to disk, show previews, or
apply their own workspace policy.

## CLI Usage

The repository includes a Node-backed MoonBit CLI for writing a project:

```bash
moon run cmd/main --target js -- \
  examples/order-events.json \
  _build/generated-orders \
  example/order-events-generated

cd _build/generated-orders
moon check --deny-warn
```

The first argument is an AsyncAPI JSON file, the second is the output directory,
and the optional third argument is the generated module name. Existing files at
the generated paths are replaced; unrelated files are left untouched.

## Examples

- `examples/temperature.json`: MQTT channel with an inline object payload
- `examples/order-events.json`: Kafka channel with component schemas, enum,
  headers, a local reference, and a receive operation

CI generates both projects and runs `moon check --deny-warn` inside each output
directory. This verifies the generated source rather than only snapshot text.

## Parser And Diagnostics

The 0.1.0 parser APIs remain source compatible. `parse`, `validate`, payload and
header validation, document inventory, and compatibility diagnostics can be
used before generation. They are supporting frontend capabilities, not a claim
to replace schema-governance projects.

## Development

```bash
moon fmt --check
moon check --deny-warn
moon check --target js --deny-warn
moon build
moon test
```

The project is licensed under Apache-2.0. Contributions should include focused
tests and, for generation changes, at least one generated-project check.
