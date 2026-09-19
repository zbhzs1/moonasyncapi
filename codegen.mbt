///|
/// Options controlling AsyncAPI-to-MoonBit project generation.
pub(all) struct CodegenOptions {
  module_name : String
  source_dir : String
  split_files : Bool
  emit_protocol_bindings : Bool
  emit_operation_stubs : Bool
} derive(Eq, Debug)

///|
/// A file produced by the generator. Paths always use forward slashes.
pub(all) struct GeneratedFile {
  path : String
  content : String
  kind : String
} derive(Eq, Debug)

///|
/// A generator diagnostic is separate from contract validation diagnostics.
pub(all) struct CodegenDiagnostic {
  severity : String
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
/// A deterministic plan containing every file and generator diagnostic.
pub(all) struct GenerationPlan {
  files : Array[GeneratedFile]
  diagnostics : Array[CodegenDiagnostic]
  schema_count : Int
  message_count : Int
  operation_count : Int
} derive(Eq, Debug)

///|
/// Intermediate representation for a generated MoonBit type.
pub(all) struct GeneratedType {
  source_name : String
  moonbit_name : String
  declaration : String
  dependencies : Array[String]
} derive(Eq, Debug)

///|
pub fn default_codegen_options() -> CodegenOptions {
  {
    module_name: "generated/asyncapi",
    source_dir: "src",
    split_files: true,
    emit_protocol_bindings: true,
    emit_operation_stubs: true,
  }
}

///|
fn[V] sorted_map_keys(values : Map[String, V]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in values {
    keys.push(key)
  }
  keys.sort_by(fn(left, right) { left.compare(right) })
  keys
}

///|
fn cg_is_letter(character : Char) -> Bool {
  (character >= 'A' && character <= 'Z') ||
  (character >= 'a' && character <= 'z')
}

///|
fn cg_is_digit(character : Char) -> Bool {
  character >= '0' && character <= '9'
}

///|
fn cg_words(source : String) -> Array[String] {
  let words : Array[String] = []
  let current : Array[Char] = []
  for character in source {
    if cg_is_letter(character) || cg_is_digit(character) {
      current.push(character)
    } else if current.length() > 0 {
      words.push(String::from_array(current.copy()))
      current.clear()
    }
  }
  if current.length() > 0 {
    words.push(String::from_array(current))
  }
  words
}

///|
fn cg_capitalize(source : String) -> String {
  let chars = source.to_array()
  if chars.length() == 0 {
    return ""
  }
  chars[0] = chars[0].to_ascii_uppercase()
  String::from_array(chars)
}

///|
/// Convert an arbitrary AsyncAPI component key to a MoonBit type identifier.
pub fn moonbit_type_name(source : String) -> String {
  let words = cg_words(source)
  let mut output = ""
  for word in words {
    output = output + cg_capitalize(word)
  }
  if output.length() == 0 {
    output = "Generated"
  }
  let first = output.to_array()[0]
  if cg_is_digit(first) {
    output = "T" + output
  }
  output
}

///|
fn cg_reserved(name : String) -> Bool {
  let words = [
    "as", "break", "catch", "class", "const", "continue", "derive", "else", "enum",
    "fn", "for", "guard", "if", "impl", "in", "let", "loop", "match", "mut", "priv",
    "pub", "raise", "return", "struct", "test", "trait", "try", "type", "while",
    "with", "async", "await",
  ]
  for word in words {
    if name == word {
      return true
    }
  }
  false
}

///|
/// Convert an arbitrary property or operation key to a MoonBit value identifier.
pub fn moonbit_value_name(source : String) -> String {
  let words = cg_words(source)
  let mut output = ""
  for index, word in words {
    if index == 0 {
      output = word.to_lower()
    } else {
      output = output + cg_capitalize(word)
    }
  }
  if output.length() == 0 {
    output = "generated"
  }
  let first = output.to_array()[0]
  if cg_is_digit(first) {
    output = "value" + output
  }
  if cg_reserved(output) {
    output + "Value"
  } else {
    output
  }
}

///|
fn local_ref_name(reference : String) -> String? {
  let prefix = "#/components/schemas/"
  if reference.has_prefix(prefix) {
    Some(reference[prefix.length():reference.length()].to_owned())
  } else {
    None
  }
}

///|
fn schema_is_required(schema : Schema, name : String) -> Bool {
  for required in schema.required {
    if required == name {
      return true
    }
  }
  false
}

///|
fn primitive_type(kind : String?, format_name : String?) -> String {
  match kind {
    Some("boolean") => "Bool"
    Some("integer") =>
      match format_name {
        Some("int64") => "Int64"
        _ => "Int"
      }
    Some("number") => "Double"
    Some("string") => "String"
    Some("null") => "Unit"
    _ => "Json"
  }
}

///|
fn inline_schema_type(schema : Schema, fallback : String) -> String {
  match schema.ref_name {
    Some(reference) =>
      match local_ref_name(reference) {
        Some(name) => moonbit_type_name(name)
        None => primitive_type(schema.kind, schema.format_name)
      }
    None =>
      if schema.enum_values.length() > 0 {
        fallback
      } else {
        match schema.kind {
          Some("array") => {
            let item_type = match schema.items {
              Some(item) => inline_schema_type(item, fallback + "Item")
              None => "Json"
            }
            "Array[" + item_type + "]"
          }
          Some("object") =>
            if schema.properties.length() == 0 {
              "Map[String, Json]"
            } else {
              fallback
            }
          _ => primitive_type(schema.kind, schema.format_name)
        }
      }
  }
}

///|
fn schema_dependencies(schema : Schema) -> Array[String] {
  let result : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  collect_schema_dependencies(schema, result, seen)
  result.sort_by(fn(left, right) { left.compare(right) })
  result
}

///|
fn collect_schema_dependencies(
  schema : Schema,
  result : Array[String],
  seen : Map[String, Bool],
) -> Unit {
  match schema.ref_name {
    Some(reference) =>
      match local_ref_name(reference) {
        Some(name) =>
          if seen.get(name) is None {
            seen[name] = true
            result.push(name)
          }
        None => ()
      }
    None => ()
  }
  for _, property in schema.properties {
    collect_schema_dependencies(property, result, seen)
  }
  match schema.items {
    Some(item) => collect_schema_dependencies(item, result, seen)
    None => ()
  }
}

///|
fn push_codegen_diagnostic(
  diagnostics : Array[CodegenDiagnostic],
  severity : String,
  code : String,
  path : String,
  message : String,
) -> Unit {
  diagnostics.push({ severity, code, path, message, })
}

///|
fn inspect_schema_for_codegen(
  schema : Schema,
  path : String,
  document : AsyncApiDocument,
  diagnostics : Array[CodegenDiagnostic],
) -> Unit {
  match schema.ref_name {
    Some(reference) =>
      match local_ref_name(reference) {
        Some(name) =>
          if document.schemas.get(name) is None {
            push_codegen_diagnostic(
              diagnostics,
              "error",
              "codegen.ref.unresolved",
              path,
              "local schema reference `" + name + "` does not exist",
            )
          }
        None =>
          push_codegen_diagnostic(
            diagnostics, "error", "codegen.ref.external", path, "external schema references are not supported by project generation",
          )
      }
    None => ()
  }
  let normalized_fields : Map[String, String] = Map([])
  let property_names = sorted_map_keys(schema.properties)
  for property_name in property_names {
    let normalized = moonbit_value_name(property_name)
    match normalized_fields.get(normalized) {
      Some(previous) =>
        push_codegen_diagnostic(
          diagnostics,
          "warning",
          "codegen.field.collision",
          path + ".properties." + property_name,
          "field name collides with `" +
          previous +
          "`; a numeric suffix is emitted",
        )
      None => normalized_fields[normalized] = property_name
    }
    inspect_schema_for_codegen(
      schema.properties.get(property_name).unwrap(),
      path + ".properties." + property_name,
      document,
      diagnostics,
    )
  }
  match schema.items {
    Some(item) =>
      inspect_schema_for_codegen(item, path + ".items", document, diagnostics)
    None => ()
  }
  match schema.kind {
    Some("object")
    | Some("array")
    | Some("string")
    | Some("integer")
    | Some("number")
    | Some("boolean")
    | Some("null")
    | None => ()
    Some(kind) =>
      push_codegen_diagnostic(
        diagnostics,
        "warning",
        "codegen.schema.fallback",
        path + ".type",
        "schema type `" + kind + "` is emitted as Json",
      )
  }
}

///|
fn inspect_codegen_input(
  document : AsyncApiDocument,
  diagnostics : Array[CodegenDiagnostic],
) -> Unit {
  let normalized_types : Map[String, String] = Map([])
  let schema_names = sorted_map_keys(document.schemas)
  for schema_name in schema_names {
    let normalized = moonbit_type_name(schema_name)
    match normalized_types.get(normalized) {
      Some(previous) =>
        push_codegen_diagnostic(
          diagnostics,
          "error",
          "codegen.type.collision",
          "$.components.schemas." + schema_name,
          "schema name collides with `" + previous + "` after normalization",
        )
      None => normalized_types[normalized] = schema_name
    }
    inspect_schema_for_codegen(
      document.schemas.get(schema_name).unwrap(),
      "$.components.schemas." + schema_name,
      document,
      diagnostics,
    )
  }
  let operation_names : Map[String, String] = Map([])
  for operation in document.operations {
    let normalized = moonbit_type_name(operation.name)
    match operation_names.get(normalized) {
      Some(previous) =>
        push_codegen_diagnostic(
          diagnostics,
          "error",
          "codegen.operation.collision",
          "$.operations." + operation.name,
          "operation name collides with `" + previous + "` after normalization",
        )
      None => operation_names[normalized] = operation.name
    }
  }
  let channel_names = sorted_map_keys(document.channels)
  for channel_name in channel_names {
    let channel = document.channels.get(channel_name).unwrap()
    let message_names = sorted_map_keys(channel.messages)
    for message_name in message_names {
      let message = channel.messages.get(message_name).unwrap()
      match message.payload {
        Some(payload) =>
          inspect_schema_for_codegen(
            payload,
            "$.channels." +
            channel_name +
            ".messages." +
            message_name +
            ".payload",
            document,
            diagnostics,
          )
        None => ()
      }
      match message.headers {
        Some(headers) =>
          inspect_schema_for_codegen(
            headers,
            "$.channels." +
            channel_name +
            ".messages." +
            message_name +
            ".headers",
            document,
            diagnostics,
          )
        None => ()
      }
    }
  }
}

///|
fn escape_doc_text(source : String) -> String {
  source.replace(old="\n", new=" ").replace(old="\r", new=" ")
}

///|
fn emit_enum(schema_name : String, schema : Schema) -> String {
  let type_name = moonbit_type_name(schema_name)
  let mut output = "///|\n/// Generated from AsyncAPI schema `" +
    escape_doc_text(schema_name) +
    "`.\n"
  output = output + "pub enum " + type_name + " {\n"
  let used : Map[String, Int] = Map([])
  for raw_value in schema.enum_values {
    let base = moonbit_type_name(raw_value)
    let count = used.get(base).unwrap_or(0)
    used[base] = count + 1
    let variant = if count == 0 { base } else { base + (count + 1).to_string() }
    output = output + "  " + variant + "\n"
  }
  output + "} derive(Eq, Debug)\n"
}

///|
fn emit_struct(schema_name : String, schema : Schema) -> String {
  let type_name = moonbit_type_name(schema_name)
  let mut output = "///|\n/// Generated from AsyncAPI schema `" +
    escape_doc_text(schema_name) +
    "`.\n"
  output = output + "pub(all) struct " + type_name + " {\n"
  let property_names = sorted_map_keys(schema.properties)
  let used : Map[String, Int] = Map([])
  for property_name in property_names {
    let property = schema.properties.get(property_name).unwrap()
    let base = moonbit_value_name(property_name)
    let count = used.get(base).unwrap_or(0)
    used[base] = count + 1
    let field_name = if count == 0 {
      base
    } else {
      base + (count + 1).to_string()
    }
    let nested_name = type_name + moonbit_type_name(property_name)
    let base_type = inline_schema_type(property, nested_name)
    let field_type = if schema_is_required(schema, property_name) {
      base_type
    } else {
      base_type + "?"
    }
    output = output + "  " + field_name + " : " + field_type + "\n"
  }
  output + "} derive(Eq, Debug)\n"
}

///|
fn emit_inline_schema_declarations(
  type_name : String,
  schema : Schema,
) -> String {
  if schema.ref_name is Some(_) {
    return ""
  }
  let mut output = ""
  if schema.kind == Some("array") {
    match schema.items {
      Some(item) =>
        output = output +
          emit_inline_schema_declarations(type_name + "Item", item)
      None => ()
    }
    return output
  }
  if schema.kind != Some("object") || schema.properties.length() == 0 {
    if schema.enum_values.length() > 0 {
      return emit_enum(type_name, schema) + "\n"
    }
    return ""
  }
  let names = sorted_map_keys(schema.properties)
  for name in names {
    let property = schema.properties.get(name).unwrap()
    output = output +
      emit_inline_schema_declarations(
        type_name + moonbit_type_name(name),
        property,
      )
  }
  output + emit_struct(type_name, schema) + "\n"
}

///|
fn emit_alias(schema_name : String, schema : Schema) -> String {
  let type_name = moonbit_type_name(schema_name)
  let target = inline_schema_type(schema, type_name + "Value")
  "///|\n/// Generated from AsyncAPI schema `" +
  escape_doc_text(schema_name) +
  "`.\npub type " +
  type_name +
  " = " +
  target +
  "\n"
}

///|
fn emit_generated_type(schema_name : String, schema : Schema) -> GeneratedType {
  let nested = if schema.kind == Some("object") {
    let mut output = ""
    let names = sorted_map_keys(schema.properties)
    for name in names {
      output = output +
        emit_inline_schema_declarations(
          moonbit_type_name(schema_name) + moonbit_type_name(name),
          schema.properties.get(name).unwrap(),
        )
    }
    output
  } else {
    ""
  }
  let primary = if schema.enum_values.length() > 0 {
    emit_enum(schema_name, schema)
  } else if schema.kind == Some("object") && schema.properties.length() > 0 {
    emit_struct(schema_name, schema)
  } else {
    emit_alias(schema_name, schema)
  }
  let declaration = nested + primary
  {
    source_name: schema_name,
    moonbit_name: moonbit_type_name(schema_name),
    declaration,
    dependencies: schema_dependencies(schema),
  }
}

///|
fn order_generated_types(
  document : AsyncApiDocument,
  diagnostics : Array[CodegenDiagnostic],
) -> Array[GeneratedType] {
  let names = sorted_map_keys(document.schemas)
  let result : Array[GeneratedType] = []
  let emitted : Map[String, Bool] = Map([])
  let mut progress = true
  while result.length() < names.length() && progress {
    progress = false
    for name in names {
      if emitted.get(name) is Some(_) {
        continue
      }
      let schema = document.schemas.get(name).unwrap()
      let dependencies = schema_dependencies(schema)
      let mut ready = true
      for dependency in dependencies {
        if dependency != name &&
          document.schemas.get(dependency) is Some(_) &&
          emitted.get(dependency) is None {
          ready = false
        }
      }
      if ready {
        result.push(emit_generated_type(name, schema))
        emitted[name] = true
        progress = true
      }
    }
  }
  if result.length() < names.length() {
    for name in names {
      if emitted.get(name) is None {
        diagnostics.push({
          severity: "warning",
          code: "codegen.schema.cycle",
          path: "$.components.schemas." + name,
          message: "schema dependency cycle emitted in stable lexical order",
        })
        result.push(
          emit_generated_type(name, document.schemas.get(name).unwrap()),
        )
      }
    }
  }
  result
}

///|
fn message_payload_type(message : AsyncApiMessage, fallback : String) -> String {
  match message.payload {
    Some(payload) => inline_schema_type(payload, fallback)
    None => "Json"
  }
}

///|
fn message_headers_type(message : AsyncApiMessage, fallback : String) -> String {
  match message.headers {
    Some(headers) => inline_schema_type(headers, fallback)
    None => "Map[String, String]"
  }
}

///|
fn emit_messages(document : AsyncApiDocument) -> String {
  let mut output = "/// Generated message envelopes.\n\n"
  let emitted : Map[String, Bool] = Map([])
  let component_names = sorted_map_keys(document.messages)
  for name in component_names {
    let message = document.messages.get(name).unwrap()
    output = output + emit_message(name, message)
    emitted[name] = true
  }
  let channel_names = sorted_map_keys(document.channels)
  for channel_name in channel_names {
    let channel = document.channels.get(channel_name).unwrap()
    let names = sorted_map_keys(channel.messages)
    for name in names {
      let qualified = moonbit_type_name(channel_name) + moonbit_type_name(name)
      if emitted.get(qualified) is None {
        output = output +
          emit_message(qualified, channel.messages.get(name).unwrap())
        emitted[qualified] = true
      }
    }
  }
  output
}

///|
fn emit_message(name : String, message : AsyncApiMessage) -> String {
  let type_name = moonbit_type_name(name) + "Message"
  let payload_type = message_payload_type(message, type_name + "Payload")
  let headers_type = message_headers_type(message, type_name + "Headers")
  let payload_declarations = match message.payload {
    Some(payload) =>
      emit_inline_schema_declarations(type_name + "Payload", payload)
    None => ""
  }
  let header_declarations = match message.headers {
    Some(headers) =>
      emit_inline_schema_declarations(type_name + "Headers", headers)
    None => ""
  }
  payload_declarations +
  header_declarations +
  "///|\n/// Typed envelope for AsyncAPI message `" +
  escape_doc_text(name) +
  "`.\npub(all) struct " +
  type_name +
  " {\n" +
  "  payload : " +
  payload_type +
  "\n" +
  "  headers : " +
  headers_type +
  "\n" +
  "  correlationId : String?\n" +
  "} derive(Eq, Debug)\n\n"
}

///|
fn operation_message_type(
  document : AsyncApiDocument,
  operation : AsyncApiOperation,
) -> String {
  if operation.messages.length() > 0 {
    let message_name = operation.messages[0]
    moonbit_type_name(operation.channel) +
    moonbit_type_name(message_name) +
    "Message"
  } else {
    match document.channels.get(operation.channel) {
      Some(channel) => {
        let names = sorted_map_keys(channel.messages)
        if names.length() > 0 {
          moonbit_type_name(operation.channel) +
          moonbit_type_name(names[0]) +
          "Message"
        } else {
          "Json"
        }
      }
      None => "Json"
    }
  }
}

///|
fn emit_operations(document : AsyncApiDocument) -> String {
  let mut output = "/// Generated transport-neutral operation ports.\n\n"
  let operations = document.operations.copy()
  operations.sort_by(fn(left, right) { left.name.compare(right.name) })
  for operation in operations {
    let function_name = moonbit_value_name(operation.name)
    let message_type = operation_message_type(document, operation)
    let channel_address = match document.channels.get(operation.channel) {
      Some(channel) => channel.address
      None => operation.channel
    }
    output = output +
      "///|\n/// " +
      operation.action +
      " on `" +
      escape_doc_text(channel_address) +
      "`.\n"
    if operation.action == "receive" {
      output = output +
        "pub trait " +
        moonbit_type_name(operation.name) +
        "Handler {\n  " +
        function_name +
        "(Self, " +
        message_type +
        ") -> Unit\n}\n\n"
    } else {
      output = output +
        "pub trait " +
        moonbit_type_name(operation.name) +
        "Publisher {\n  " +
        function_name +
        "(Self, " +
        message_type +
        ") -> Unit\n}\n\n"
    }
  }
  output
}

///|
fn protocol_config_type(protocol : String) -> String {
  match protocol.to_lower() {
    "mqtt" => "MqttBindingConfig"
    "kafka" => "KafkaBindingConfig"
    "amqp" => "AmqpBindingConfig"
    _ => "CustomBindingConfig"
  }
}

///|
fn emit_bindings(document : AsyncApiDocument) -> String {
  let mut output = "/// Transport configuration skeletons; no network I/O is generated.\n\n"
  output = output +
    "pub(all) struct MqttBindingConfig {\n  topic : String\n  qos : Int\n  retain : Bool\n} derive(Eq, Debug)\n\n"
  output = output +
    "pub(all) struct KafkaBindingConfig {\n  topic : String\n  groupId : String?\n} derive(Eq, Debug)\n\n"
  output = output +
    "pub(all) struct AmqpBindingConfig {\n  exchange : String\n  routingKey : String\n} derive(Eq, Debug)\n\n"
  output = output +
    "pub(all) struct CustomBindingConfig {\n  protocol : String\n  address : String\n} derive(Eq, Debug)\n\n"
  let names = sorted_map_keys(document.channels)
  for name in names {
    let channel = document.channels.get(name).unwrap()
    let protocol = channel.binding.unwrap_or("custom")
    output = output +
      "/// `" +
      escape_doc_text(channel.address) +
      "` uses " +
      protocol +
      ".\npub type " +
      moonbit_type_name(name) +
      "Binding = " +
      protocol_config_type(protocol) +
      "\n\n"
  }
  output
}

///|
fn source_header(document : AsyncApiDocument) -> String {
  "// Generated by MoonAsyncAPI from " + document.title + ". DO NOT EDIT.\n\n"
}

///|
fn normalize_source_dir(source_dir : String) -> String {
  let trimmed = source_dir.trim().to_owned().replace(old="\\", new="/")
  if trimmed.length() == 0 {
    "src"
  } else {
    trimmed
  }
}

///|
fn emit_moon_mod(options : CodegenOptions) -> String {
  "name = \"" +
  options.module_name +
  "\"\n\n" +
  "version = \"0.1.0\"\n\n" +
  "license = \"Apache-2.0\"\n"
}

///|
fn emit_moon_pkg() -> String {
  "import {\n  \"moonbitlang/core/json\",\n}\n"
}

///|
/// Generate a complete MoonBit project plan from a parsed AsyncAPI document.
pub fn generate_project(
  document : AsyncApiDocument,
  options? : CodegenOptions = default_codegen_options(),
) -> GenerationPlan {
  let diagnostics : Array[CodegenDiagnostic] = []
  inspect_codegen_input(document, diagnostics)
  if options.module_name.trim().length() == 0 {
    diagnostics.push({
      severity: "error",
      code: "codegen.module.empty",
      path: "$.options.module_name",
      message: "module name must not be empty",
    })
  }
  let types = order_generated_types(document, diagnostics)
  let files : Array[GeneratedFile] = [
    { path: "moon.mod", content: emit_moon_mod(options), kind: "manifest", },
  ]
  let source_dir = normalize_source_dir(options.source_dir)
  files.push({
    path: source_dir + "/moon.pkg",
    content: emit_moon_pkg(),
    kind: "package",
  })
  if options.split_files {
    for generated_type in types {
      files.push({
        path: source_dir +
        "/types_" +
        generated_type.source_name.to_lower().replace(old="-", new="_") +
        ".mbt",
        content: source_header(document) + generated_type.declaration,
        kind: "schema",
      })
    }
    files.push({
      path: source_dir + "/messages.mbt",
      content: source_header(document) + emit_messages(document),
      kind: "messages",
    })
    if options.emit_operation_stubs {
      files.push({
        path: source_dir + "/operations.mbt",
        content: source_header(document) + emit_operations(document),
        kind: "operations",
      })
    }
    if options.emit_protocol_bindings {
      files.push({
        path: source_dir + "/bindings.mbt",
        content: source_header(document) + emit_bindings(document),
        kind: "bindings",
      })
    }
  } else {
    let mut content = source_header(document)
    for generated_type in types {
      content = content + generated_type.declaration + "\n"
    }
    content = content + emit_messages(document)
    if options.emit_operation_stubs {
      content = content + emit_operations(document)
    }
    if options.emit_protocol_bindings {
      content = content + emit_bindings(document)
    }
    files.push({ path: source_dir + "/generated.mbt", content, kind: "source", })
  }
  {
    files,
    diagnostics,
    schema_count: document.schemas.length(),
    message_count: document_inventory(document).message_count,
    operation_count: document.operations.length(),
  }
}

///|
/// Parse JSON and generate a project in one call.
pub fn generate_from_json(
  input : String,
  options? : CodegenOptions = default_codegen_options(),
) -> Result[GenerationPlan, String] {
  match parse(input) {
    Ok(document) => Ok(generate_project(document, options~))
    Err(error) => Err(error)
  }
}

///|
pub fn find_generated_file(
  plan : GenerationPlan,
  path : String,
) -> GeneratedFile? {
  for file in plan.files {
    if file.path == path {
      return Some(file)
    }
  }
  None
}

///|
pub fn generation_has_errors(plan : GenerationPlan) -> Bool {
  for diagnostic in plan.diagnostics {
    if diagnostic.severity == "error" {
      return true
    }
  }
  false
}

///|
pub fn generation_manifest(plan : GenerationPlan) -> String {
  let files = plan.files.copy()
  files.sort_by(fn(left, right) { left.path.compare(right.path) })
  let mut output = ""
  for file in files {
    output = output +
      file.kind +
      "\t" +
      file.path +
      "\t" +
      file.content.length().to_string() +
      "\n"
  }
  output
}
