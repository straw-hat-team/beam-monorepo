defmodule Trogon.Test.Application.MissingEnvError do
  @moduledoc """
  Raised by `fetch_env!/2` on `Trogon.Test.Application.Mock` for a key the test
  removed with `Trogon.Test.Application.delete_env/2`.
  """

  defexception [:app, :key]

  @type t :: %__MODULE__{app: Application.app(), key: Application.key()}

  @impl true
  def message(%__MODULE__{app: app, key: key}) do
    "#{inspect(key)} was deleted from the #{inspect(app)} application environment for this test"
  end
end
