///|
fn codegen_fixture() -> String {
  "{\"asyncapi\":\"3.0.0\",\"info\":{\"title\":\"Order Events\"},\"channels\":{\"order-events\":{\"address\":\"orders/{tenant}\",\"bindings\":{\"kafka\":{}},\"messages\":{\"order-created\":{\"payload\":{\"$ref\":\"#/components/schemas/Order\"},\"headers\":{\"$ref\":\"#/components/schemas/TraceHeaders\"}}}}},\"operations\":{\"consume-orders\":{\"action\":\"receive\",\"channel\":{\"$ref\":\"#/channels/order-events\"},\"messages\":[{\"$ref\":\"#/channels/order-events/messages/order-created\"}]}},\"components\":{\"schemas\":{\"OrderStatus\":{\"type\":\"string\",\"enum\":[\"created\",\"in-progress\",\"done\"]},\"TraceHeaders\":{\"type\":\"object\",\"required\":[\"trace-id\"],\"properties\":{\"trace-id\":{\"type\":\"string\"}}},\"Order\":{\"type\":\"object\",\"required\":[\"id\",\"status\"],\"properties\":{\"id\":{\"type\":\"string\"},\"status\":{\"$ref\":\"#/components/schemas/OrderStatus\"},\"class\":{\"type\":\"string\"},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}}}}"
}

///|
test "normalizes type and value identifiers" {
  inspect(moonbit_type_name("order-created.v2"), content="OrderCreatedV2")
  inspect(moonbit_type_name("123-event"), content="T123Event")
  inspect(moonbit_value_name("trace-id"), content="traceId")
  inspect(moonbit_value_name("match"), content="matchValue")
  inspect(moonbit_value_name(""), content="generated")
}

///|
test "generates a deterministic multi-file MoonBit project" {
  let plan = generate_from_json(codegen_fixture()).unwrap()
  inspect(plan.schema_count, content="3")
  inspect(plan.message_count, content="1")
  inspect(plan.operation_count, content="1")
  inspect(plan.diagnostics.length(), content="0")
  inspect(plan.files.length(), content="8")
  inspect(find_generated_file(plan, "moon.mod") is Some(_), content="true")
  inspect(find_generated_file(plan, "src/types_order.mbt") is Some(_), content="true")
  inspect(find_generated_file(plan, "src/messages.mbt") is Some(_), content="true")
  inspect(find_generated_file(plan, "src/operations.mbt") is Some(_), content="true")
  inspect(find_generated_file(plan, "src/bindings.mbt") is Some(_), content="true")
}

///|
test "maps object fields, optional values, arrays and refs" {
  let plan = generate_from_json(codegen_fixture()).unwrap()
  let order = find_generated_file(plan, "src/types_order.mbt").unwrap().content
  assert_true(order.contains("pub(all) struct Order"))
  assert_true(order.contains("id : String"))
  assert_true(order.contains("status : OrderStatus"))
  assert_true(order.contains("classValue : String?"))
  assert_true(order.contains("tags : Array[String]?"))
  let status = find_generated_file(
    plan,
    "src/types_orderstatus.mbt",
  ).unwrap().content
  assert_true(status.contains("pub enum OrderStatus"))
  assert_true(status.contains("InProgress"))
}

///|
test "emits typed messages, operation ports and protocol bindings" {
  let plan = generate_from_json(codegen_fixture()).unwrap()
  let messages = find_generated_file(plan, "src/messages.mbt").unwrap().content
  assert_true(messages.contains("OrderEventsOrderCreatedMessage"))
  assert_true(messages.contains("payload : Order"))
  assert_true(messages.contains("headers : TraceHeaders"))
  let operations = find_generated_file(plan, "src/operations.mbt").unwrap().content
  assert_true(operations.contains("ConsumeOrdersHandler"))
  assert_true(operations.contains("consumeOrders"))
  let bindings = find_generated_file(plan, "src/bindings.mbt").unwrap().content
  assert_true(bindings.contains("OrderEventsBinding = KafkaBindingConfig"))
}

///|
test "supports deterministic single-file generation" {
  let options = { ..default_codegen_options(), split_files: false }
  let first = generate_from_json(codegen_fixture(), options~).unwrap()
  let second = generate_from_json(codegen_fixture(), options~).unwrap()
  assert_true(first == second)
  inspect(first.files.length(), content="3")
  let source = find_generated_file(first, "src/generated.mbt").unwrap().content
  assert_true(source.contains("pub(all) struct Order"))
  assert_true(source.contains("ConsumeOrdersHandler"))
}

///|
test "can disable transport and operation scaffolding" {
  let options = {
    ..default_codegen_options(),
    emit_protocol_bindings: false,
    emit_operation_stubs: false,
  }
  let plan = generate_from_json(codegen_fixture(), options~).unwrap()
  inspect(find_generated_file(plan, "src/operations.mbt") is None, content="true")
  inspect(find_generated_file(plan, "src/bindings.mbt") is None, content="true")
}

///|
test "reports invalid generator options without hiding generated files" {
  let options = { ..default_codegen_options(), module_name: "" }
  let plan = generate_from_json(codegen_fixture(), options~).unwrap()
  inspect(generation_has_errors(plan), content="true")
  inspect(plan.diagnostics[0].code, content="codegen.module.empty")
  assert_true(plan.files.length() > 0)
}

///|
test "generation manifest is sorted and stable" {
  let plan = generate_from_json(codegen_fixture()).unwrap()
  let manifest = generation_manifest(plan)
  assert_true(manifest.has_prefix("manifest\tmoon.mod"))
  assert_true(manifest.contains("manifest\tmoon.mod"))
  assert_true(manifest.contains("operations\tsrc/operations.mbt"))
}
