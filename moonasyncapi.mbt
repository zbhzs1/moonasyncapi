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
  servers : Map[String, AsyncApiServer]
} derive(Eq, Debug)

///|
pub struct AsyncApiServer {
  name : String
  host : String
  protocol : String
  protocol_version : String?
  pathname : String?
  description : String?
} derive(Eq, Debug)

///|
pub struct AsyncApiChannel {
  address : String
  messages : Map[String, AsyncApiMessage]
  binding : String?
  parameters : Map[String, ChannelParameter]
} derive(Eq, Debug)

///|
pub struct ChannelParameter {
  name : String
  description : String?
  location : String?
  enum_values : Array[String]
  default_value : String?
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
  enum_json_values : Array[Json]
  const_value : Json?
  default_value : Json?
  examples : Array[Json]
  ref_name : String?
  items : Schema?
  minimum : Double?
  maximum : Double?
  exclusive_minimum : Double?
  exclusive_maximum : Double?
  min_length : Double?
  max_length : Double?
  min_items : Double?
  max_items : Double?
  unique_items : Bool
  min_properties : Double?
  max_properties : Double?
  unsupported_keywords : Array[String]
} derive(Eq, Debug)

///|
pub struct Diagnostic {
  severity : String
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
pub struct DiagnosticSummary {
  errors : Int
  warnings : Int
  infos : Int
  total : Int
} derive(Eq, Debug)

///|
pub fn parse(input : String) -> Result[AsyncApiDocument, String] {
  let value = @json.parse(input) catch {
    _ => return Err("invalid JSON".to_string())
  }
  parse_document(value)
}

///|
/// Find a channel by its document key.
pub fn find_channel(
  document : AsyncApiDocument,
  name : String,
) -> AsyncApiChannel? {
  document.channels.get(name)
}

///|
/// Find a declared parameter on a channel.
pub fn find_channel_parameter(
  channel : AsyncApiChannel,
  name : String,
) -> ChannelParameter? {
  channel.parameters.get(name)
}

///|
/// Extract parameter names from a channel address in declaration order.
pub fn address_parameters(address : String) -> Array[String] {
  let result : Array[String] = []
  let parts = address.split("{")
  for index, part in parts {
    if index > 0 {
      if part.contains("}") {
        for closed_index, value in part.split("}") {
          if closed_index == 0 && value.length() > 0 {
            result.push(value.to_owned())
          }
        }
      }
    }
  }
  result
}

///|
/// Render a concrete channel address from declared parameter values.
/// Declared defaults are used when the caller omits a value.
pub fn render_channel_address(
  channel : AsyncApiChannel,
  values : Map[String, String],
) -> Result[String, String] {
  let template_issues = validate_address_template(channel.address, "$.address")
  if template_issues.length() > 0 {
    return Err("channel address template is malformed")
  }
  let mut output = ""
  for part_index, part in channel.address.split("{") {
    if part_index == 0 {
      output = output + part.to_owned()
    } else {
      let mut parameter_name = ""
      let mut suffix = ""
      for closed_index, piece in part.split("}") {
        if closed_index == 0 {
          parameter_name = piece.to_owned()
        } else if closed_index == 1 {
          suffix = piece.to_owned()
        }
      }
      let parameter = match channel.parameters.get(parameter_name) {
        Some(value) => value
        None => return Err("undeclared channel parameter: " + parameter_name)
      }
      let rendered = match values.get(parameter_name) {
        Some(value) => value
        None =>
          match parameter.default_value {
            Some(value) => value
            None =>
              return Err("missing channel parameter value: " + parameter_name)
          }
      }
      if parameter.enum_values.length() > 0 &&
        !contains_string(parameter.enum_values, rendered) {
        return Err("channel parameter value is outside enum: " + parameter_name)
      }
      output = output + rendered + suffix
    }
  }
  Ok(output)
}

///|
/// Find a reusable component schema by name.
pub fn find_schema(document : AsyncApiDocument, name : String) -> Schema? {
  document.schemas.get(name)
}

///|
/// Find a reusable component message by name.
pub fn find_message(
  document : AsyncApiDocument,
  name : String,
) -> AsyncApiMessage? {
  document.messages.get(name)
}

///|
/// Find an operation by its document key.
pub fn find_operation(
  document : AsyncApiDocument,
  name : String,
) -> AsyncApiOperation? {
  find_operation_in(document.operations, name)
}

///|
/// Find a server declaration by name.
pub fn find_server(
  document : AsyncApiDocument,
  name : String,
) -> AsyncApiServer? {
  document.servers.get(name)
}

///|
/// Return a compact inventory of the parsed contract.
pub fn document_summary(document : AsyncApiDocument) -> String {
  "AsyncAPI " +
  document.version +
  ": " +
  document.channels.length().to_string() +
  " channels, " +
  document.operations.length().to_string() +
  " operations, " +
  document.messages.length().to_string() +
  " messages, " +
  document.schemas.length().to_string() +
  " schemas, " +
  document.servers.length().to_string() +
  " servers"
}

///|
/// Count diagnostics by severity for CI and command-line consumers.
pub fn summarize_diagnostics(issues : Array[Diagnostic]) -> DiagnosticSummary {
  let mut errors = 0
  let mut warnings = 0
  let mut infos = 0
  for issue in issues {
    if issue.severity == "error" {
      errors += 1
    } else if issue.severity == "warning" {
      warnings += 1
    } else {
      infos += 1
    }
  }
  { errors, warnings, infos, total: issues.length() }
}

///|
/// Keep only diagnostics with the requested severity.
pub fn diagnostics_by_severity(
  issues : Array[Diagnostic],
  severity : String,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for issue in issues {
    if issue.severity == severity {
      result.push(issue)
    }
  }
  result
}

///|
/// Return the most severe level present, or `none` for an empty list.
pub fn highest_severity(issues : Array[Diagnostic]) -> String {
  let mut has_warning = false
  let mut has_info = false
  for issue in issues {
    if issue.severity == "error" {
      return "error"
    }
    if issue.severity == "warning" {
      has_warning = true
    } else {
      has_info = true
    }
  }
  if has_warning {
    "warning"
  } else if has_info {
    "info"
  } else {
    "none"
  }
}

///|
/// Recommend a conventional process exit code for the diagnostic set.
pub fn diagnostics_exit_code(
  issues : Array[Diagnostic],
  warnings_as_errors? : Bool = false,
) -> Int {
  let summary = summarize_diagnostics(issues)
  if summary.errors > 0 || (warnings_as_errors && summary.warnings > 0) {
    1
  } else {
    0
  }
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
    for
      address_issue in validate_address_template(
        channel.address,
        path + ".address",
      ) {
      issues.push(address_issue)
    }
    validate_channel_parameters(channel, path, issues)
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
  for name, server in document.servers {
    validate_server(server, "$.servers." + name, issues)
  }
  for name, schema in document.schemas {
    validate_schema_definition(schema, "$.components.schemas." + name, issues)
  }
  for name, message in document.messages {
    validate_message(message, "$.components.messages." + name, issues)
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
    match operation.protocol {
      Some(protocol) =>
        match document.channels.get(operation.channel) {
          Some(channel) =>
            match channel.binding {
              Some(binding) =>
                if protocol != binding {
                  issues.push(
                    warning(
                      "operation.protocol.mismatch",
                      path + ".protocol",
                      "operation protocol does not match channel binding",
                    ),
                  )
                }
              None => ()
            }
          None => ()
        }
      None => ()
    }
    let seen_messages : Map[String, Bool] = Map([])
    for message_name in operation.messages {
      if seen_messages.get(message_name) is Some(_) {
        issues.push(
          warning(
            "operation.messages.duplicate",
            path + ".messages",
            "operation lists the same message more than once: " + message_name,
          ),
        )
      }
      seen_messages[message_name] = true
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
        compare_channel_parameters(
          old_channel,
          new_channel,
          "$.channels." + name,
          issues,
        )
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
        for message_name, old_message in old_channel.messages {
          match new_channel.messages.get(message_name) {
            Some(new_message) =>
              compare_message_compatibility(
                old_message,
                new_message,
                "$.channels." + name + ".messages." + message_name,
                issues,
              )
            None => ()
          }
        }
      }
    }
  }
  compare_servers(before.servers, after.servers, issues)
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
  for name, old_message in before.messages {
    match after.messages.get(name) {
      None =>
        issues.push(
          error(
            "compat.component_message.removed",
            "$.components.messages." + name,
            "component message was removed",
          ),
        )
      Some(new_message) =>
        compare_message_compatibility(
          old_message,
          new_message,
          "$.components.messages." + name,
          issues,
        )
    }
  }
  for name, _ in after.messages {
    if before.messages.get(name) is None {
      issues.push(
        info(
          "compat.component_message.added",
          "$.components.messages." + name,
          "component message was added",
        ),
      )
    }
  }
  for name, old_schema in before.schemas {
    match after.schemas.get(name) {
      Some(new_schema) =>
        compare_schema_compatibility(
          old_schema,
          new_schema,
          "$.components.schemas." + name,
          issues,
        )
      None => ()
    }
  }
  for old_operation in before.operations {
    match find_operation_in(after.operations, old_operation.name) {
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
        for old_message in old_operation.messages {
          if !contains_string(new_operation.messages, old_message) {
            issues.push(
              error(
                "compat.operation.message.removed",
                "$.operations." + old_operation.name + ".messages",
                "operation message was removed: " + old_message,
              ),
            )
          }
        }
        for new_message in new_operation.messages {
          if !contains_string(old_operation.messages, new_message) {
            issues.push(
              info(
                "compat.operation.message.added",
                "$.operations." + old_operation.name + ".messages",
                "operation message was added: " + new_message,
              ),
            )
          }
        }
      }
    }
  }
  for new_operation in after.operations {
    if find_operation_in(before.operations, new_operation.name) is None {
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
fn compare_channel_parameters(
  before : AsyncApiChannel,
  after : AsyncApiChannel,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  for name, old_parameter in before.parameters {
    match after.parameters.get(name) {
      None =>
        issues.push(
          error(
            "compat.channel.parameter.removed",
            path + ".parameters." + name,
            "channel parameter was removed",
          ),
        )
      Some(new_parameter) => {
        if old_parameter.location != new_parameter.location {
          issues.push(
            warning(
              "compat.channel.parameter.location.changed",
              path + ".parameters." + name + ".location",
              "channel parameter location changed",
            ),
          )
        }
        for old_value in old_parameter.enum_values {
          if new_parameter.enum_values.length() > 0 &&
            !contains_string(new_parameter.enum_values, old_value) {
            issues.push(
              error(
                "compat.channel.parameter.enum.removed",
                path + ".parameters." + name + ".enum",
                "channel parameter enum value was removed: " + old_value,
              ),
            )
          }
        }
      }
    }
  }
  for name, _ in after.parameters {
    if before.parameters.get(name) is None {
      issues.push(
        info(
          "compat.channel.parameter.added",
          path + ".parameters." + name,
          "channel parameter was added",
        ),
      )
    }
  }
}

///|
fn validate_server(
  server : AsyncApiServer,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  if server.host.length() == 0 {
    issues.push(
      error(
        "server.host.missing",
        path + ".host",
        "server host must not be empty",
      ),
    )
  } else if server.host.contains("://") {
    issues.push(
      warning(
        "server.host.scheme",
        path + ".host",
        "server host should not include a URI scheme",
      ),
    )
  }
  if server.protocol.length() == 0 {
    issues.push(
      error(
        "server.protocol.missing",
        path + ".protocol",
        "server protocol must not be empty",
      ),
    )
  } else if !is_recognized_server_protocol(server.protocol) {
    issues.push(
      warning(
        "server.protocol.unknown",
        path + ".protocol",
        "server protocol is outside the recognized set: " + server.protocol,
      ),
    )
  }
  match server.pathname {
    Some(pathname) =>
      if pathname.length() > 0 && !pathname.has_prefix("/") {
        issues.push(
          warning(
            "server.pathname.invalid",
            path + ".pathname",
            "server pathname should start with a slash",
          ),
        )
      }
    None => ()
  }
  match server.protocol_version {
    Some(version) =>
      if version.length() == 0 {
        issues.push(
          warning(
            "server.protocol_version.empty",
            path + ".protocolVersion",
            "protocolVersion must not be empty when supplied",
          ),
        )
      }
    None => ()
  }
}

///|
fn is_recognized_server_protocol(protocol : String) -> Bool {
  protocol == "mqtt" ||
  protocol == "mqtts" ||
  protocol == "kafka" ||
  protocol == "kafka-secure" ||
  protocol == "amqp" ||
  protocol == "amqps" ||
  protocol == "ws" ||
  protocol == "wss" ||
  protocol == "http" ||
  protocol == "https"
}

///|
fn compare_servers(
  before : Map[String, AsyncApiServer],
  after : Map[String, AsyncApiServer],
  issues : Array[Diagnostic],
) -> Unit {
  for name, old_server in before {
    match after.get(name) {
      None =>
        issues.push(
          error(
            "compat.server.removed",
            "$.servers." + name,
            "server was removed",
          ),
        )
      Some(new_server) => {
        if old_server.host != new_server.host {
          issues.push(
            error(
              "compat.server.host.changed",
              "$.servers." + name + ".host",
              "server host changed",
            ),
          )
        }
        if old_server.protocol != new_server.protocol {
          issues.push(
            error(
              "compat.server.protocol.changed",
              "$.servers." + name + ".protocol",
              "server protocol changed",
            ),
          )
        }
        if old_server.pathname != new_server.pathname {
          issues.push(
            warning(
              "compat.server.pathname.changed",
              "$.servers." + name + ".pathname",
              "server pathname changed",
            ),
          )
        }
        if old_server.protocol_version != new_server.protocol_version {
          issues.push(
            warning(
              "compat.server.protocol_version.changed",
              "$.servers." + name + ".protocolVersion",
              "server protocol version changed",
            ),
          )
        }
      }
    }
  }
  for name, _ in after {
    if before.get(name) is None {
      issues.push(
        info("compat.server.added", "$.servers." + name, "server was added"),
      )
    }
  }
}

///|
fn compare_message_compatibility(
  before : AsyncApiMessage,
  after : AsyncApiMessage,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  if before.content_type != after.content_type {
    issues.push(
      error(
        "compat.message.content_type.changed",
        path + ".contentType",
        "message content type changed",
      ),
    )
  }
  if before.title != after.title {
    issues.push(
      info(
        "compat.message.title.changed",
        path + ".title",
        "message title changed",
      ),
    )
  }
  match before.payload {
    Some(old_schema) =>
      match after.payload {
        Some(new_schema) =>
          compare_schema_compatibility(
            old_schema,
            new_schema,
            path + ".payload",
            issues,
          )
        None =>
          issues.push(
            error(
              "compat.message.payload.removed",
              path + ".payload",
              "message payload schema was removed",
            ),
          )
      }
    None =>
      match after.payload {
        Some(_) =>
          issues.push(
            info(
              "compat.message.payload.added",
              path + ".payload",
              "message payload schema was added",
            ),
          )
        None => ()
      }
  }
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
/// Validate a payload against every message selected by an operation.
pub fn validate_operation_payload(
  document : AsyncApiDocument,
  operation_name : String,
  payload : Json,
) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  let operation = match find_operation_in(document.operations, operation_name) {
    Some(value) => value
    None => {
      issues.push(
        error(
          "operation.missing",
          "$.operations." + operation_name,
          "operation does not exist",
        ),
      )
      return issues
    }
  }
  let channel = match document.channels.get(operation.channel) {
    Some(value) => value
    None => {
      issues.push(
        error(
          "operation.channel.missing",
          "$.operations." + operation_name + ".channel",
          "operation references an unknown channel",
        ),
      )
      return issues
    }
  }
  if operation.messages.length() == 0 {
    issues.push(
      warning(
        "operation.messages.empty",
        "$.operations." + operation_name + ".messages",
        "operation declares no messages",
      ),
    )
  }
  for message_name in operation.messages {
    match channel.messages.get(message_name) {
      Some(message) =>
        for issue in validate_payload(message, payload) {
          issues.push(issue)
        }
      None =>
        match document.messages.get(message_name) {
          Some(message) =>
            for issue in validate_payload(message, payload) {
              issues.push(issue)
            }
          None =>
            issues.push(
              error(
                "operation.message.missing",
                "$.operations." + operation_name + ".messages",
                "operation references an unknown message",
              ),
            )
        }
    }
  }
  issues
}

///|
pub fn diagnostics_has_errors(issues : Array[Diagnostic]) -> Bool {
  for issue in issues {
    if issue.severity == "error" {
      return true
    }
  }
  false
}

///|
pub fn diagnostics_count(issues : Array[Diagnostic], severity : String) -> Int {
  let mut count = 0
  for issue in issues {
    if issue.severity == severity {
      count += 1
    }
  }
  count
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
  let servers = match root.get("servers") {
    Some(Object(value)) => parse_servers(value)
    Some(_) => return Err("$.servers must be an object".to_string())
    None => Map([])
  }
  Ok({
    asyncapi,
    version: asyncapi,
    title,
    channels,
    operations,
    schemas,
    messages,
    servers,
  })
}

///|
fn parse_servers(raw : Map[String, Json]) -> Map[String, AsyncApiServer] {
  let result : Map[String, AsyncApiServer] = Map([])
  for name, value in raw {
    match value {
      Object(server) => {
        let host = match server.get("host") {
          Some(String(value)) => value
          _ => ""
        }
        let protocol = match server.get("protocol") {
          Some(String(value)) => value
          _ => ""
        }
        let protocol_version = optional_string_field(server, "protocolVersion")
        let pathname = optional_string_field(server, "pathname")
        let description = optional_string_field(server, "description")
        result[name] = {
          name,
          host,
          protocol,
          protocol_version,
          pathname,
          description,
        }
      }
      _ =>
        result[name] = {
          name,
          host: "",
          protocol: "",
          protocol_version: None,
          pathname: None,
          description: None,
        }
    }
  }
  result
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
        let parameters = parse_channel_parameters(object)
        result[name] = { address, messages, binding, parameters }
      }
      _ =>
        result[name] = {
          address: "",
          messages: Map([]),
          binding: None,
          parameters: Map([]),
        }
    }
  }
  result
}

///|
fn parse_channel_parameters(
  channel : Map[String, Json],
) -> Map[String, ChannelParameter] {
  let result : Map[String, ChannelParameter] = Map([])
  match channel.get("parameters") {
    Some(Object(parameters)) =>
      for name, value in parameters {
        match value {
          Object(parameter) => {
            let description = optional_string_field(parameter, "description")
            let location = optional_string_field(parameter, "location")
            let default_value = optional_string_field(parameter, "default")
            let enum_values : Array[String] = []
            match parameter.get("enum") {
              Some(Array(values)) =>
                for item in values {
                  match item {
                    String(text) => enum_values.push(text)
                    _ => ()
                  }
                }
              _ => ()
            }
            result[name] = {
              name,
              description,
              location,
              enum_values,
              default_value,
            }
          }
          _ =>
            result[name] = {
              name,
              description: None,
              location: None,
              enum_values: [],
              default_value: None,
            }
        }
      }
    _ => ()
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
        let protocol = match object.get("protocol") {
          Some(String(value)) => Some(value)
          _ => None
        }
        result.push({ name, action, channel, messages, protocol })
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
      let enum_json_values : Array[Json] = []
      match object.get("enum") {
        Some(Array(values)) =>
          for item in values {
            enum_json_values.push(item)
            match item {
              String(value) => enum_values.push(value)
              _ => ()
            }
          }
        _ => ()
      }
      let const_value = object.get("const")
      let default_value = object.get("default")
      let examples : Array[Json] = []
      match object.get("examples") {
        Some(Array(values)) =>
          for value in values {
            examples.push(value)
          }
        _ => ()
      }
      let items = match object.get("items") {
        Some(value) => Some(parse_schema(value))
        None => None
      }
      let minimum = number_field(object, "minimum")
      let maximum = number_field(object, "maximum")
      let exclusive_minimum = number_field(object, "exclusiveMinimum")
      let exclusive_maximum = number_field(object, "exclusiveMaximum")
      let min_length = number_field(object, "minLength")
      let max_length = number_field(object, "maxLength")
      let min_items = number_field(object, "minItems")
      let max_items = number_field(object, "maxItems")
      let unique_items = bool_field(object, "uniqueItems", false)
      let min_properties = number_field(object, "minProperties")
      let max_properties = number_field(object, "maxProperties")
      let unsupported_keywords : Array[String] = []
      for key, _ in object {
        if is_unsupported_schema_keyword(key) {
          unsupported_keywords.push(key)
        }
      }
      {
        kind,
        required,
        properties,
        enum_values,
        enum_json_values,
        const_value,
        default_value,
        examples,
        ref_name,
        items,
        minimum,
        maximum,
        exclusive_minimum,
        exclusive_maximum,
        min_length,
        max_length,
        min_items,
        max_items,
        unique_items,
        min_properties,
        max_properties,
        unsupported_keywords,
      }
    }
    _ =>
      {
        kind: None,
        required: [],
        properties: Map([]),
        enum_values: [],
        enum_json_values: [],
        const_value: None,
        default_value: None,
        examples: [],
        ref_name: None,
        items: None,
        minimum: None,
        maximum: None,
        exclusive_minimum: None,
        exclusive_maximum: None,
        min_length: None,
        max_length: None,
        min_items: None,
        max_items: None,
        unique_items: false,
        min_properties: None,
        max_properties: None,
        unsupported_keywords: [],
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
  { ..resolved, properties, items, ref_name: schema.ref_name }
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
  match message.content_type {
    Some(content_type) =>
      if content_type.length() == 0 || !content_type.contains("/") {
        issues.push(
          warning(
            "message.content_type.invalid",
            path + ".contentType",
            "contentType should use a type/subtype media type",
          ),
        )
      }
    None => ()
  }
  match message.payload {
    Some(schema) => {
      if schema.ref_name is None {
        validate_schema_definition(schema, path + ".payload", issues)
      }
      match schema.ref_name {
        Some(reference) =>
          if schema.kind is None &&
            schema.properties.is_empty() &&
            schema.items is None {
            issues.push(
              error(
                "schema.ref.missing",
                path + ".payload.$ref",
                "local schema reference could not be resolved: " + reference,
              ),
            )
          }
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
fn validate_schema_definition(
  schema : Schema,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  match schema.kind {
    Some(kind) =>
      if !is_supported_schema_kind(kind) {
        issues.push(
          warning(
            "schema.type.unsupported",
            path + ".type",
            "schema type is outside the supported subset: " + kind,
          ),
        )
      }
    None => ()
  }
  match schema.minimum {
    Some(minimum) =>
      match schema.maximum {
        Some(maximum) =>
          if minimum > maximum {
            issues.push(
              error(
                "schema.range.invalid", path, "schema minimum must not exceed maximum",
              ),
            )
          }
        None => ()
      }
    None => ()
  }
  match (schema.exclusive_minimum, schema.exclusive_maximum) {
    (Some(minimum), Some(maximum)) =>
      if minimum >= maximum {
        issues.push(
          error(
            "schema.exclusive_range.invalid", path, "exclusiveMinimum must be less than exclusiveMaximum",
          ),
        )
      }
    _ => ()
  }
  match schema.min_length {
    Some(minimum) => {
      if minimum < 0 {
        issues.push(
          error(
            "schema.length.negative",
            path + ".minLength",
            "schema minLength must not be negative",
          ),
        )
      }
      match schema.max_length {
        Some(maximum) => {
          if maximum < 0 {
            issues.push(
              error(
                "schema.length.negative",
                path + ".maxLength",
                "schema maxLength must not be negative",
              ),
            )
          }
          if minimum > maximum {
            issues.push(
              error(
                "schema.length.invalid", path, "schema minLength must not exceed maxLength",
              ),
            )
          }
        }
        None => ()
      }
    }
    None => ()
  }
  validate_nonnegative_bounds(
    schema.min_items,
    schema.max_items,
    path,
    "items",
    issues,
  )
  validate_nonnegative_bounds(
    schema.min_properties,
    schema.max_properties,
    path,
    "properties",
    issues,
  )
  for keyword in schema.unsupported_keywords {
    issues.push(
      warning(
        "schema.keyword.unsupported",
        path + "." + keyword,
        "schema keyword is recognized but outside the supported subset: " +
        keyword,
      ),
    )
  }
  match schema.default_value {
    Some(value) => {
      let default_issues : Array[Diagnostic] = []
      validate_json_schema(schema, value, path + ".default", default_issues)
      if default_issues.length() > 0 {
        issues.push(
          warning(
            "schema.default.invalid",
            path + ".default",
            "schema default does not satisfy its constraints",
          ),
        )
      }
    }
    None => ()
  }
  for index, example in schema.examples {
    let example_issues : Array[Diagnostic] = []
    validate_json_schema(
      schema,
      example,
      path + ".examples[" + index.to_string() + "]",
      example_issues,
    )
    if example_issues.length() > 0 {
      issues.push(
        warning(
          "schema.example.invalid",
          path + ".examples[" + index.to_string() + "]",
          "schema example does not satisfy its constraints",
        ),
      )
    }
  }
  for name, property in schema.properties {
    if property.ref_name is None {
      validate_schema_definition(property, path + ".properties." + name, issues)
    }
  }
  let seen_required : Map[String, Bool] = Map([])
  for required_name in schema.required {
    if required_name.length() == 0 {
      issues.push(
        warning(
          "schema.required.empty",
          path + ".required",
          "required field name must not be empty",
        ),
      )
    }
    if seen_required.get(required_name) is Some(_) {
      issues.push(
        warning(
          "schema.required.duplicate",
          path + ".required",
          "required field is listed more than once: " + required_name,
        ),
      )
    }
    seen_required[required_name] = true
    if schema.properties.get(required_name) is None {
      issues.push(
        warning(
          "schema.required.unknown",
          path + ".required",
          "required field is not declared in properties: " + required_name,
        ),
      )
    }
  }
  match schema.kind {
    Some(kind) =>
      if kind == "array" && schema.items is None {
        issues.push(
          warning(
            "schema.items.missing",
            path + ".items",
            "array schema does not declare items",
          ),
        )
      }
    None => ()
  }
  match schema.items {
    Some(items) =>
      if items.ref_name is None {
        validate_schema_definition(items, path + ".items", issues)
      }
    None => ()
  }
}

///|
fn is_supported_schema_kind(kind : String) -> Bool {
  kind == "string" ||
  kind == "number" ||
  kind == "integer" ||
  kind == "boolean" ||
  kind == "null" ||
  kind == "object" ||
  kind == "array"
}

///|
fn is_unsupported_schema_keyword(keyword : String) -> Bool {
  keyword == "allOf" ||
  keyword == "anyOf" ||
  keyword == "oneOf" ||
  keyword == "not" ||
  keyword == "pattern" ||
  keyword == "format" ||
  keyword == "additionalProperties"
}

///|
fn validate_nonnegative_bounds(
  minimum : Double?,
  maximum : Double?,
  path : String,
  subject : String,
  issues : Array[Diagnostic],
) -> Unit {
  match minimum {
    Some(value) =>
      if value < 0 {
        issues.push(
          error(
            "schema." + subject + ".negative",
            path,
            "schema " + subject + " minimum must not be negative",
          ),
        )
      }
    None => ()
  }
  match maximum {
    Some(value) =>
      if value < 0 {
        issues.push(
          error(
            "schema." + subject + ".negative",
            path,
            "schema " + subject + " maximum must not be negative",
          ),
        )
      }
    None => ()
  }
  match (minimum, maximum) {
    (Some(low), Some(high)) =>
      if low > high {
        issues.push(
          error(
            "schema." + subject + ".invalid",
            path,
            "schema " + subject + " minimum must not exceed maximum",
          ),
        )
      }
    _ => ()
  }
}

///|
/// Validate the simple `{parameter}` address form used by channel examples.
fn validate_address_template(
  address : String,
  path : String,
) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  let open = address.split("{").length() - 1
  let close = address.split("}").length() - 1
  if open != close {
    issues.push(
      error(
        "channel.address.template.unbalanced", path, "channel address template has unbalanced braces",
      ),
    )
    return issues
  }
  if address.contains("{}") {
    issues.push(
      error(
        "channel.address.template.empty", path, "channel address template parameter must not be empty",
      ),
    )
  }
  issues
}

///|
fn validate_channel_parameters(
  channel : AsyncApiChannel,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  let template_names = address_parameters(channel.address)
  let seen : Map[String, Bool] = Map([])
  for name in template_names {
    if seen.get(name) is Some(_) {
      issues.push(
        warning(
          "channel.parameter.duplicate",
          path + ".address",
          "channel address uses a parameter more than once: " + name,
        ),
      )
    }
    seen[name] = true
    if channel.parameters.get(name) is None {
      issues.push(
        error(
          "channel.parameter.missing",
          path + ".parameters." + name,
          "address parameter has no declaration",
        ),
      )
    }
  }
  for name, parameter in channel.parameters {
    if !contains_string(template_names, name) {
      issues.push(
        warning(
          "channel.parameter.unused",
          path + ".parameters." + name,
          "declared parameter is not used by the channel address",
        ),
      )
    }
    match parameter.location {
      Some(location) =>
        if location.length() == 0 {
          issues.push(
            warning(
              "channel.parameter.location.empty",
              path + ".parameters." + name + ".location",
              "parameter location must not be empty when supplied",
            ),
          )
        }
      None => ()
    }
    let enum_seen : Map[String, Bool] = Map([])
    for value in parameter.enum_values {
      if enum_seen.get(value) is Some(_) {
        issues.push(
          warning(
            "channel.parameter.enum.duplicate",
            path + ".parameters." + name + ".enum",
            "parameter enum contains a duplicate value: " + value,
          ),
        )
      }
      enum_seen[value] = true
    }
    match parameter.default_value {
      Some(value) =>
        if parameter.enum_values.length() > 0 &&
          !contains_string(parameter.enum_values, value) {
          issues.push(
            error(
              "channel.parameter.default.invalid",
              path + ".parameters." + name + ".default",
              "parameter default is not present in its enum",
            ),
          )
        }
      None => ()
    }
  }
}

///|
fn validate_json_schema(
  schema : Schema,
  value : Json,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  match schema.ref_name {
    Some(reference) =>
      if schema.kind is None &&
        schema.properties.is_empty() &&
        schema.items is None {
        issues.push(
          error(
            "schema.ref.missing",
            path + ".$ref",
            "local schema reference could not be resolved: " + reference,
          ),
        )
      }
    None => ()
  }
  let type_matches = match schema.kind {
    Some(kind) => {
      let actual = json_kind(value)
      if kind == "integer" {
        json_is_integer(value)
      } else {
        kind == actual
      }
    }
    None => true
  }
  if !type_matches {
    issues.push(
      error(
        "payload.type.mismatch", path, "payload type does not match schema type",
      ),
    )
    return
  }
  if schema.enum_json_values.length() > 0 &&
    !contains_json(schema.enum_json_values, value) {
    issues.push(
      error("payload.enum.invalid", path, "payload value is not in enum"),
    )
  }
  match schema.const_value {
    Some(expected) =>
      if expected != value {
        issues.push(
          error(
            "payload.const.invalid", path, "payload value does not match const",
          ),
        )
      }
    None => ()
  }
  match value {
    Object(object) => {
      match schema.min_properties {
        Some(limit) =>
          if object.length().to_double() < limit {
            issues.push(
              error(
                "payload.object.min_properties", path, "object has fewer properties than minProperties",
              ),
            )
          }
        None => ()
      }
      match schema.max_properties {
        Some(limit) =>
          if object.length().to_double() > limit {
            issues.push(
              error(
                "payload.object.max_properties", path, "object has more properties than maxProperties",
              ),
            )
          }
        None => ()
      }
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
    String(text) => {
      match schema.min_length {
        Some(limit) =>
          if text.length().to_double() < limit {
            issues.push(
              error(
                "payload.string.min_length", path, "string is shorter than minLength",
              ),
            )
          }
        None => ()
      }
      match schema.max_length {
        Some(limit) =>
          if text.length().to_double() > limit {
            issues.push(
              error(
                "payload.string.max_length", path, "string is longer than maxLength",
              ),
            )
          }
        None => ()
      }
    }
    Array(values) => {
      match schema.min_items {
        Some(limit) =>
          if values.length().to_double() < limit {
            issues.push(
              error(
                "payload.array.min_items", path, "array has fewer items than minItems",
              ),
            )
          }
        None => ()
      }
      match schema.max_items {
        Some(limit) =>
          if values.length().to_double() > limit {
            issues.push(
              error(
                "payload.array.max_items", path, "array has more items than maxItems",
              ),
            )
          }
        None => ()
      }
      if schema.unique_items && json_array_has_duplicates(values) {
        issues.push(
          error(
            "payload.array.unique_items", path, "array items must be unique",
          ),
        )
      }
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
      match schema.exclusive_minimum {
        Some(minimum) =>
          if number <= minimum {
            issues.push(
              error(
                "payload.number.exclusive_minimum", path, "number must be greater than exclusiveMinimum",
              ),
            )
          }
        None => ()
      }
      match schema.exclusive_maximum {
        Some(maximum) =>
          if number >= maximum {
            issues.push(
              error(
                "payload.number.exclusive_maximum", path, "number must be less than exclusiveMaximum",
              ),
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
fn json_is_integer(value : Json) -> Bool {
  match value {
    Number(number, repr~) =>
      match repr {
        Some(text) =>
          if text.contains(".") {
            number == number.floor()
          } else {
            true
          }
        None => number == number.floor()
      }
    _ => false
  }
}

///|
fn json_array_has_duplicates(values : Array[Json]) -> Bool {
  for index, value in values {
    let mut other = index + 1
    while other < values.length() {
      if value == values[other] {
        return true
      }
      other += 1
    }
  }
  false
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
fn contains_json(items : Array[Json], value : Json) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

///|
fn compare_schema_compatibility(
  before : Schema,
  after : Schema,
  path : String,
  issues : Array[Diagnostic],
) -> Unit {
  if before.kind != after.kind {
    issues.push(
      error("compat.schema.type.changed", path + ".type", "schema type changed"),
    )
  }
  compare_lower_bound(
    before.minimum,
    after.minimum,
    path + ".minimum",
    "compat.schema.minimum.tightened",
    issues,
  )
  compare_upper_bound(
    before.maximum,
    after.maximum,
    path + ".maximum",
    "compat.schema.maximum.tightened",
    issues,
  )
  compare_lower_bound(
    before.exclusive_minimum,
    after.exclusive_minimum,
    path + ".exclusiveMinimum",
    "compat.schema.exclusive_minimum.tightened",
    issues,
  )
  compare_upper_bound(
    before.exclusive_maximum,
    after.exclusive_maximum,
    path + ".exclusiveMaximum",
    "compat.schema.exclusive_maximum.tightened",
    issues,
  )
  compare_lower_bound(
    before.min_length,
    after.min_length,
    path + ".minLength",
    "compat.schema.min_length.tightened",
    issues,
  )
  compare_upper_bound(
    before.max_length,
    after.max_length,
    path + ".maxLength",
    "compat.schema.max_length.tightened",
    issues,
  )
  compare_lower_bound(
    before.min_items,
    after.min_items,
    path + ".minItems",
    "compat.schema.min_items.tightened",
    issues,
  )
  compare_upper_bound(
    before.max_items,
    after.max_items,
    path + ".maxItems",
    "compat.schema.max_items.tightened",
    issues,
  )
  compare_lower_bound(
    before.min_properties,
    after.min_properties,
    path + ".minProperties",
    "compat.schema.min_properties.tightened",
    issues,
  )
  compare_upper_bound(
    before.max_properties,
    after.max_properties,
    path + ".maxProperties",
    "compat.schema.max_properties.tightened",
    issues,
  )
  if !before.unique_items && after.unique_items {
    issues.push(
      error(
        "compat.schema.unique_items.enabled",
        path + ".uniqueItems",
        "uniqueItems was enabled",
      ),
    )
  }
  for old_value in before.enum_json_values {
    if after.enum_json_values.length() > 0 &&
      !contains_json(after.enum_json_values, old_value) {
      issues.push(
        error(
          "compat.schema.enum.value.removed",
          path + ".enum",
          "an enum value was removed",
        ),
      )
    }
  }
  match after.const_value {
    Some(new_value) =>
      match before.const_value {
        Some(old_value) =>
          if old_value != new_value {
            issues.push(
              error(
                "compat.schema.const.changed",
                path + ".const",
                "const value changed",
              ),
            )
          }
        None =>
          issues.push(
            error(
              "compat.schema.const.added",
              path + ".const",
              "const constraint was introduced",
            ),
          )
      }
    None => ()
  }
  if before.default_value != after.default_value {
    issues.push(
      info(
        "compat.schema.default.changed",
        path + ".default",
        "schema default changed",
      ),
    )
  }
  for required_name in after.required {
    if !contains_string(before.required, required_name) {
      issues.push(
        error(
          "compat.schema.required.added",
          path + ".required",
          "required field was added: " + required_name,
        ),
      )
    }
  }
  for name, _ in before.properties {
    if after.properties.get(name) is None {
      issues.push(
        error(
          "compat.schema.property.removed",
          path + ".properties." + name,
          "schema property was removed",
        ),
      )
    }
  }
  for name, new_property in after.properties {
    match before.properties.get(name) {
      None =>
        issues.push(
          info(
            "compat.schema.property.added",
            path + ".properties." + name,
            "schema property was added",
          ),
        )
      Some(old_property) =>
        compare_schema_compatibility(
          old_property,
          new_property,
          path + ".properties." + name,
          issues,
        )
    }
  }
  match before.items {
    Some(old_items) =>
      match after.items {
        Some(new_items) =>
          compare_schema_compatibility(
            old_items,
            new_items,
            path + ".items",
            issues,
          )
        None =>
          issues.push(
            error(
              "compat.schema.items.removed",
              path + ".items",
              "array item schema was removed",
            ),
          )
      }
    None =>
      match after.items {
        Some(_) =>
          issues.push(
            info(
              "compat.schema.items.added",
              path + ".items",
              "array item schema was added",
            ),
          )
        None => ()
      }
  }
}

///|
fn compare_lower_bound(
  before : Double?,
  after : Double?,
  path : String,
  code : String,
  issues : Array[Diagnostic],
) -> Unit {
  match after {
    Some(new_value) =>
      match before {
        Some(old_value) =>
          if new_value > old_value {
            issues.push(
              error(code, path, "lower bound became more restrictive"),
            )
          }
        None => issues.push(error(code, path, "a lower bound was introduced"))
      }
    None => ()
  }
}

///|
fn compare_upper_bound(
  before : Double?,
  after : Double?,
  path : String,
  code : String,
  issues : Array[Diagnostic],
) -> Unit {
  match after {
    Some(new_value) =>
      match before {
        Some(old_value) =>
          if new_value < old_value {
            issues.push(
              error(code, path, "upper bound became more restrictive"),
            )
          }
        None => issues.push(error(code, path, "an upper bound was introduced"))
      }
    None => ()
  }
}

///|
fn find_operation_in(
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
fn optional_string_field(object : Map[String, Json], name : String) -> String? {
  match object.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn bool_field(
  object : Map[String, Json],
  name : String,
  fallback : Bool,
) -> Bool {
  match object.get(name) {
    Some(True) => true
    Some(False) => false
    _ => fallback
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
