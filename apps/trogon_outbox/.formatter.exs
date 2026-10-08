test_dirs = if System.get_env("TROGON_OUTBOX_OBAN_PRO") == "true", do: "test,test_pro", else: "test"

[
  line_length: 120,
  import_deps: [:ecto],
  inputs: ["{mix,.formatter}.exs", "{config,lib,#{test_dirs}}/**/*.{ex,exs}"]
]
