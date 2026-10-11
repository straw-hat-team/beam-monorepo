defmodule Trogon.Dispatcher.OpenTelemetry.SemConv do
  @moduledoc false

  def messaging_system, do: :"messaging.system"
  def messaging_operation_name, do: :"messaging.operation.name"
  def messaging_operation_type, do: :"messaging.operation.type"
  def messaging_destination_name, do: :"messaging.destination.name"
  def messaging_message_id, do: :"messaging.message.id"
  def messaging_message_conversation_id, do: :"messaging.message.conversation_id"
  def error_type, do: :"error.type"
  def code_function_name, do: :"code.function.name"

  # Not a semantic convention attribute yet. The unprefixed name matches what other Elixir OpenTelemetry
  # integrations use for the same fact, so it lives here rather than under `trogon_dispatcher.`.
  def erlang_exception_kind, do: :"erlang.exception.kind"
end
