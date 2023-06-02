defmodule Inngest.Client do
  @default_headers [
    {"user-agent", "ElixirInngest/#{Mix.Project.config()[:version]}"},
    {"accept", "application/json"}
  ]

  @enforce_keys [:endpoint, :key]
  defstruct [:endpoint, :key]

  def new(key, opts \\ []) do
    %__MODULE__{key: key, endpoint: opts[:endpoint] || "http://127.0.0.1:8288"}
  end

  def register(%__MODULE__{} = client, %Inngest.RegisterRequest{} = body) do
    send_request(client, method: :post, url: "/fn/register", json: body)
  end

  def send_event(%__MODULE__{} = client, %Inngest.Event{} = body) do
    send_request(client, method: :post, url: "/e/:key", path_params: [key: client.key], json: body)
  end

  def get_health(%__MODULE__{} = client) do
    send_request(client, method: :get, url: "/health")
  end

  defp send_request(%__MODULE__{} = client, opts) do
    req = Req.new(base_url: client.endpoint, headers: @default_headers)

    with {:ok, resp} <- Req.request(req, opts) do
      resp
      |> put_json_body()
      |> to_tuple()
    end
  end

  defp put_json_body(resp) do
    Map.replace!(resp, :body, Jason.decode!(resp.body))
  end

  defp to_tuple(%{status: status} = resp) when status in 200..299, do: {:ok, resp.body}
  defp to_tuple(resp), do: {:error, resp.body}
end
