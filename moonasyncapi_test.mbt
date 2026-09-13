///|
test "parse and validate a minimal AsyncAPI document" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Temperature API\"},\"channels\":{\"temperature\":{\"address\":\"devices/{id}/temperature\",\"parameters\":{\"id\":{}},\"messages\":{\"reported\":{\"payload\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}}}}}}}}",
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
test "warns when operation protocol disagrees with channel binding" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Protocols\"},\"channels\":{\"events\":{\"address\":\"events\",\"bindings\":{\"mqtt\":{}}}},\"operations\":{\"receive\":{\"action\":\"receive\",\"channel\":\"events\",\"protocol\":\"kafka\"}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="operation.protocol.mismatch")
  inspect(issues[1].code, content="operation.messages.empty")
}

///|
test "warns about duplicate operation messages" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Duplicates\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"string\"}}}}},\"operations\":{\"receive\":{\"action\":\"receive\",\"channel\":\"events\",\"messages\":[\"created\",\"created\"]}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="operation.messages.duplicate")
}

///|
test "exposes parsed contract lookup APIs" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Lookup\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"string\"}}}}},\"operations\":{\"receive\":{\"action\":\"receive\",\"channel\":\"events\",\"messages\":[\"created\"]}},\"components\":{\"schemas\":{\"Id\":{\"type\":\"string\"}},\"messages\":{\"Shared\":{\"payload\":{\"type\":\"string\"}}}}}",
  ).unwrap()
  inspect(find_channel(document, "events") is Some(_), content="true")
  inspect(find_channel(document, "missing") is None, content="true")
  inspect(find_schema(document, "Id") is Some(_), content="true")
  inspect(find_message(document, "Shared") is Some(_), content="true")
  inspect(find_operation(document, "receive") is Some(_), content="true")
  inspect(
    document_summary(document),
    content="AsyncAPI 3.0.0: 1 channels, 1 operations, 1 messages, 1 schemas, 0 servers, 0 security schemes",
  )
}

///|
test "diagnoses malformed channel address templates" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Addresses\"},\"channels\":{\"broken\":{\"address\":\"devices/{id\"},\"empty\":{\"address\":\"devices/{}\"}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="channel.address.template.unbalanced")
  inspect(issues[1].code, content="channel.address.template.empty")
}

///|
test "diagnoses duplicate and empty required fields" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Required fields\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\",\"id\",\"\"],\"properties\":{\"id\":{\"type\":\"string\"}}}}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="3")
  inspect(issues[0].code, content="schema.required.duplicate")
  inspect(issues[1].code, content="schema.required.empty")
  inspect(issues[2].code, content="schema.required.unknown")
}

///|
test "rejects negative string length constraints" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Lengths\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"string\",\"minLength\":-1,\"maxLength\":-2}}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="3")
  inspect(issues[0].code, content="schema.length.negative")
  inspect(issues[1].code, content="schema.length.negative")
  inspect(issues[2].code, content="schema.length.invalid")
}

///|
test "validates array size and uniqueness constraints" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Batches\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"batch\":{\"payload\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":3,\"uniqueItems\":true,\"items\":{\"type\":\"integer\"}}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("batch")
    .unwrap()
  inspect(validate_payload(message, @json.parse("[1]")).length(), content="1")
  inspect(validate_payload(message, @json.parse("[1,1]")).length(), content="1")
  inspect(
    validate_payload(message, @json.parse("[1,2,3,4]")).length(),
    content="1",
  )
  inspect(
    validate_payload(message, @json.parse("[1,2,3]")).length(),
    content="0",
  )
}

///|
test "validates object property count constraints" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Objects\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"minProperties\":1,\"maxProperties\":2}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("event")
    .unwrap()
  inspect(validate_payload(message, @json.parse("{}")).length(), content="1")
  inspect(
    validate_payload(message, @json.parse("{\"a\":1}")).length(),
    content="0",
  )
  inspect(
    validate_payload(message, @json.parse("{\"a\":1,\"b\":2,\"c\":3}")).length(),
    content="1",
  )
}

///|
test "integer schemas reject fractional numbers" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Integers\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"integer\"}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("event")
    .unwrap()
  inspect(validate_payload(message, @json.parse("42")).length(), content="0")
  inspect(validate_payload(message, @json.parse("1.5")).length(), content="1")
}

///|
test "validates exclusive numeric bounds" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Scores\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"score\":{\"payload\":{\"type\":\"number\",\"exclusiveMinimum\":0,\"exclusiveMaximum\":10}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("score")
    .unwrap()
  inspect(validate_payload(message, @json.parse("0")).length(), content="1")
  inspect(validate_payload(message, @json.parse("5")).length(), content="0")
  inspect(validate_payload(message, @json.parse("10")).length(), content="1")
}

///|
test "diagnoses invalid exclusive numeric ranges" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Ranges\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"score\":{\"payload\":{\"type\":\"number\",\"exclusiveMinimum\":10,\"exclusiveMaximum\":10}}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="schema.exclusive_range.invalid")
}

///|
test "reports tightened schema constraints" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{},\"components\":{\"schemas\":{\"Batch\":{\"type\":\"array\",\"maxItems\":10,\"uniqueItems\":false,\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{},\"components\":{\"schemas\":{\"Batch\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":5,\"uniqueItems\":true,\"items\":{\"type\":\"string\",\"enum\":[\"a\"]}}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="4")
  inspect(issues[0].code, content="compat.schema.min_items.tightened")
  inspect(issues[1].code, content="compat.schema.max_items.tightened")
  inspect(issues[2].code, content="compat.schema.unique_items.enabled")
  inspect(issues[3].code, content="compat.schema.enum.value.removed")
}

///|
test "validates reusable component messages" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Components\"},\"channels\":{\"events\":{\"address\":\"events\"}},\"components\":{\"messages\":{\"Invalid\":{\"contentType\":\"json\"}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="message.content_type.invalid")
  inspect(issues[1].code, content="message.payload.missing")
}

///|
test "parses and validates channel parameters" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Devices\"},\"channels\":{\"events\":{\"address\":\"devices/{region}/{id}\",\"parameters\":{\"region\":{\"description\":\"Region\",\"enum\":[\"eu\",\"us\"],\"default\":\"eu\"},\"id\":{\"location\":\"$message.header#/id\"}}}}}",
  ).unwrap()
  let channel = find_channel(document, "events").unwrap()
  let parameters = address_parameters(channel.address)
  inspect(parameters.length(), content="2")
  inspect(parameters[0], content="region")
  inspect(parameters[1], content="id")
  inspect(
    find_channel_parameter(channel, "region").unwrap().default_value.unwrap(),
    content="eu",
  )
  inspect(validate(document).length(), content="0")
}

///|
test "diagnoses inconsistent channel parameter declarations" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Devices\"},\"channels\":{\"events\":{\"address\":\"devices/{region}/{region}/{id}\",\"parameters\":{\"region\":{\"enum\":[\"eu\",\"eu\"],\"default\":\"apac\"},\"unused\":{}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="5")
  inspect(issues[0].code, content="channel.parameter.duplicate")
  inspect(issues[1].code, content="channel.parameter.missing")
  inspect(issues[2].code, content="channel.parameter.enum.duplicate")
  inspect(issues[3].code, content="channel.parameter.default.invalid")
  inspect(issues[4].code, content="channel.parameter.unused")
}

///|
test "reports channel parameter compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{\"events\":{\"address\":\"events\",\"parameters\":{\"region\":{\"enum\":[\"eu\",\"us\"]},\"id\":{}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{\"events\":{\"address\":\"events\",\"parameters\":{\"region\":{\"enum\":[\"eu\"]},\"tenant\":{}}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="3")
  inspect(issues[0].code, content="compat.channel.parameter.enum.removed")
  inspect(issues[1].code, content="compat.channel.parameter.removed")
  inspect(issues[2].code, content="compat.channel.parameter.added")
}

///|
test "renders channel addresses with explicit and default parameters" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Devices\"},\"channels\":{\"events\":{\"address\":\"devices/{region}/{id}/events\",\"parameters\":{\"region\":{\"enum\":[\"eu\",\"us\"],\"default\":\"eu\"},\"id\":{}}}}}",
  ).unwrap()
  let channel = find_channel(document, "events").unwrap()
  inspect(
    render_channel_address(channel, Map([("id", "42")])).unwrap(),
    content="devices/eu/42/events",
  )
  inspect(
    render_channel_address(channel, Map([("region", "us"), ("id", "7")])).unwrap(),
    content="devices/us/7/events",
  )
}

///|
test "rejects missing and invalid channel parameter values" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Devices\"},\"channels\":{\"events\":{\"address\":\"devices/{region}/{id}\",\"parameters\":{\"region\":{\"enum\":[\"eu\",\"us\"]},\"id\":{}}}}}",
  ).unwrap()
  let channel = find_channel(document, "events").unwrap()
  inspect(
    render_channel_address(channel, Map([])).unwrap_err(),
    content="missing channel parameter value: region",
  )
  inspect(
    render_channel_address(channel, Map([("region", "apac"), ("id", "7")])).unwrap_err(),
    content="channel parameter value is outside enum: region",
  )
}

///|
test "reports channel message payload compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"title\":\"Created\",\"contentType\":\"application/json\",\"payload\":{\"type\":\"string\",\"maxLength\":20}}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"title\":\"Created event\",\"contentType\":\"text/plain\",\"payload\":{\"type\":\"string\",\"maxLength\":10}}}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="3")
  inspect(issues[0].code, content="compat.message.content_type.changed")
  inspect(issues[1].code, content="compat.message.title.changed")
  inspect(issues[2].code, content="compat.schema.max_length.tightened")
}

///|
test "reports reusable component message additions and removals" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{},\"components\":{\"messages\":{\"Old\":{\"payload\":{\"type\":\"string\"}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{},\"components\":{\"messages\":{\"New\":{\"payload\":{\"type\":\"string\"}}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="compat.component_message.removed")
  inspect(issues[1].code, content="compat.component_message.added")
}

///|
test "parses and validates AsyncAPI servers" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Servers\"},\"servers\":{\"production\":{\"host\":\"broker.example.com:8883\",\"protocol\":\"mqtts\",\"protocolVersion\":\"5.0\",\"pathname\":\"/mqtt\",\"description\":\"Production broker\"}},\"channels\":{}}",
  ).unwrap()
  let server = find_server(document, "production").unwrap()
  inspect(server.host, content="broker.example.com:8883")
  inspect(server.protocol, content="mqtts")
  inspect(validate(document).length(), content="1")
  inspect(validate(document)[0].code, content="channels.empty")
}

///|
test "diagnoses malformed AsyncAPI servers" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Servers\"},\"servers\":{\"missing\":{},\"custom\":{\"host\":\"https://example.com\",\"protocol\":\"custom\",\"protocolVersion\":\"\",\"pathname\":\"events\"}},\"channels\":{}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="7")
  inspect(diagnostics_by_severity(issues, "error").length(), content="2")
  inspect(diagnostics_by_severity(issues, "warning").length(), content="5")
}

///|
test "reports server compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"servers\":{\"production\":{\"host\":\"old.example.com\",\"protocol\":\"mqtt\",\"pathname\":\"/mqtt\"},\"legacy\":{\"host\":\"legacy.example.com\",\"protocol\":\"mqtt\"}},\"channels\":{}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"servers\":{\"production\":{\"host\":\"new.example.com\",\"protocol\":\"mqtts\",\"pathname\":\"/events\"},\"staging\":{\"host\":\"staging.example.com\",\"protocol\":\"mqtt\"}},\"channels\":{}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="5")
  inspect(issues[0].code, content="compat.server.host.changed")
  inspect(issues[1].code, content="compat.server.protocol.changed")
  inspect(issues[2].code, content="compat.server.pathname.changed")
  inspect(issues[3].code, content="compat.server.removed")
  inspect(issues[4].code, content="compat.server.added")
}

///|
test "validates boolean number and null enum values" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Enums\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"enum\":[true,42,null]}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("event")
    .unwrap()
  inspect(validate_payload(message, @json.parse("true")).length(), content="0")
  inspect(validate_payload(message, @json.parse("42")).length(), content="0")
  inspect(validate_payload(message, @json.parse("null")).length(), content="0")
  inspect(validate_payload(message, @json.parse("false")).length(), content="1")
}

///|
test "validates const payload values" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Const\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"string\",\"const\":\"created\"}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("event")
    .unwrap()
  inspect(
    validate_payload(message, @json.parse("\"created\"")).length(),
    content="0",
  )
  inspect(
    validate_payload(message, @json.parse("\"deleted\"")).length(),
    content="1",
  )
}

///|
test "reports enum and const compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{},\"components\":{\"schemas\":{\"Flag\":{\"enum\":[true,false]}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{},\"components\":{\"schemas\":{\"Flag\":{\"enum\":[true],\"const\":true}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="compat.schema.enum.value.removed")
  inspect(issues[1].code, content="compat.schema.const.added")
}

///|
test "validates schema defaults and examples" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Examples\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"integer\",\"minimum\":0,\"default\":-1,\"examples\":[0,2,-3]}}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="schema.default.invalid")
  inspect(issues[1].code, content="schema.example.invalid")
}

///|
test "reports schema default changes as informational" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{},\"components\":{\"schemas\":{\"Limit\":{\"type\":\"integer\",\"default\":10}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{},\"components\":{\"schemas\":{\"Limit\":{\"type\":\"integer\",\"default\":20}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="compat.schema.default.changed")
}

///|
test "parses and validates message headers and correlation ids" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Headers\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"headers\":{\"type\":\"object\",\"required\":[\"trace-id\"],\"properties\":{\"trace-id\":{\"type\":\"string\"}}},\"correlationId\":{\"location\":\"$message.header#/trace-id\"},\"payload\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("event")
    .unwrap()
  inspect(validate(document).length(), content="0")
  inspect(validate_headers(message, @json.parse("{}")).length(), content="1")
  inspect(
    validate_headers(message, @json.parse("{\"trace-id\":\"abc\"}")).length(),
    content="0",
  )
}

///|
test "reports absent message header schemas" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Headers\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let message = find_channel(document, "events").unwrap().messages
    .get("event")
    .unwrap()
  let issues = validate_headers(message, @json.parse("{}"))
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="message.headers.missing")
}

///|
test "reports message header compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"headers\":{\"type\":\"object\",\"properties\":{\"trace\":{\"type\":\"string\"}}},\"correlationId\":{\"location\":\"$message.header#/trace\"},\"payload\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"headers\":{\"type\":\"object\",\"required\":[\"trace\"],\"properties\":{\"trace\":{\"type\":\"string\"}}},\"correlationId\":{\"location\":\"$message.payload#/trace\"},\"payload\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="compat.message.correlation_id.changed")
  inspect(issues[1].code, content="compat.schema.required.added")
}

///|
test "parses validates and renders server variables" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Variables\"},\"servers\":{\"production\":{\"host\":\"{region}.broker.example.com\",\"protocol\":\"mqtts\",\"pathname\":\"/{tenant}/mqtt\",\"variables\":{\"region\":{\"default\":\"eu\",\"enum\":[\"eu\",\"us\"]},\"tenant\":{\"default\":\"public\"}}}},\"channels\":{}}",
  ).unwrap()
  let server = find_server(document, "production").unwrap()
  inspect(find_server_variable(server, "region") is Some(_), content="true")
  inspect(
    render_server_endpoint(server, Map([])).unwrap(),
    content="mqtts://eu.broker.example.com/public/mqtt",
  )
  inspect(
    render_server_endpoint(server, Map([("region", "us"), ("tenant", "acme")])).unwrap(),
    content="mqtts://us.broker.example.com/acme/mqtt",
  )
  inspect(validate(document).length(), content="1")
}

///|
test "diagnoses malformed server variable declarations" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Variables\"},\"servers\":{\"production\":{\"host\":\"{region}.example.com\",\"protocol\":\"mqtt\",\"variables\":{\"unused\":{},\"region\":{\"default\":\"apac\",\"enum\":[\"eu\",\"eu\"]}}}},\"channels\":{}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="5")
  inspect(diagnostics_by_severity(issues, "error").length(), content="1")
  inspect(diagnostics_by_severity(issues, "warning").length(), content="4")
}

///|
test "reports server variable compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"servers\":{\"production\":{\"host\":\"example.com\",\"protocol\":\"mqtt\",\"variables\":{\"region\":{\"default\":\"eu\",\"enum\":[\"eu\",\"us\"]},\"tenant\":{\"default\":\"public\"}}}},\"channels\":{}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"servers\":{\"production\":{\"host\":\"example.com\",\"protocol\":\"mqtt\",\"variables\":{\"region\":{\"default\":\"us\",\"enum\":[\"eu\"]},\"stage\":{\"default\":\"prod\"}}}},\"channels\":{}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="4")
  inspect(issues[0].code, content="compat.server.variable.enum.removed")
  inspect(issues[1].code, content="compat.server.variable.default.changed")
  inspect(issues[2].code, content="compat.server.variable.removed")
  inspect(issues[3].code, content="compat.server.variable.added")
}

///|
test "parses and validates descriptive security schemes" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Security\"},\"servers\":{\"production\":{\"host\":\"broker.example.com\",\"protocol\":\"mqtts\",\"security\":[{\"apiKey\":[]}] }},\"components\":{\"securitySchemes\":{\"apiKey\":{\"type\":\"apiKey\",\"in\":\"header\",\"description\":\"API token\"},\"bearer\":{\"type\":\"http\",\"scheme\":\"bearer\"}}},\"channels\":{}}",
  ).unwrap()
  inspect(find_security_scheme(document, "apiKey") is Some(_), content="true")
  inspect(
    find_server(document, "production").unwrap().security_requirements.length(),
    content="1",
  )
  inspect(validate(document).length(), content="1")
  inspect(validate(document)[0].code, content="channels.empty")
}

///|
test "diagnoses invalid security scheme declarations" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Security\"},\"components\":{\"securitySchemes\":{\"missing\":{},\"badKey\":{\"type\":\"apiKey\",\"in\":\"path\"},\"badHttp\":{\"type\":\"http\"}}},\"channels\":{}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="4")
  inspect(diagnostics_by_severity(issues, "error").length(), content="3")
  inspect(diagnostics_by_severity(issues, "warning").length(), content="1")
}

///|
test "reports server security requirement changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"servers\":{\"production\":{\"host\":\"example.com\",\"protocol\":\"mqtt\",\"security\":[{\"apiKey\":[]}] }},\"components\":{\"securitySchemes\":{\"apiKey\":{\"type\":\"apiKey\",\"in\":\"header\"}}},\"channels\":{}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"servers\":{\"production\":{\"host\":\"example.com\",\"protocol\":\"mqtt\",\"security\":[]}},\"components\":{\"securitySchemes\":{\"apiKey\":{\"type\":\"apiKey\",\"in\":\"header\"}}},\"channels\":{}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="compat.server.security.changed")
}

///|
test "validates operation payloads as independent reports" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Operations\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"integer\"}}}},\"deleted\":{\"payload\":{\"type\":\"string\"}}}}},\"operations\":{\"create\":{\"action\":\"send\",\"channel\":\"events\",\"messages\":[\"created\"]},\"remove\":{\"action\":\"send\",\"channel\":\"events\",\"messages\":[\"deleted\"]}}}",
  ).unwrap()
  let reports = validate_operations(
    document,
    Map([("create", @json.parse("{\"id\":\"wrong\"}"))]),
  )
  inspect(reports.length(), content="2")
  inspect(reports[0].operation_name, content="create")
  inspect(reports[0].message_count, content="1")
  inspect(reports[0].diagnostics.length(), content="1")
  inspect(reports[1].diagnostics.length(), content="1")
  inspect(operation_report_diagnostics(reports).length(), content="2")
}

///|
test "returns clean operation report for valid payload" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Operations\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"string\"}}}}},\"operations\":{\"receive\":{\"action\":\"receive\",\"channel\":\"events\",\"messages\":[\"created\"]}}}",
  ).unwrap()
  let reports = validate_operations(
    document,
    Map([("receive", @json.parse("\"ok\""))]),
  )
  inspect(reports[0].diagnostics.length(), content="0")
  inspect(
    highest_severity(operation_report_diagnostics(reports)),
    content="none",
  )
}

///|
test "summarizes and filters diagnostics for CI consumers" {
  let document = parse(
    "{\"asyncapi\":\"2.6.0\",\"info\":{\"title\":\"Diagnostics\"},\"channels\":{\"events\":{\"address\":\"events\",\"bindings\":{\"custom\":{}}}}}",
  ).unwrap()
  let issues = validate(document)
  let summary = summarize_diagnostics(issues)
  inspect(summary.errors, content="1")
  inspect(summary.warnings, content="1")
  inspect(summary.infos, content="0")
  inspect(summary.total, content="2")
  inspect(diagnostics_by_severity(issues, "error").length(), content="1")
  inspect(highest_severity(issues), content="error")
  inspect(diagnostics_exit_code(issues), content="1")
}

///|
test "supports strict warning exit codes" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Warnings\"},\"channels\":{\"events\":{\"address\":\"events\",\"bindings\":{\"custom\":{}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(highest_severity(issues), content="warning")
  inspect(diagnostics_exit_code(issues), content="0")
  inspect(diagnostics_exit_code(issues, warnings_as_errors=true), content="1")
  inspect(highest_severity([]), content="none")
}

///|
test "validates a message payload against its schema" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Payloads\"},\"channels\":{\"events\":{\"address\":\"events\",\"bindings\":{\"mqtt\":{}},\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}}}}}}",
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
test "validates string length constraints" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Names\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"string\",\"minLength\":3,\"maxLength\":5}}}}}}",
  ).unwrap()
  let message = document.channels.get("events").unwrap().messages
    .get("event")
    .unwrap()
  inspect(
    validate_payload(message, @json.parse("\"hi\"")).length(),
    content="1",
  )
  inspect(
    validate_payload(message, @json.parse("\"hello\"")).length(),
    content="0",
  )
  inspect(
    validate_payload(message, @json.parse("\"toolong\"")).length(),
    content="1",
  )
}

///|
test "diagnoses unsupported schema keywords" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Boundaries\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"string\",\"pattern\":\"^[a-z]+$\",\"format\":\"email\"}}}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="schema.keyword.unsupported")
  inspect(issues[1].code, content="schema.keyword.unsupported")
}

///|
test "reports breaking schema compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{},\"components\":{\"schemas\":{\"Event\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{},\"components\":{\"schemas\":{\"Event\":{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"number\"},\"name\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="3")
  inspect(issues[0].code, content="compat.schema.required.added")
  inspect(issues[1].code, content="compat.schema.type.changed")
  inspect(issues[2].code, content="compat.schema.property.added")
}

///|
test "reports operation message compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Before\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"string\"}},\"deleted\":{\"payload\":{\"type\":\"string\"}}}}},\"operations\":{\"events\":{\"action\":\"receive\",\"channel\":\"events\",\"messages\":[\"created\"]}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"After\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"string\"}},\"deleted\":{\"payload\":{\"type\":\"string\"}}}}},\"operations\":{\"events\":{\"action\":\"receive\",\"channel\":\"events\",\"messages\":[\"deleted\"]}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="compat.operation.message.removed")
  inspect(issues[1].code, content="compat.operation.message.added")
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
test "resolves nested schema references in object properties" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Nested\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"properties\":{\"user\":{\"$ref\":\"#/components/schemas/User\"}}}}}}},\"components\":{\"schemas\":{\"User\":{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"string\"}}}}}}",
  ).unwrap()
  let message = document.channels.get("events").unwrap().messages
    .get("event")
    .unwrap()
  let issues = validate_payload(message, @json.parse("{\"user\":{}}"))
  inspect(issues.length(), content="1")
  inspect(issues[0].path, content="$.payload.user.id")
}

///|
test "diagnoses invalid component schema definitions" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Invalid schema\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"$ref\":\"#/components/schemas/Bad\"}}}}},\"components\":{\"schemas\":{\"Bad\":{\"type\":\"date\",\"minimum\":10,\"maximum\":1}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="schema.type.unsupported")
  inspect(issues[1].code, content="schema.range.invalid")
}

///|
test "diagnoses unresolved nested payload references" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Broken nested ref\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"properties\":{\"meta\":{\"$ref\":\"#/components/schemas/Missing\"}}}}}}}}",
  ).unwrap()
  let message = document.channels.get("events").unwrap().messages
    .get("event")
    .unwrap()
  let issues = validate_payload(message, @json.parse("{\"meta\":{}}"))
  inspect(issues.length(), content="1")
  inspect(issues[0].code, content="schema.ref.missing")
}

///|
test "validates payloads through an operation" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Operation payloads\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"created\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\"]}}}}},\"operations\":{\"consume\":{\"action\":\"receive\",\"channel\":{\"$ref\":\"#/channels/events\"},\"messages\":[\"created\"]}}}",
  ).unwrap()
  let issues = validate_operation_payload(
    document,
    "consume",
    @json.parse("{}"),
  )
  inspect(diagnostics_has_errors(issues), content="true")
  inspect(diagnostics_count(issues, "error"), content="1")
  let valid = validate_operation_payload(
    document,
    "consume",
    @json.parse("{\"id\":\"1\"}"),
  )
  inspect(diagnostics_has_errors(valid), content="false")
}

///|
test "diagnoses incomplete object and array schemas" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Incomplete schemas\"},\"channels\":{\"events\":{\"address\":\"events\",\"messages\":{\"event\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\"]}}}}},\"components\":{\"schemas\":{\"Items\":{\"type\":\"array\"}}}}",
  ).unwrap()
  let issues = validate(document)
  inspect(issues.length(), content="2")
  inspect(issues[0].code, content="schema.required.unknown")
  inspect(issues[1].code, content="schema.items.missing")
}

///|
test "accepts an operation that references a component message" {
  let document = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Orders\"},\"channels\":{\"orders\":{\"address\":\"orders\"}},\"operations\":{\"receiveOrders\":{\"action\":\"receive\",\"channel\":{\"$ref\":\"#/channels/orders\"},\"messages\":[{\"$ref\":\"#/components/messages/OrderCreated\"}]}},\"components\":{\"messages\":{\"OrderCreated\":{\"payload\":{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"string\"}}}}}}}",
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
test "reports channel and operation compatibility changes" {
  let before = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"API\"},\"channels\":{\"orders\":{\"address\":\"orders\",\"bindings\":{\"mqtt\":{}},\"messages\":{\"created\":{}}}},\"operations\":{\"consume\":{\"action\":\"receive\",\"channel\":{\"$ref\":\"#/channels/orders\"}}}}",
  ).unwrap()
  let after = parse(
    "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"API\"},\"channels\":{\"orders\":{\"address\":\"archive/orders\",\"bindings\":{\"kafka\":{}},\"messages\":{\"created\":{},\"updated\":{}}}},\"operations\":{\"consume\":{\"action\":\"send\",\"channel\":{\"$ref\":\"#/channels/orders\"}},\"publish\":{\"action\":\"send\",\"channel\":{\"$ref\":\"#/channels/orders\"}}}}",
  ).unwrap()
  let issues = diff(before, after)
  inspect(issues.length(), content="5")
  inspect(issues[0].code, content="compat.channel.address.changed")
  inspect(issues[1].code, content="compat.channel.binding.changed")
  inspect(issues[2].code, content="compat.message.added")
  inspect(issues[3].code, content="compat.operation.action.changed")
  inspect(issues[4].code, content="compat.operation.added")
}

///|
test "rejects malformed root" {
  match parse("[]") {
    Ok(_) => fail("array must not be accepted as a document")
    Err(message) => inspect(message, content="document must be a JSON object")
  }
}
