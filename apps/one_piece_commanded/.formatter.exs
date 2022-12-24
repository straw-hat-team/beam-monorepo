locals_without_parens = [
  register_type: 2,
  import_type_provider: 1
]

[
  line_length: 120,
  import_deps: [:ecto],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
