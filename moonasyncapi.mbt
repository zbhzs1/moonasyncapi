///|
/// A small, typed core for the AsyncAPI 3 document model.
pub struct AsyncApiDocument {
  version : String
  title : String
  channels : Map[String, AsyncApiChannel]
} derive(Eq, Debug)

///|
/// A channel with the operations relevant to the first release.
pub struct AsyncApiChannel {
  address : String
  messages : Array[String]
  has_publish : Bool
  has_subscribe : Bool
} derive(Eq, Debug)

///|
/// A validation diagnostic with a stable JSON-like path.
pub struct Diagnostic {
  severity : String
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
/// Parse the core AsyncAPI 3 JSON shape.
pub fn parse(input : String) -> Result[AsyncApiDocument, String] {
  let value = @json.parse(input) catch {
    _ => return Err("invalid JSON".to_string())
  }
  parse_document(value)
}

///|
/// Validate a parsed document and return all issues.
pub fn validate(document : AsyncApiDocument) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  if document.version != "3.0.0" {
    issues.push({
      severity: "error",
      code: "asyncapi.version.unsupported",
      path: "$.asyncapi",
      message: "first release accepts AsyncAPI 3.0.0 documents",
    })
  }
  if document.title.length() == 0 {
    issues.push({
      severity: "error",
      code: "info.title.missing",
      path: "$.info.title",
      message: "info.title must not be empty",
    })
  }
  for name, channel in document.channels {
    let path = "$.channels." + name
    if channel.address.length() == 0 {
      issues.push({
        severity: "error",
        code: "channel.address.missing",
        path: path + ".address",
        message: "channel.address must not be empty",
      })
    }
    if !channel.has_publish && !channel.has_subscribe {
      issues.push({
        severity: "warning",
        code: "channel.operation.missing",
        path,
        message: "channel has neither publish nor subscribe operation",
      })
    }
  }
  issues
}

///|
/// Compare channel and message names between two documents.
pub fn diff(
  before : AsyncApiDocument,
  after : AsyncApiDocument,
) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  for name, old_channel in before.channels {
    match after.channels.get(name) {
      None =>
        issues.push({
          severity: "error",
          code: "compat.channel.removed",
          path: "$.channels." + name,
          message: "channel was removed",
        })
      Some(new_channel) =>
        for message in old_channel.messages {
          if !contains(new_channel.messages, message) {
            issues.push({
              severity: "error",
              code: "compat.message.removed",
              path: "$.channels." + name + ".messages",
              message: "message " + message + " was removed",
            })
          }
        }
    }
  }
  for name, _ in after.channels {
    if before.channels.get(name) is None {
      issues.push({
        severity: "info",
        code: "compat.channel.added",
        path: "$.channels." + name,
        message: "channel was added",
      })
    }
  }
  issues
}

///|
fn contains(items : Array[String], value : String) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

///|
fn parse_document(value : Json) -> Result[AsyncApiDocument, String] {
  let root = match value {
    Object(object) => object
    _ => return Err("document must be a JSON object".to_string())
  }
  let version = match root.get("asyncapi") {
    Some(String(value)) => value
    _ => return Err("$.asyncapi must be a string".to_string())
  }
  let info = match root.get("info") {
    Some(Object(value)) => value
    _ => return Err("$.info must be an object".to_string())
  }
  let title = match info.get("title") {
    Some(String(value)) => value
    _ => return Err("$.info.title must be a string".to_string())
  }
  let channels = match root.get("channels") {
    Some(Object(value)) => parse_channels(value)
    Some(_) => return Err("$.channels must be an object".to_string())
    None => Map([])
  }
  Ok({ version, title, channels })
}

///|
fn parse_channels(value : Map[String, Json]) -> Map[String, AsyncApiChannel] {
  let result : Map[String, AsyncApiChannel] = Map([])
  for name, raw in value {
    let channel = match raw {
      Object(object) => {
        let address = match object.get("address") {
          Some(String(value)) => value
          _ => ""
        }
        let messages : Array[String] = []
        match object.get("messages") {
          Some(Object(values)) =>
            for message_name, _ in values {
              messages.push(message_name)
            }
          _ => ()
        }
        {
          address,
          messages,
          has_publish: object.get("operations") is Some(_),
          has_subscribe: object.get("messages") is Some(_),
        }
      }
      _ =>
        { address: "", messages: [], has_publish: false, has_subscribe: false }
    }
    result[name] = channel
  }
  result
}
