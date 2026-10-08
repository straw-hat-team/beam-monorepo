defmodule Trogon.Credo.Check.Commanded.ErrorConstruction do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      errors: ["(*.*).**Error"],
      hint: nil
    ],
    explanations: [
      check: """
      An error belongs to the context that defines it, and that context is the one that
      decides when it happens. A context is whatever owns the decision, a domain layer,
      a command layer, or a web server that is its own domain; nothing here asks for a
      layer by name. Another context building or raising that error decides something on
      the owner's behalf, and keeps deciding it the old way after the owner changes its
      rule. Reacting to the error, matching it in a `rescue` or a pattern, leaves the
      decision with its owner and is never reported.

          # preferred
          defmodule Acme.Billing.Invoice do
            def register(%__MODULE__{status: :registered}, _command) do
              raise Acme.Billing.AlreadyRegisteredError
            end
          end

          defmodule Acme.Web.InvoiceController do
            def create(conn, params) do
              Acme.Billing.register_invoice(params)
            rescue
              e in Acme.Billing.AlreadyRegisteredError -> conn |> send_conflict(e)
            end

            def show(conn, %{"id" => id}) do
              raise Acme.Web.NotFoundError, id: id
            end
          end

          # NOT preferred
          defmodule Acme.Web.InvoiceController do
            def create(conn, params) do
              if already_registered?(params) do
                raise Acme.Billing.AlreadyRegisteredError
              end
            end
          end

      This check runs `Trogon.Credo.Check.Design.NamespaceBoundary` with `private_to` set
      to `errors` and `in_patterns` set to `false`, so a reference written as a pattern,
      a `rescue` clause included, is never reported, while building the struct, raising
      the module, or calling a function on it from outside its owner is.
      """,
      params: [
        errors: """
        A list of patterns in the form `Trogon.Credo.Check.Design.NamespaceBoundary`
        accepts for `private_to`: the parenthesized prefix names the owning context, and
        the remainder names its errors. Defaults to `["(*.*).**Error"]`, so the first
        two segments of an error module own it, `Acme.Billing` for
        `Acme.Billing.Domain.NotFoundError`. A project whose contexts sit deeper writes
        its own prefix, `"(Acme.*.*).**Error"` for instance.
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

  @message "Only the context that defines this error builds or raises it; match on it " <>
             "here, or raise an error this context owns."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    errors = params |> Params.get(:errors, __MODULE__) |> List.wrap()

    CheckDelegate.run(source_file, params, __MODULE__, NamespaceBoundary,
      private_to: Enum.map(errors, &owned_error/1),
      in_patterns: false,
      hint: Params.get(params, :hint, __MODULE__)
    )
  end

  defp owned_error(pattern), do: {pattern, @message}
end
