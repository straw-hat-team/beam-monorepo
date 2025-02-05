defmodule OnePiece.Error do
  def __using__ do
    quote generated: true do
      defexception message: "runtime error"

        defexception [:struct, :term]

        @impl true
        def message(exception) do
          "expected a struct named #{inspect(exception.struct)}, got: #{inspect(exception.term)}"
        end
    end
  end

  # TODO: add `blame` callback
  # https://hexdocs.pm/elixir/Exception.html
end
