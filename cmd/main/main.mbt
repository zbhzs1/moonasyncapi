///|
fn example_payload() -> Result[Json, String] {
  let payload = @json.parse("{\"value\":24.5}") catch {
    _ => return Err("invalid example payload")
  }
  Ok(payload)
}

///|
/// Runnable contract validation and payload compatibility demonstration.
fn main {
  let input = "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Temperature API\"},\"channels\":{\"temperature\":{\"address\":\"devices/{id}/temperature\",\"parameters\":{\"id\":{\"description\":\"Device identifier\"}},\"bindings\":{\"mqtt\":{}},\"messages\":{\"reported\":{\"payload\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}},\"required\":[\"value\"]}}}}}}"
  match @lib.parse(input) {
    Ok(document) => {
      println("AsyncAPI " + document.version + " is readable")
      let issues = @lib.validate(document)
      println("document diagnostics: " + @lib.diagnostics_to_text(issues))
      let channel = document.channels.get("temperature").unwrap()
      let message = channel.messages.get("reported").unwrap()
      match example_payload() {
        Ok(payload) => {
          let payload_issues = @lib.validate_payload(message, payload)
          println(
            "payload diagnostics: " + @lib.diagnostics_to_text(payload_issues),
          )
        }
        Err(error) => println("payload parse error: " + error)
      }
    }
    Err(message) => println("parse error: " + message)
  }
}
