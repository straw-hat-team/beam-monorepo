defmodule Trogon.Credo.Check.Warning.SystemEnvRead do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      calls: [
        {System, :get_env},
        {System, :fetch_env},
        {System, :fetch_env!},
        {:os, :getenv},
        {:os, :env}
      ],
      hint: nil,
      allowed_files: [
        {"config/runtime.exs",
         "Runtime config is read once at boot, where the release's environment is the one that runs it."}
      ]
    ],
    explanations: [
      check: """
      `System.get_env/0,1,2` reads the operating system's environment of the node that
      runs the code, and where it runs decides which value it reads. A call in a module
      body or in `config/config.exs` runs when the project compiles, so a release bakes
      in the value of the machine that built it, not the one that runs it. A call in a
      function runs on every invocation, so the project's configuration ends up scattered
      across the code base, each reader with its own default and its own idea of what a
      missing variable means, and a test that needs another value has to write the
      process environment, which is global to the node.

      Environment variables are read once, at boot, in `config/runtime.exs`, and handed
      to the rest of the project through application config. A function that needs a
      value takes it as an argument, or reads it through `Application.fetch_env!/2`
      instead of reaching for the operating system itself:

          # preferred
          # config/runtime.exs
          import Config

          config :acme, :tax_rate, String.to_float(System.get_env("TAX_RATE", "0.0"))

          defmodule Acme.Billing do
            def tax_rate do
              Application.fetch_env!(:acme, :tax_rate)
            end
          end

          # NOT preferred
          defmodule Acme.Billing do
            def tax_rate do
              String.to_float(System.get_env("TAX_RATE", "0.0"))
            end
          end

      This check runs `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` with a default
      list covering `System.get_env/0,1,2`, `System.fetch_env/1`, `System.fetch_env!/1`,
      and the Erlang `:os.getenv/0,1,2` and `:os.env/0`, the way
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` reports every call to them:
      qualified, through an alias, piped, captured, or written against the Erlang module
      directly. A bare call or capture is reported where an `import` brings the function
      in, `import System, only: [get_env: 1]` for instance, and a read in the options of
      a `use`, `use Acme.Options, value: System.fetch_env!("VALUE")`, is reported too,
      since those options are evaluated when the module compiles.

      A file is left alone when its path ends in the path of one of `allowed_files`,
      `config/runtime.exs` by default. Every entry is a `{path, reason}` tuple, and the
      reason is required: it states why that file may read the environment, so whoever
      reads the `.credo.exs` learns the situation instead of guessing, and a bare path,
      a blank reason, or any other shape raises `ArgumentError`. The path is matched on
      whole segments, so `apps/acme/config/runtime.exs` and an absolute path to it are
      allowed, and `myconfig/runtime.exs` is not.
      Writing the environment, `System.put_env/2` and `System.delete_env/1`, is a
      different decision and is not reported.

      Credo does not analyze `config/` by default, since its `files.included` lists
      `lib/`, `test/` and the like, so in practice the check reports reads under `lib`
      and `test`, and `config/runtime.exs` stays unreported even before `allowed_files`
      applies. A project that adds `config/` or `mix.exs` to `files.included` lists
      each file it allows in `allowed_files`, `mix.exs` for instance, since a Mix project
      file runs at compile time by design and may legitimately read the environment:

          # .credo.exs
          {Trogon.Credo.Check.Warning.SystemEnvRead,
           allowed_files: [
             {"config/runtime.exs", "Runtime config is read once at boot."},
             {"mix.exs", "The Mix project file runs at compile time by design."}
           ]}

      Replacing the default drops `config/runtime.exs`, so list it again to keep it allowed.
      """,
      params: [
        calls: """
        The calls this check forbids outside of `allowed_files`, given in the form
        `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` accepts for its own `calls:`
        param, without messages. Defaults to a list covering `System.get_env`,
        `System.fetch_env`, `System.fetch_env!`, `:os.getenv`, and `:os.env`. A project
        with its own wrapper around the environment replaces the default with its own
        list.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can name its own configuration module, `"Read it through Acme.Config
        instead."` for instance. Skipped when set to `nil`, the default.
        """,
        allowed_files: """
        The files allowed to read the environment, given as `{path, reason}` tuples. The
        path is matched against the end of a file's path on whole segments, and the reason
        is a non-blank string that documents why the file may read the environment; an
        entry without one raises `ArgumentError`. Defaults to `config/runtime.exs` with
        the reason that runtime config is read once at boot. A project that analyzes
        `mix.exs` adds `{"mix.exs", "<reason>"}` here, along with `config/runtime.exs`
        again, since replacing the default drops it.
        """
      ]
    ]

  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall
  alias Trogon.Credo.CheckDelegate

  @message "Environment variables are read once at boot in config/runtime.exs and passed " <>
             "through application config; a read here happens at compile time or scatters " <>
             "configuration across the code base. Read the value from application config " <>
             "or take it as an argument instead."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    allowed_files =
      params |> Params.get(:allowed_files, __MODULE__) |> List.wrap() |> Enum.map(&allowed_path!/1)

    if allowed_file?(source_file.filename, allowed_files) do
      []
    else
      run_on_file(source_file, params)
    end
  end

  defp run_on_file(source_file, params) do
    calls = params |> Params.get(:calls, __MODULE__) |> List.wrap()

    CheckDelegate.run(source_file, params, __MODULE__, ForbiddenFunctionCall,
      calls: Enum.map(calls, &forbidden_call/1),
      except: [],
      hint: Params.get(params, :hint, __MODULE__),
      use_options: true
    )
  end

  defp allowed_path!({path, reason} = entry) when is_binary(path) and is_binary(reason) do
    if String.trim(reason) == "", do: invalid_allowed_file!(entry), else: path
  end

  defp allowed_path!(entry), do: invalid_allowed_file!(entry)

  defp invalid_allowed_file!(entry) do
    raise ArgumentError,
          "invalid allowed_files entry #{inspect(entry)}: expected a {path, reason} tuple " <>
            "with a non-blank reason string, such as " <>
            ~s({"test/support/postgres.ex", "Gates the Postgres tests on a database URL."})
  end

  # An allowed path matches the whole filename or a tail of it that starts at a
  # segment boundary, so `myconfig/runtime.exs` never counts as `config/runtime.exs`.
  defp allowed_file?(filename, allowed_files) do
    segments = Path.split(filename)

    Enum.any?(allowed_files, fn allowed ->
      allowed_segments = Path.split(allowed)
      Enum.take(segments, -length(allowed_segments)) == allowed_segments
    end)
  end

  defp forbidden_call({module, function, arity}) when is_atom(function) and is_integer(arity) do
    {{module, function, arity}, @message}
  end

  defp forbidden_call({module, function}) when is_atom(function), do: {{module, function}, @message}
  defp forbidden_call(module), do: {module, @message}
end
