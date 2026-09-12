///|
/// A small, typed and executable AsyncAPI 3.0 document model.
///
/// This release supports JSON documents, local references, channels,
/// operations, messages, a JSON Schema subset, and compatibility diagnostics.
/// It intentionally does not claim complete YAML or JSON Schema support.
pub struct AsyncApiDocument {
  asyncapi : String
  version : String
  title : String
  channels : Map[String, AsyncApiChannel]
  operations : Array[AsyncApiOperation]
  schemas : Map[String, Schema]
  messages : Map[String, AsyncApiMessage]
} derive(Eq, Debug)

///|
pub struct AsyncApiChannel {
  address : String
  messages : Map[String, AsyncApiMessage]
  binding : String?
} derive(Eq, Debug)

///|
pub struct AsyncApiOperation {
  name : String
  action : String
  channel : String
  messages : Array[String]
  protocol : String?
} derive(Eq, Debug)

///|
pub struct AsyncApiMessage {
  name : String
  title : String
  content_type : String?
  payload : Schema?
} derive(Eq, Debug)

///|
pub struct Schema {
  kind : String?
  required : Array[String]
  properties : Map[String, Schema]
  enum_values : Array[String]
  ref_name : String?
  items : Schema?
  minimum : Double?
  maximum : Double?
} derive(Eq, Debug)

///|
pub struct Diagnostic {
  severity : String
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
pub fn parse(input : String) -> Result[AsyncApiDocument, String] {
  let value = @json.parse(input) catch {
    _ => return Err("invalid JSON".to_string())
  }
  parse_document(value)
}

///|
pub fn validate(document : AsyncApiDocument) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  if document.asyncapi != "3.0.0" {
    issues.push(
      error(
        "asyncapi.version.unsupported", "$.asyncapi", "only AsyncAPI 3.0.0 is supported",
      ),
    )
  }
  if document.title.length() == 0 {
    issues.push(
      error(
        "info.title.missing", "$.info.title", "info.title must not be empty",
      ),
    )
  }
  if document.channels.is_empty() {
    issues.push(
      warning("channels.empty", "$.channels", "document declares no channels"),
    )
  }
  for name, channel in document.channels {
    let path = "$.channels." + name
    if channel.address.length() == 0 {
      issues.push(
        error(
          "channel.address.missing",
          path + ".address",
          "channel.address must not be empty",
        ),
      )
    }
    match channel.binding {
      Some(protocol) =>
        if protocol != "mqtt" && protocol != "kafka" && protocol != "amqp" {
          issues.push(
            warning(
              "channel.binding.unsupported",
              path + ".bindings",
              "binding is parsed but not one of mqtt, kafka, or amqp",
            ),
          )
        }
      None => ()
    }
    for message_name, message in channel.messages {
      validate_message(message, path + ".messages." + message_name, issues)
    }
  }
  for operation in document.operations {
    let path = "$.operations." + operation.name
    if operation.action != "send" && operation.action != "receive" {
      issues.push(
        error(
          "operation.action.invalid",
          path + ".action",
          "action must be send or receive",
        ),
      )
    }
    if document.channels.get(operation.channel) is None {
      issues.push(
        error(
          "operation.channel.missing",
          path + ".channel",
          "operation references an unknown channel",
        ),
      )
    }
    for message_name in operation.messages {
      match document.channels.get(operation.channel) {
        Some(channel) =>
          if channel.messages.get(message_name) is None &&
            document.messages.get(message_name) is None {
            issues.push(
              error(
                "operation.message.missing",
                path + ".messages",
                "operation references an unknown message",
              ),
            )
          }
        None => ()
      }
    }
    if operation.messages.length() == 0 {
      issues.push(
        warning(
          "operation.messages.empty",
          path + ".messages",
          "operation declares no messages",
        ),
      )
    }
  }
  issues
}

///|
pub fn diff(
  before : AsyncApiDocument,
  after : AsyncApiDocument,
) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  for name, old_channel in before.channels {
    match after.channels.get(name) {
      None =>
        issues.push(
          error(
            "compat.channel.removed",
            "$.channels." + name,
            "channel was removed",
          ),
        )
      Some(new_channel) => {
        if old_channel.address != new_channel.address {
          issues.push(
            error(
              "compat.channel.address.changed",
              "$.channels." + name + ".address",
              "channel address changed",
            ),
          )
        }
        if old_channel.binding != new_channel.binding {
          issues.push(
            warning(
              "compat.channel.binding.changed",
              "$.channels." + name + ".bindings",
              "channel binding changed",
            ),
          )
        }
        for message_name, _ in old_channel.messages {
          if new_channel.messages.get(message_name) is None {
            issues.push(
              error(
                "compat.message.removed",
                "$.channels." + name + ".messages." + message_name,
                "message was removed",
              ),
            )
          }
        }
        for message_name, _ in new_channel.messages {
          if old_channel.messages.get(message_name) is None {
            issues.push(
              info(
                "compat.message.added",
                "$.channels." + name + ".messages." + message_name,
                "message was added",
              ),
            )
          }
        }
      }
    }
  }
  for name, _ in after.channels {
    if before.channels.get(name) is None {
      issues.push(
        info("compat.channel.added", "$.channels." + name, "channel was added"),
      )
    }
  }
  for name, _ in before.schemas {
    if after.schemas.get(name) is None {
      issues.push(
        warning(
          "compat.schema.removed",
          "$.components.schemas." + name,
          "schema was removed",
        ),
      )
    }
  }
  for name, _ in after.schemas {
    if before.schemas.get(name) is None {
      issues.push(
        info(
          "compat.schema.added",
          "$.components.schemas." + name,
          "schema was added",
        ),
      )
    }
  }
  for old_operation in before.operations {
    match find_operation(after.operations, old_operation.name) {
      None =>
        issues.push(
          error(
            "compat.operation.removed",
            "$.operations." + old_operation.name,
            "operation was removed",
          ),
        )
      Some(new_operation) => {
        if old_operation.channel != new_operation.channel {
          issues.push(
            error(
              "compat.operation.channel.changed",
              "$.operations." + old_operation.name + ".channel",
              "operation channel changed",
            ),
          )
        }
        if old_operation.action != new_operation.action {
          issues.push(
            error(
              "compat.operation.action.changed",
              "$.operations." + old_operation.name + ".action",
              "operation action changed",
            ),
          )
        }
      }
    }
  }
  for new_operation in after.operations {
    if find_operation(before.operations, new_operation.name) is None {
      issues.push(
        info(
          "compat.operation.added",
          "$.operations." + new_operation.name,
          "operation was added",
        ),
      )
    }
  }
  issues
}

///|
pub fn diagnostics_to_text(issues : Array[Diagnostic]) -> String {
  if issues.length() == 0 {
    return "ok"
  }
  let lines : Array[String] = []
  for issue in issues {
    lines.push(
      issue.severity +
      " " +
      issue.code +
      " " +
      issue.path +
      ": " +
      issue.message,
    )
  }
  lines.join("\n")
}

///|
/// Validate a JSON value against the supported schema subset of a message.
pub fn validate_payload(
  message : AsyncApiMessage,
  payload : Json,
) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  match message.payload {
    Some(schema) => validate_json_schema(schema, payload, "$.payload", issues)
    None =>
      issues.push(
        error(
          "message.payload.missing", "$.payload", "message has no payload schema",
        ),
      )
  }
  issues
}

///|
fn parse_document(value : Json) -> Result[AsyncApiDocument, String] {
  let root = match value {
    Object(object) => object
    _ => return Err("document must be a JSON object".to_string())
  }
  let asyncapi = match string_field(root, "asyncapi", "$.asyncapi") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let info = match object_field(root, "info", "$.info") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let title = match string_field(info, "title", "$.info.title") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let schemas = parse_schemas(root)
  let messages = parse_component_messages(root, schemas)
  let channels = match root.get("channels") {
    Some(Object(value)) => parse_channels(value, schemas)
    Some(_) => return Err("$.channels must be an object".to_string())
    None => Map([])
  }
  let operations = match root.get("operations") {
    Some(Object(value)) => parse_operations(value)
    Some(_) => return Err("$.operations must be an object".to_string())
    None => []
  }
  Ok({
    asyncapi,
    version: asyncapi,
    title,
    channels,
    operations,
    schemas,
    messages,
  })
}

///|
fn parse_schemas(root : Map[String, Json]) -> Map[String, Schema] {
  let result : Map[String, Schema] = Map([])
  match root.get("components") {
    Some(Object(components)) =>
      match components.get("schemas") {
        Some(Object(raw)) =>
          for name, value in raw {
            result[name] = parse_schema(value)
          }
        _ => ()
      }
    _ => ()
  }
  result
}

///|
fn parse_component_messages(
  root : Map[String, Json],
  schemas : Map[String, Schema],
) -> Map[String, AsyncApiMessage] {
  let result : Map[String, AsyncApiMessage] = Map([])
  match root.get("components") {
    Some(Object(components)) =>
      match components.get("messages") {
        Some(Object(raw)) =>
          for name, value in raw {
            result[name] = parse_message(name, value, schemas)
          }
        _ => ()
      }
    _ => ()
  }
  result
}

///|
fn parse_channels(
  raw : Map[String, Json],
  schemas : Map[String, Schema],
) -> Map[String, AsyncApiChannel] {
  let result : Map[String, AsyncApiChannel] = Map([])
  for name, value in raw {
    match value {
      Object(object) => {
        let address = match object.get("address") {
          Some(String(value)) => value
          _ => ""
        }
        let binding = parse_binding(object)
        let messages : Map[String, AsyncApiMessage] = Map([])
        match object.get("messages") {
          Some(Object(values)) =>
            for message_name, message in values {
              messages[message_name] = parse_message(
                message_name, message, schemas,
              )
            }
          _ => ()
        }
        result[name] = { address, messages, binding }
      }
      _ => result[name] = { address: "", messages: Map([]), binding: None }
    }
  }
  result
}

///|
fn parse_operations(raw : Map[String, Json]) -> Array[AsyncApiOperation] {
  let result : Array[AsyncApiOperation] = []
  for name, value in raw {
    match value {
      Object(object) => {
        let action = match object.get("action") {
          Some(String(value)) => value
          _ => ""
        }
        let channel = match object.get("channel") {
          Some(Object(value)) => ref_name(value)
          Some(String(value)) => value
          _ => ""
        }
        let messages : Array[String] = []
        match object.get("messages") {
          Some(Array(values)) =>
            for item in values {
              match item {
                Object(reference) => messages.push(message_ref_name(reference))
                String(value) => messages.push(value)
                _ => ()
              }
            }
          _ => ()
        }
        result.push({ name, action, channel, messages, protocol: None })
      }
      _ =>
        result.push({
          name,
          action: "",
          channel: "",
          messages: [],
          protocol: None,
        })
    }
  }
  result
}

///|
fn parse_message(
  name : String,
  value : Json,
  schemas : Map[String, Schema],
) -> AsyncApiMessage {
  match value {
    Object(object) => {
      let title = match object.get("title") {
        Some(String(value)) => value
        _ => name
      }
      let content_type = match object.get("contentType") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let payload = match object.get("payload") {
        Some(value) => Some(resolve_schema(parse_schema(value), schemas))
        None => None
      }
      { name, title, content_type, payload }
    }
    _ => { name, title: name, content_type: None, payload: None }
  }
}

///|
fn parse_schema(value : Json) -> Schema {
  match value {
    Object(object) => {
      let kind = match object.get("type") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let ref_name = match object.get("$ref") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let required : Array[String] = []
      match object.get("required") {
        Some(Array(values)) =>
          for item in values {
            match item {
              String(value) => required.push(value)
              _ => ()
            }
          }
        _ => ()
      }
      let properties : Map[String, Schema] = Map([])
      match object.get("properties") {
        Some(Object(values)) =>
          for name, property in values {
            properties[name] = parse_schema(property)
          }
        _ => ()
      }
      let enum_values : Array[String] = []
      match object.get("enum") {
        Some(Array(values)) =>
          for item in values {
            match item {
              String(value) => enum_values.push(value)
              _ => ()
            }
          }
        _ => ()
      }
      let items = match object.get("items") {
        Some(value) => Some(parse_schema(value))
        None => None
      }
      let minimum = number_field(object, "minimum")
      let maximum = number_field(object, "maximum")
      {
        kind,
        required,
        properties,
        enum_values,
        ref_name,
        items,
        minimum,
        maximum,
      }
    }
    _ =>
      {
        kind: None,
        required: [],
        properties: Map([]),
        enum_values: [],
        ref_name: None,
        items: None,
        minimum: None,
        maximum: None,
      }
  }
}

///|
fn resolve_schema(schema : Schema, schemas : Map[String, Schema]) -> Schema {
  let resolved = match schema.ref_name {
    Some(reference) => {
      let prefix = "#/components/schemas/"
      if reference.has_prefix(prefix) {
        match
          schemas.get(reference[prefix.length():reference.length()].to_owned()) {
          Some(value) => value
          None => schema
        }
      } else {
        schema
      }
    }
    None => schema
  }
  let properties : Map[String, Schema] = Map([])
  for name, property in resolved.properties {
    properties[name] = resolve_schema(property, schemas)
  }
  let items = match resolved.items {
    Some(item) => Some(resolve_schema(item, schemas))
    None => None
  }
  { ..resolved, properties, items }
}

///|
fn validate_message(
  message : AsyncApiMessage,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  if message.title.length() == 0 {
    issues.push(
      warning("message.title.missing", path + ".title", "message has no title"),
    )
  }
  match message.payload {
    Some(schema) =>
      match schema.ref_name {
        Some(reference) =>
          issues.push(
            error(
              "schema.ref.missing",
              path + ".payload.$ref",
              "local schema reference could not be resolved: " + reference,
            ),
          )
        None =>
          if schema.kind is None && schema.properties.is_empty() {
            issues.push(
              warning(
                "message.payload.empty",
                path + ".payload",
                "payload schema is empty",
              ),
            )
          }
      }
    None =>
      issues.push(
        warning(
          "message.payload.missing",
          path + ".payload",
          "message has no payload schema",
        ),
      )
  }
}

///|
fn validate_json_schema(
  schema : Schema,
  value : Json,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  match schema.kind {
    Some(kind) => {
      let actual = json_kind(value)
      if kind != actual && !(kind == "integer" && actual == "number") {
        issues.push(
          error(
            "payload.type.mismatch", path, "payload type does not match schema type",
          ),
        )
      }
    }
    None => ()
  }
  match value {
    Object(object) => {
      for name in schema.required {
        if object.get(name) is None {
          issues.push(
            error(
              "payload.required.missing",
              path + "." + name,
              "required property is missing",
            ),
          )
        }
      }
      for name, property in schema.properties {
        match object.get(name) {
          Some(child) =>
            validate_json_schema(property, child, path + "." + name, issues)
          None => ()
        }
      }
    }
    String(text) =>
      if schema.enum_values.length() > 0 &&
        !contains_string(schema.enum_values, text) {
        issues.push(
          error("payload.enum.invalid", path, "string value is not in enum"),
        )
      }
    Array(values) =>
      match schema.items {
        Some(item_schema) =>
          for index, item in values {
            validate_json_schema(
              item_schema,
              item,
              path + "[" + index.to_string() + "]",
              issues,
            )
          }
        None => ()
      }
    _ => ()
  }
  match value {
    Number(number, ..) => {
      match schema.minimum {
        Some(minimum) =>
          if number < minimum {
            issues.push(
              error("payload.number.minimum", path, "number is below minimum"),
            )
          }
        None => ()
      }
      match schema.maximum {
        Some(maximum) =>
          if number > maximum {
            issues.push(
              error("payload.number.maximum", path, "number is above maximum"),
            )
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn json_kind(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(_, repr~) => {
      ignore(repr)
      "number"
    }
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn contains_string(items : Array[String], value : String) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

///|
fn find_operation(
  operations : Array[AsyncApiOperation],
  name : String,
) -> AsyncApiOperation? {
  for operation in operations {
    if operation.name == name {
      return Some(operation)
    }
  }
  None
}

///|
fn parse_binding(object : Map[String, Json]) -> String? {
  match object.get("bindings") {
    Some(Object(bindings)) => {
      for name, _ in bindings {
        return Some(name)
      }
      None
    }
    _ => None
  }
}

///|
fn ref_name(object : Map[String, Json]) -> String {
  match object.get("$ref") {
    Some(String(value)) => {
      let channel_prefix = "#/channels/"
      if value.has_prefix(channel_prefix) {
        value[channel_prefix.length():value.length()].to_owned()
      } else {
        value
      }
    }
    _ => ""
  }
}

///|
fn message_ref_name(object : Map[String, Json]) -> String {
  match object.get("$ref") {
    Some(String(value)) => {
      let marker = "/messages/"
      if value.contains(marker) {
        let mut last = value
        for part in value.split("/") {
          last = part.to_owned()
        }
        last
      } else {
        value
      }
    }
    _ => ""
  }
}

///|
fn string_field(
  object : Map[String, Json],
  name : String,
  path : String,
) -> Result[String, String] {
  match object.get(name) {
    Some(String(value)) => Ok(value)
    _ => Err(path + " must be a string")
  }
}

///|
fn object_field(
  object : Map[String, Json],
  name : String,
  path : String,
) -> Result[Map[String, Json], String] {
  match object.get(name) {
    Some(Object(value)) => Ok(value)
    _ => Err(path + " must be an object")
  }
}

///|
fn number_field(object : Map[String, Json], name : String) -> Double? {
  match object.get(name) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn error(code : String, path : String, message : String) -> Diagnostic {
  { severity: "error", code, path, message }
}

///|
fn warning(code : String, path : String, message : String) -> Diagnostic {
  { severity: "warning", code, path, message }
}

///|
fn info(code : String, path : String, message : String) -> Diagnostic {
  { severity: "info", code, path, message }
}
