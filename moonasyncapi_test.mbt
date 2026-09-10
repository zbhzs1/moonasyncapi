///|
test "parse and validate a minimal AsyncAPI document" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Temperature API\"},\"channels\":{\"temperature\":{\"address\":\"devices/{id}/temperature\",\"messages\":{\"reported\":{}}}}}",
  ).unwrap()
  inspect(document.version, content="3.0.0")
  inspect(document.channels.length(), content="1")
  inspect(validate(document).length(), content="0")
}

///|
test "reports removed channels" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"API\"},\"channels\":{\"orders\":{\"address\":\"orders\",\"messages\":{\"created\":{}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"API\"},\"channels\":{}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="compat.channel.removed")
}

///|
test "rejects malformed root" {
  match parse("[]") {
    Ok(_) => fail("array must not be accepted as a document")
    Err(message) => inspect(message, content="document must be a JSON object")
  }
}
