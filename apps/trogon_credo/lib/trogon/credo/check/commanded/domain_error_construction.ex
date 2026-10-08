defmodule Trogon.Credo.Check.Commanded.DomainErrorConstruction do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      errors: ["**.Domain.**Error"],
      constructed_in: ["**.Domain", "**.Domain.**", "**.Command.**"],
      hint: nil
    ],
    explanations: [
      check: """
      A domain error is raised by the domain and the command that decided it: the
      domain is what found the invariant broken, and the command layer is what turned
      that into the error the caller sees. Another layer, a web controller or an
      adapter that receives the error, is allowed to react to it, matching it in a
      `rescue` or a pattern, but building or raising one of its own is deciding
      something that is not its decision to make.

          # preferred
          defmodule Acme.Billing.Domain.Invoice do
            def register(%__MODULE__{status: :registered}, _command) do
              raise Acme.Billing.Domain.AlreadyRegisteredError
            end
          end

          defmodule Acme.Billing.Web.InvoiceController do
            def create(conn, params) do
              Acme.Billing.register_invoice(params)
            rescue
              e in Acme.Billing.Domain.AlreadyRegisteredError -> conn |> send_conflict(e)
            end
          end

          # NOT preferred
          defmodule Acme.Billing.Web.InvoiceController do
            def create(conn, params) do
              if already_registered?(params) do
                raise Acme.Billing.Domain.AlreadyRegisteredError
              end
            end
          end

      This check runs `Trogon.Credo.Check.Design.NamespaceBoundary` with `forbidden` set
      to `errors`, `except_in` set to `constructed_in`, and `in_patterns` set to `false`,
      so a reference written as a pattern, a `rescue` clause included, is never reported,
      while building the struct, raising the module, or calling `exception/1` on it from
      anywhere else is.
      """,
      params: [
        errors: """
        A list of module name patterns, given as strings, naming the domain error
        modules this check protects. Defaults to `["**.Domain.**Error"]`, every module
        under a `Domain` namespace whose name ends in `Error`. The pattern grammar is
        the one `Trogon.Credo.Check.Design.NamespaceBoundary` documents.
        """,
        constructed_in: """
        A list of module name patterns, given as strings, naming the namespaces allowed
        to construct or raise a matching error. Defaults to `["**.Domain", "**.Domain.**",
        "**.Command.**"]`, the domain namespace an error belongs to and the command layer
        that decided it.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.Check.Design.NamespaceBoundary
  alias Trogon.Credo.CheckDelegate

  @message "A domain error is raised by the domain and the command that decided it; " <>
             "match on it here instead of constructing or raising it."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    errors = params |> Params.get(:errors, __MODULE__) |> List.wrap()
    constructed_in = params |> Params.get(:constructed_in, __MODULE__) |> List.wrap()

    CheckDelegate.run(source_file, params, __MODULE__, NamespaceBoundary,
      forbidden: Enum.map(errors, &forbidden_error/1),
      except_in: constructed_in,
      in_patterns: false,
      hint: Params.get(params, :hint, __MODULE__)
    )
  end

  defp forbidden_error(pattern), do: {pattern, @message}
end
