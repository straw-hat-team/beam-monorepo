defmodule Trogon.Dispatcher.DispatchOptions do
  @moduledoc """
  Caller-supplied options for a dispatch.

  Everything a caller is allowed to seed the `Trogon.Dispatcher.Context` with lives here. `private` is deliberately
  absent: it is middleware scratch space, not caller input.
  """

  defstruct correlation_id: nil,
            causation_id: nil,
            actor: nil,
            assigns: %{}

  @type t :: %__MODULE__{
          correlation_id: term() | nil,
          causation_id: term() | nil,
          actor: term() | nil,
          assigns: map()
        }

  @doc """
  Builds options for a nested dispatch out of the context of the dispatch currently in flight.

  Carries `correlation_id` and `actor` forward. It does not carry `causation_id`: the library defines no identity
  contract for commands, so it cannot know what identifies the causing message. Set it yourself from whatever identity
  your commands carry.

  ## Example

      def handle_message(%ArchiveUser{} = message, context) do
        options = DispatchOptions.from_context(context)
        MyApp.Dispatcher.dispatch_message(%NotifyUser{user_id: message.user_id}, options)
      end
  """
  @spec from_context(Trogon.Dispatcher.Context.t()) :: t()
  def from_context(%Trogon.Dispatcher.Context{} = context) do
    %__MODULE__{
      correlation_id: context.correlation_id,
      actor: context.actor,
      assigns: context.assigns
    }
  end
end
