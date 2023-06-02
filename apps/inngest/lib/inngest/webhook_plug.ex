defmodule Inngest.WebhookPlug do
  @sdk "elixir:v#{Mix.Project.config()[:version]}"

  alias Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts) do
    opts
  end

  @impl true
  def call(%Conn{method: "POST"} = conn, opts) do
    app_module = Keyword.fetch!(opts, :app)

    case app_module.get_registration("step function") do
      {:error, :not_found} ->
        conn |> Conn.send_resp(410, Jason.encode!(%{error: "function not found"}))

      {:ok, registration} ->
        registration |> dbg()
    end
  end

  @impl true
  def call(%Conn{method: "PUT"} = conn, opts) do
    app_module = Keyword.fetch!(opts, :app)

    conn |> dbg()

    # TODO: would the register URL `ALWAYS` be the same as the `/e/:key` for sending events?
    #  Work on making tihs configurable.
    # register_url = ""

    url =
      conn.host
      |> URI.new!()
      |> Map.put(:path, conn.request_path)

    step_url = URI.append_query(url, URI.encode_query(%{"fnId" => "registration.name", "step" => "step"}, :rfc3986))

    functions =
      app_module.functions()
      |> Enum.map(fn %Inngest.FunctionRegistration{} = registration ->
        %Inngest.SdkFunction{
          name: registration.name,
          id: registration.id,
          trigger: registration.trigger,
          concurrency: registration.concurrency,
          idempotency: registration.idempotency,
          rateLimit: nil,
          retries: registration.retries,
          cancel: nil,
          steps: %{
            "step" => %Inngest.SdkStep{
              name: registration.name,
              id: "step",
              runtime: %{
                "url" => URI.to_string(step_url),
              },
              retries: nil,
            }
          }
        }
      end)

    request = %Inngest.RegisterRequest{
      url: URI.to_string(url),
      v: "1",
      deployType: "ping",
      sdk: @sdk,
      framework: "[TODO]",
      appName: app_module.app_name(),
      functions: functions,
      headers: %Inngest.Headers{
        env: env(opts),
        platform: platform()
      }
    } |> dbg()

    case Inngest.Client.register(opts[:client], request) |> dbg() do
      # TODO: what I suppose to send back here?
      {:ok, _} -> conn |> Conn.send_resp(200, "OK")
      {:error, _} -> conn |> Conn.send_resp(500, "ERROR")
    end
  end

  defp env(opts) do
    case opts[:env] do
      nil -> System.get_env("INNGEST_ENV")
      env -> env
    end
  end

  defp platform do
    # TODO: I dont like this, maybe opt-in for self-discovery?!?
    cond do
      {:ok, region} = System.fetch_env("AWS_REGION") -> "aws-#{region}"
      System.get_env("VERCEL") -> "vercel"
      true -> ""
    end
  end
end
