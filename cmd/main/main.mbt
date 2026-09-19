///|
#cfg(target="js")
extern "js" fn cli_arguments() -> FixedArray[String] =
  #|() => process.argv.slice(2)

///|
#cfg(target="js")
extern "js" fn cli_read_text(path : String) -> String =
  #|(path) => require("node:fs").readFileSync(path, "utf8")

///|
#cfg(target="js")
extern "js" fn cli_write_text(path : String, content : String) -> Unit =
  #|(path, content) => {
  #|  const fs = require("node:fs")
  #|  const p = require("node:path")
  #|  fs.mkdirSync(p.dirname(path), { recursive: true })
  #|  fs.writeFileSync(path, content, "utf8")
  #|}

///|
#cfg(target="js")
extern "js" fn cli_fail(message : String) -> Unit =
  #|(message) => {
  #|  console.error(message)
  #|  process.exitCode = 1
  #|}

///|
fn usage() -> String {
  "Usage: moon run cmd/main --target js -- <asyncapi.json> <output-dir> [module-name]"
}

///|
#cfg(target="js")
fn main {
  let args = cli_arguments()
  if args.length() < 2 || args.length() > 3 {
    cli_fail(usage())
    return
  }
  let input_path = args[0]
  let output_dir = args[1]
  let module_name = if args.length() == 3 {
    args[2]
  } else {
    "generated/asyncapi"
  }
  let input = cli_read_text(input_path)
  let options = { ..@lib.default_codegen_options(), module_name, }
  match @lib.generate_from_json(input, options~) {
    Err(error) => cli_fail("MoonAsyncAPI: " + error)
    Ok(plan) => {
      if @lib.generation_has_errors(plan) {
        cli_fail("MoonAsyncAPI: generation failed")
        return
      }
      for file in plan.files {
        cli_write_text(output_dir + "/" + file.path, file.content)
      }
      println(
        "Generated " +
        plan.files.length().to_string() +
        " files in " +
        output_dir,
      )
    }
  }
}

///|
#cfg(not(target="js"))
fn main {
  let _ = @lib.default_codegen_options()
  println("MoonAsyncAPI CLI requires the JavaScript target.")
  println(usage())
}
