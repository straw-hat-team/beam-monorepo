locals_without_parens = [
  middleware: 1,
  middleware: 2,
  register_command: 2,
  import_dispatcher: 1
]

[
  line_length: 120,
  import_deps: [],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
