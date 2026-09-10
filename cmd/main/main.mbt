///|
/// Minimal executable smoke test for the first library release.
fn main {
  let input = "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Example\"},\"channels\":{}}"
  match @lib.parse(input) {
    Ok(document) => println("AsyncAPI " + document.version + " is readable")
    Err(message) => println("parse error: " + message)
  }
}
