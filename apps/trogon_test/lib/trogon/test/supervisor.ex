defmodule Trogon.Test.Supervisor do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {NimbleOwnership, name: Trogon.Test.Ownership}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
