///|
test "parse and validate a minimal AsyncAPI document" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Temperature API\"},\"channels\":{\"temperature\":{\"address\":\"devices/{id}/temperature\",\"messages\":{\"reported\":{\"payload\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}}}}}}}}",
  ).unwrap()
  inspect(document.version, content="3.0.0")
  inspect(document.channels.length(), content="1")
  inspect(validate(document).length(), content="0")
}

///|
test "parses operations and local schema references" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Orders\"},\"channels\":{\"orders\":{\"address\":\"orders\",\"messages\":{\"created\":{\"payload\":{\"$ref\":\"#/components/schemas/Order\"}}}}},\"operations\":{\"consumeOrders\":{\"action\":\"receive\",\"channel\":{\"$ref\":\"#/channels/orders\"},\"messages\":[{\"$ref\":\"#/channels/orders/messages/created\"}]}},\"components\":{\"schemas\":{\"Order\":{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  inspect(document.operations.length(), content="1")
  inspect(document.operations[0].channel, content="orders")
  inspect(document.operations[0].action, content="receive")
  inspect(document.schemas.get("Order") is Some(_), content="true")
  inspect(validate(document).length(), content="0")
}

///|
test "reports invalid operation references" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Broken\"},\"channels\":{\"events\":{\"address\":\"events\"}},\"operations\":{\"publish\":{\"action\":\"send\",\"channel\":{\"$ref\":\"#/channels/events\"},\"messages\":[\"unknown\"]}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues[0].code, content="operation.message.missing")
}

///|
test "validates a message payload against its schema" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Payloads\"},\"channels\":{\"events\":{\"address\":\"events\",\"bindings\":{\"mqtt\":{}},\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\"]}}}}}}",
  ).unwrap()
  let channel = document.channels.get("events").unwrap()
  let message = channel.messages.get("event").unwrap()
  inspect(validate_payload(message, @json.parse("{}")).length(), content="1")
  inspect(
    validate_payload(message, @json.parse("{\"id\":\"e1\"}")).length(),
    content="0",
  )
  inspect(validate(document).length(), content="0")
}

///|
test "reports payload type and enum violations" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Events\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"properties\":{\"kind\":{\"type\":\"string\",\"enum\":[\"created\",\"deleted\"]}}}}}}}}",
  ).unwrap()
  let message = document.channels.get("events").unwrap().messages
    .get("event")
    .unwrap()
  let issues = validate_payload(message, @json.parse("{\"kind\":false}"))
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="payload.type.mismatch")
  let enum_issues = validate_payload(
    message,
    @json.parse("{\"kind\":\"updated\"}"),
  )
  inspect(enum_issues.length(), content="1")
  inspect(enum_issues[0].code, content="payload.enum.invalid")
}

///|
test "reports unsupported bindings and invalid version" {
  let document = parse(
    "{\"asyncapi\":\"2.6.0\",\"info\":{\"title\":\"Legacy\"},\"channels\":{\"events\":{\"address\":\"events\",\"bindings\":{\"nats\":{}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="asyncapi.version.unsupported")
  inspect(issues[1].code, content="channel.binding.unsupported")
}

///|
test "detects added and removed component schemas" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"API\"},\"components\":{\"schemas\":{\"Old\":{\"type\":\"string\"}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"API\"},\"components\":{\"schemas\":{\"New\":{\"type\":\"string\"}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="compat.schema.removed")
  inspect(issues[1].code, content="compat.schema.added")
}

///|
test "reports an unresolved local schema reference" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Broken schema\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"$ref\":\"#/components/schemas/Missing\"}}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="schema.ref.missing")
}

///|
test "validates nested arrays and numeric bounds" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Measurements\"},\"channels\":{\"measurements\":{\"address\":\"measurements\",\"messages\":{\"batch\":{\"payload\":{\"type\":\"array\",\"items\":{\"type\":\"number\",\"minimum\":0,\"maximum\":100}}}}}}}",
  ).unwrap()
  let message = document.channels.get("measurements").unwrap().messages
    .get("batch")
    .unwrap()
  let issues = validate_payload(message, @json.parse("[12,101,-1]"))
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="payload.number.maximum")
  inspect(issues[1].code, content="payload.number.minimum")
}

///|
test "reports an array item type mismatch" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Tags\"},\"channels\":{\"tags\":{\"address\":\"tags\",\"messages\":{\"list\":{\"payload\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}}}}",
  ).unwrap()
  let message = document.channels.get("tags").unwrap().messages
    .get("list")
    .unwrap()
  let issues = validate_payload(message, @json.parse("[\"ok\",false]"))
  inspect(issues.length(), content="1")
  inspect(issues[0].path, content="$.payload[1]")
}

///|
test "accepts an operation that references a component message" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Orders\"},\"channels\":{\"orders\":{\"address\":\"orders\"}},\"operations\":{\"receiveOrders\":{\"action\":\"receive\",\"channel\":{\"$ref\":\"#/channels/orders\"},\"messages\":[{\"$ref\":\"#/components/messages/OrderCreated\"}]}},\"components\":{\"messages\":{\"OrderCreated\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\"]}}}}}",
  ).unwrap()
  inspect(document.messages.length(), content="1")
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
