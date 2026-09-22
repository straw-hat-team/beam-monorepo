defmodule Trogon.Credo.Check.Readability.ForbiddenFilePath do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      forbidden: [],
      except: [],
      hint: nil
    ],
    explanations: [
      check: """
      Where a file lives is part of a project's structure, and some directories are
      decided rather than discovered: a compile time test helper belongs in
      `test/support` because that is the path a project wires into `elixirc_paths`,
      a generated directory is not hand edited, a directory being retired takes no
      new files. None of that is visible in a module's contents, so no check that
      reads code can enforce it.

      This check matches a file's path and reports the file itself, which is how a
      project says "nothing may live here".

          {Trogon.Credo.Check.Readability.ForbiddenFilePath,
           [forbidden: [
              {"test/**/*.ex", "A compile-time test file must live in `test/support`."}
            ],
            except: ["test/support/**"]]}

      `forbidden` with `except` is how a single allowed location is expressed:
      forbid the whole tree, then except the one directory that is wired into
      `elixirc_paths`. `forbidden` on its own closes a directory entirely.

      A pattern matches a path as Credo reports it, relative to the directory
      `mix credo` runs in, so a project configuring this at the root of a monorepo
      writes `apps/*/test/**/*.ex` where one configuring it inside a single app
      writes `test/**/*.ex`. The path is matched whole, anchored at both ends, and
      everything other than a wildcard is literal.

      | pattern | matches |
      | --- | --- |
      | `*` | any run of characters within one path segment, never crossing a `/` |
      | `**` | zero or more whole path segments, so it crosses `/` |
      | `test/**/*.ex` | `test/foo.ex` and `test/a/b/foo.ex` |
      | `test/support/**` | anything under `test/support`, at any depth |

      The issue is reported at the first line of the file, since the file existing
      at that path is the problem rather than anything written in it. Nothing in the
      file is parsed, which makes this the one check here that says nothing about
      the code, and the only one that still reports a file Credo cannot compile.

      Credo's own per check `files:` param can narrow which files this check sees,
      but the patterns live in `forbidden` rather than in `files:` so that an
      unconfigured instance stays silent. A check whose rule was carried entirely by
      `files:` would report every file in the project by default.
      """,
      params: [
        forbidden: """
        A list of path patterns, given as strings, or as `{pattern, "message"}`
        tuples that each carry their own message. The default empty list makes the
        check inert, since there is no universal forbidden path.
        """,
        except: """
        A list of patterns, in the same syntax as `forbidden`, that carve exceptions
        out of it. A path matching any `except` pattern is never reported, even when
        it also matches a `forbidden` one. The default empty list means there is no
        exception; `nil` is also accepted and treated the same way.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    case Params.get(params, :forbidden, __MODULE__) do
      forbidden when forbidden in [nil, []] -> []
      forbidden -> check_path(source_file, forbidden, params)
    end
  end

  defp check_path(source_file, forbidden, params) do
    except = Params.get(params, :except, __MODULE__) || []
    path = source_file.filename

    case match_forbidden(path, prepare(forbidden), Enum.map(except, &compile_pattern/1)) do
      nil -> []
      message -> [issue_for(source_file, params, message)]
    end
  end

  defp match_forbidden(path, forbidden, except) do
    if excepted?(path, except) do
      nil
    else
      forbidden
      |> Enum.find(&matches?(&1, path))
      |> forbidden_message(path)
    end
  end

  defp matches?({regex, _message}, path), do: Regex.match?(regex, path)

  defp excepted?(path, except), do: Enum.any?(except, &Regex.match?(&1, path))

  defp forbidden_message(nil, _path), do: nil
  defp forbidden_message({_regex, nil}, path), do: default_message(path)
  defp forbidden_message({_regex, message}, _path), do: message

  defp default_message(path), do: "A file must not live at `#{path}`."

  defp issue_for(source_file, params, message) do
    hint = Params.get(params, :hint, __MODULE__)

    format_issue(
      IssueMeta.for(source_file, params),
      message: append_hint(message, hint),
      trigger: Credo.Issue.no_trigger(),
      line_no: 1
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"

  defp prepare(patterns), do: Enum.map(patterns, &prepare_entry/1)

  defp prepare_entry({pattern, message}) when is_binary(message) do
    {compile_pattern(pattern), message}
  end

  defp prepare_entry({_pattern, _message} = entry) do
    raise ArgumentError,
          "invalid forbidden entry #{inspect(entry)}: the message in a {pattern, message} tuple must be a string"
  end

  defp prepare_entry(pattern), do: {compile_pattern(pattern), nil}

  defp compile_pattern(pattern) when is_binary(pattern), do: to_regex(pattern)

  defp compile_pattern(pattern) do
    raise ArgumentError,
          "invalid file path pattern #{inspect(pattern)}: expected a path pattern as a string"
  end

  defp to_regex(pattern) do
    regex_source =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*/", "(?:[^/]+/)*")
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")

    Regex.compile!("^#{regex_source}$")
  end
end
