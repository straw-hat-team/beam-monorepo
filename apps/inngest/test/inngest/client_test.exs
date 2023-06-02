defmodule Inngest.ClientTest do
  use ExUnit.Case, async: true

  test "POST /e/{key}" do
    assert_call(
      method: :post,
      path: "/e/testing-key",
      req_body: %{
        data: %{username: "yordis"},
        name: "users/signed_up"
      },
      resp_status: 200,
      resp_body: %{"ids" => ["01H1ZWP32XWV4JZWVW70W8SHHT"], "status" => 200}
    )

    client = Inngest.Client.new("testing-key", endpoint: TestServer.url())
    event = %Inngest.Event{name: "users/signed_up", data: %{username: "yordis"}}

    assert {:ok, resp} = Inngest.Client.send_event(client, event)
    assert resp == %{"ids" => ["01H1ZWP32XWV4JZWVW70W8SHHT"], "status" => 200}
  end

  test "GET /health" do
    assert_call(
      method: :get,
      path: "/health",
      req_body: nil,
      resp_status: 200,
      resp_body: %{"message" => "OK", "status" => 200}
    )

    client = Inngest.Client.new("testing-key", endpoint: TestServer.url())

    assert {:ok, resp} = Inngest.Client.get_health(client) |> dbg()
    assert resp == %{"message" => "OK", "status" => 200}
  end

  defp assert_call(opts) do
    path = Keyword.fetch!(opts, :path)
    method = Keyword.fetch!(opts, :method)
    req_body = Keyword.fetch!(opts, :req_body)
    resp_body = Keyword.fetch!(opts, :resp_body)
    resp_status = Keyword.fetch!(opts, :resp_status)

    TestServer.add(path,
      via: method,
      to: fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, [])

        assert [user_agent] = Plug.Conn.get_req_header(conn, "user-agent")
        assert Regex.match?(~r{ElixirInngest/*.*.*}, user_agent)
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]

        if req_body || body != "" do
          assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
          assert body == Jason.encode!(req_body)
        end

        Plug.Conn.send_resp(conn, resp_status, Jason.encode!(resp_body))
      end
    )
  end
end
