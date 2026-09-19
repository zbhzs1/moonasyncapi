# Generator Design

MoonAsyncAPI separates parsing from source emission so each stage has a narrow,
testable contract.

```text
AsyncAPI 3.0 JSON
  -> parser and input diagnostics
  -> schema dependency inspection
  -> MoonBit identifier and type mapping
  -> message and operation interface emission
  -> deterministic project plan
  -> CLI filesystem writer
  -> moon check on the generated project
```

## Input Frontend

`parse` builds the typed document model. Existing document validation can run
independently, while generation-specific inspection checks references and names
that affect compilability. The generator never fetches remote schemas, which
makes builds reproducible and avoids hidden network dependencies.

## Naming

AsyncAPI component keys become PascalCase MoonBit type names. Property and
operation keys become lower camel case value names. Separators are removed,
leading digits receive a prefix, and MoonBit reserved words receive a `Value`
suffix. Field collisions receive stable numeric suffixes. Top-level collisions
are errors because silently changing a public type name would create an unstable
API.

## Type Mapping

Required object properties use direct types; other properties use MoonBit option
types. Local references retain named component types. Arrays recursively map
their item schema. Inline object and enum declarations are emitted before the
type that uses them. Unknown or unconstrained payloads use `Json` explicitly.

## Project Plan

Generation returns `GenerationPlan`, an in-memory list of `GeneratedFile` values
and diagnostics. It has no filesystem side effects. This allows IDEs, build
tools, and tests to preview output or choose their own write policy. The CLI is a
small JavaScript-target adapter that reads one input file and writes this plan.

## Verification

Unit tests cover mapping, naming, ordering, collision diagnostics, output modes,
and manifests. Repository CI additionally runs the CLI for MQTT and Kafka
fixtures, then executes `moon check --deny-warn` in both generated projects.
