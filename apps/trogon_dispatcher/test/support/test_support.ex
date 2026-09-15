defmodule Support do
  @moduledoc false

  defmodule Opaque do
    @moduledoc false
    # Hides a value from the compiler's type checker so the deliberately invalid fixtures below reach the runtime
    # guard instead of being flagged at compile time.
    def wrap(term), do: Process.get(:__trogon_dispatcher_opaque__, term)
  end

  defmodule User do
    @moduledoc false
    defstruct [:email, :tenant, :actor, :trail]
  end

  defmodule RegisterUser do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Handler

    defstruct [:email]

    @impl true
    def handle_command(%__MODULE__{} = command, context) do
      {:ok,
       %User{
         email: command.email,
         tenant: Trogon.Dispatcher.Context.get_private(context, Support.RequireTenant),
         actor: context.actor,
         trail: Map.get(context.assigns, :trail, [])
       }}
    end
  end

  defmodule GetUser do
    @moduledoc false
    defstruct [:id]

    def handle_command(%__MODULE__{}, _context), do: {:ok, %User{email: "read@example.com"}}
  end

  defmodule ArchiveUser do
    @moduledoc false
    defstruct [:id]
  end

  defmodule ArchiveUserHandler do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Handler

    @impl true
    def handle_command(%ArchiveUser{}, _context), do: :ok
  end

  defmodule FailingCommand do
    @moduledoc false
    defstruct []

    def handle_command(%__MODULE__{}, _context), do: {:error, :nope}
  end

  defmodule ExplodingCommand do
    @moduledoc false
    defstruct []

    def handle_command(%__MODULE__{}, _context) do
      if Opaque.wrap(true), do: raise(RuntimeError, "boom"), else: :ok
    end
  end

  defmodule ListReturningCommand do
    @moduledoc false
    defstruct []

    def handle_command(%__MODULE__{}, _context), do: {:ok, Opaque.wrap([%User{}])}
  end

  defmodule MapReturningCommand do
    @moduledoc false
    defstruct []

    def handle_command(%__MODULE__{}, _context), do: {:ok, Opaque.wrap(%{email: "nope"})}
  end

  defmodule NotRegistered do
    @moduledoc false
    defstruct []
  end

  defmodule BillingCommand do
    @moduledoc false
    defstruct []

    def handle_command(%__MODULE__{}, context) do
      {:ok, %User{trail: Map.get(context.assigns, :trail, [])}}
    end
  end

  defmodule Trail do
    @moduledoc false

    def append(context, name) do
      trail = Map.get(context.assigns, :trail, [])
      Trogon.Dispatcher.Context.assign(context, :trail, trail ++ [name])
    end
  end

  defmodule RequireTenant do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Middleware

    @impl true
    def init(opts), do: Keyword.get(opts, :tenant, "acme")

    @impl true
    def call(context, next, tenant) do
      context
      |> Trogon.Dispatcher.Context.put_private(__MODULE__, tenant)
      |> Trail.append(:require_tenant)
      |> next.()
    end
  end

  defmodule Authorize do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Middleware

    @impl true
    def init(opts), do: opts

    @impl true
    def call(context, next, _options) do
      case context.actor do
        :forbidden ->
          Trogon.Dispatcher.Context.put_response(context, {:error, :unauthorized})

        _actor ->
          context |> Trail.append(:authorize) |> next.()
      end
    end
  end

  defmodule NoInit do
    @moduledoc false

    def call(context, next, options) do
      context |> Trail.append({:no_init, options}) |> next.()
    end
  end

  defmodule Stamp do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Middleware

    @impl true
    def call(context, next, _options) do
      context
      |> next.()
      |> Trogon.Dispatcher.Context.put_private(__MODULE__, :stamped)
      |> Trail.append(:stamp)
    end
  end

  defmodule Halting do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Middleware

    @impl true
    def call(context, _next, _options), do: Opaque.wrap(context)
  end

  defmodule BadMiddleware do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Middleware

    @impl true
    def init(opts), do: opts

    @impl true
    def call(_context, _next, _options), do: Opaque.wrap(:bogus)
  end

  defmodule AccountsDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware RequireTenant

    register_command RegisterUser, kind: :command
    register_command GetUser, kind: :query
    register_command ArchiveUser, kind: :command, to: ArchiveUserHandler
    register_command FailingCommand, kind: :command
    register_command ExplodingCommand, kind: :command
    register_command ListReturningCommand, kind: :query
    register_command MapReturningCommand, kind: :query
  end

  defmodule BillingDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    register_command BillingCommand, kind: :command
  end

  defmodule RootDispatcher do
    @moduledoc false
    use Trogon.Dispatcher, telemetry_prefix: [:support, :root]

    middleware Authorize

    import_dispatcher AccountsDispatcher
    import_dispatcher BillingDispatcher
  end

  defmodule BadMiddlewareDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware BadMiddleware

    register_command RegisterUser, kind: :command
  end

  defmodule HaltingDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware Halting

    register_command RegisterUser, kind: :command
  end

  defmodule StampDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware Stamp
    middleware RequireTenant

    register_command RegisterUser, kind: :command
  end

  defmodule NoInitDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware NoInit, some: :option

    register_command RegisterUser, kind: :command
  end

  defmodule SharedMiddlewareDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware Authorize

    register_command BillingCommand, kind: :command
  end

  defmodule RepeatedMiddlewareDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    middleware Authorize

    import_dispatcher SharedMiddlewareDispatcher
  end

  defmodule LeftDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    import_dispatcher BillingDispatcher
  end

  defmodule RightDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    import_dispatcher BillingDispatcher
  end

  defmodule DiamondDispatcher do
    @moduledoc false
    use Trogon.Dispatcher

    import_dispatcher LeftDispatcher
    import_dispatcher RightDispatcher
  end
end
