defmodule Trogon.Dispatcher.OpenTelemetry.SemConv do
  @moduledoc false

  def messaging_system, do: :"messaging.system"
  def messaging_operation_name, do: :"messaging.operation.name"
  def messaging_operation_type, do: :"messaging.operation.type"
  def messaging_destination_name, do: :"messaging.destination.name"
  def messaging_message_conversation_id, do: :"messaging.message.conversation_id"
  def error_type, do: :"error.type"
end
