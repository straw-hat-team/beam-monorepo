defmodule Trogon.Credo.Check.Design.AppDependency do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      forbidden: [],
      except: [],
      hint: nil
    ],
    explanations: [
      check: """
      A project split into several applications decides which of them may depend on
      which: a core application that must not reach for the web one, a library
      application that must stay free of the framework its callers use. The decision is
      written once, in a `deps/0` function, and the moment someone adds a line there the
      architecture has changed. Nothing reports that, since the build is happy either
      way.

      This check reads that line. A project scopes an instance to the application whose
      dependencies it constrains with Credo's own `files:` param, and lists what that
      application may not depend on in `forbidden`.

          # the core application must not depend on the web one
          {Trogon.Credo.Check.Design.AppDependency,
           [forbidden: [:acme_web],
            files: %{included: ["apps/acme_core/mix.exs"]}]}

          # a worker may reach for the core application, and for no other application of its own project
          {Trogon.Credo.Check.Design.AppDependency,
           [forbidden: ["acme_*"],
            except: [:acme_core],
            files: %{included: ["apps/acme_worker/mix.exs"]}]}

      A dependency name is matched by the pattern syntax
      `Trogon.Credo.Check.Design.NamespaceBoundary` documents, anchored at both ends,
      where everything other than a wildcard is literal. A name has no segments, so a
      single `*` covers any run of characters in it, and a dependency name given as an
      atom names only that dependency.

      Only the body of a `deps/0` function inside a `mix.exs` is read, so a Mix alias or
      any other keyword list that happens to look like a dependency list is left alone,
      and a dependency whose name is not written as a literal atom is not reported.

      The dependency this check reads is the declared one, so a dependency reached
      transitively is not reported. That is deliberate: a declared dependency is the
      decision a project makes and reviews, while the transitive closure is the
      resolution of everyone else's decisions, which belongs to a tool that reads a
      built dependency graph.

      It is the build level companion of
      `Trogon.Credo.Check.Design.NamespaceBoundary`, which states the same kind of rule
      one module reference at a time. An application that may not depend on another is
      better said once here than as a namespace pattern every file is matched against.
      """,
      params: [
        forbidden: """
        A list of dependency name patterns, given as strings, or as `{pattern, "message"}`
        tuples that each carry their own message. A dependency name, given as an atom, is
        also accepted and matches only that dependency. The default empty list makes the
        check inert, since there is no universal dependency rule; a project configures its
        own with `forbidden` and, usually, with `files:`.
        """,
        except: """
        A list of dependency name patterns that carve exceptions out of `forbidden`. A
        dependency matching any `except` pattern is never reported, even when it also
        matches a forbidden one, which is how a rule forbids a whole family of
        applications and then allows the one that is meant to be shared. The pattern
        syntax is the one `forbidden` uses, without its `{pattern, "message"}` form, since
        an exception reports nothing and so has no message to carry. The default empty
        list means there is no exception; `nil` is also accepted and treated the same way.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a project
        can say in its own words what to do instead. Skipped when set to `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.MixDeps
  alias Trogon.Credo.ModulePattern

  @doc false
  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    forbidden = prepare_forbidden(Params.get(params, :forbidden, __MODULE__) || [])

    if forbidden == [] or Path.basename(filename) != "mix.exs" do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        forbidden: forbidden,
        except: prepare_except(Params.get(params, :except, __MODULE__) || []),
        hint: Params.get(params, :hint, __MODULE__)
      }

      source_file
      |> MixDeps.names()
      |> Enum.flat_map(&issues_for(&1, context))
    end
  end

  defp issues_for({dep, line_no}, context) do
    name = to_string(dep)

    with false <- matches?(context.except, name),
         {_regex, message} <- Enum.find(context.forbidden, &matches_entry?(&1, name)) do
      [issue_for(context, dep, line_no, message)]
    else
      _ -> []
    end
  end

  defp matches?(patterns, name), do: Enum.any?(patterns, &Regex.match?(&1, name))

  defp matches_entry?({regex, _message}, name), do: Regex.match?(regex, name)

  defp issue_for(context, dep, line_no, message) do
    format_issue(
      context.issue_meta,
      message: append_hint(message || default_message(dep), context.hint),
      trigger: to_string(dep),
      line_no: line_no
    )
  end

  defp default_message(dep), do: "This application must not depend on `#{inspect(dep)}`."

  defp prepare_forbidden(forbidden) when is_list(forbidden) do
    Enum.map(forbidden, &normalize_forbidden/1)
  end

  defp prepare_forbidden(other), do: raise_invalid_forbidden(other)

  defp normalize_forbidden({pattern, message}) when is_binary(message) do
    {compile_forbidden!(pattern), message}
  end

  defp normalize_forbidden(pattern) when is_binary(pattern) or is_atom(pattern) do
    {compile_forbidden!(pattern), nil}
  end

  defp normalize_forbidden(other), do: raise_invalid_forbidden(other)

  defp compile_forbidden!(pattern) do
    case ModulePattern.compile(pattern) do
      {:ok, regex} -> regex
      :error -> raise_invalid_forbidden(pattern)
    end
  end

  defp raise_invalid_forbidden(entry) do
    raise ArgumentError,
          "invalid forbidden entry #{inspect(entry)}: expected a dependency name pattern as a string, a dependency name as an atom, or either of those paired with a message"
  end

  defp prepare_except(except) when is_list(except), do: Enum.map(except, &normalize_except/1)
  defp prepare_except(other), do: raise_invalid_except(other)

  defp normalize_except(pattern) when is_binary(pattern) or is_atom(pattern) do
    case ModulePattern.compile(pattern) do
      {:ok, regex} -> regex
      :error -> raise_invalid_except(pattern)
    end
  end

  defp normalize_except(other), do: raise_invalid_except(other)

  defp raise_invalid_except(entry) do
    raise ArgumentError,
          "invalid except entry #{inspect(entry)}: expected a dependency name pattern as a string, or a dependency name as an atom, without a message, since an exception reports nothing"
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
