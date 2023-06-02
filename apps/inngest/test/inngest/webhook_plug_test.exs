defmodule Inngest.WebhookPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule MyApp do
    use Inngest.App,
      app_name: "My App"

    register_function(%Inngest.FunctionRegistration{
      trigger: %Inngest.EventTrigger{event: "my-event"},
      name: "step function",
      callback: &MyApp.handle_event/1
    })

    def handle_event(event) do
      event |> dbg()
    end
  end

  test "POST /" do
    client = Inngest.Client.new("testing-key")

    assert Inngest.WebhookPlug.call(
             make_invoke_req(),
             Inngest.WebhookPlug.init(
               app: MyApp,
               client: client
             )
           )
  end

  test "PUT /" do
    client = Inngest.Client.new("testing-key")

    assert Inngest.WebhookPlug.call(
             make_register_req(),
             Inngest.WebhookPlug.init(
               app: MyApp,
               client: client
             )
           )
  end

  def make_invoke_req do
    Plug.Test.conn(:post, "/webhooks/inngest")
  end

  def make_register_req do
    Plug.Test.conn(:put, "/webhooks/inngest")
  end
end
