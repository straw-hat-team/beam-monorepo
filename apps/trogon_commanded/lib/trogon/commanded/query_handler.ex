defmodule Trogon.Commanded.QueryHandler do
  @moduledoc """
  Defines a module as a "Query Handler". For more information about queries, please read the following:

  - [CQRS pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/cqrs)
  """

  @type view_model :: any()

  @type error :: any()

  @doc """
  Handle the incoming `params` and return the result data.
  """
  @callback handle(params :: any()) :: {:ok, view_model()} | {:error, error()}

  @doc """
  Convert the module into a `Trogon.Commanded.QueryHandler`.

  ## Usage

      defmodule MyQueryHandler do
        use Trogon.Commanded.QueryHandler
        import Ecto.Query, only: [from: 2]

        @impl Trogon.Commanded.QueryHandler
        def handle(params) do
          query = from u in User,
                    where: u.age > 18 or is_nil(params.email),
                    select: u

          {:ok, Repo.all(query)}
        end
      end
  """
  @spec __using__(opts :: []) :: any()
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Trogon.Commanded.QueryHandler
    end
  end
end
