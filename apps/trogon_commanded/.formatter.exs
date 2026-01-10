locals_without_parens = [
  register_type: 2,
  import_type_provider: 1,
  register_protobuf_message: 1,
  dispatch_transaction_script: 2,
  identify_aggregate: 1,
  register_transaction_script: 1,
  register_transaction_script: 2,
  polymorphic_embeds_one: 2,
  polymorphic_embeds_many: 2
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
