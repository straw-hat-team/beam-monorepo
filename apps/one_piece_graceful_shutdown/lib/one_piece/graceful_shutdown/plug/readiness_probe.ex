defmodule OnePiece.GracefulShutdown.Plug.ReadinessProbe do
  @moduledoc """
  A `Plug` module provides the functionality to check the readiness of the application using
  `OnePiece.GracefulShutdown`.

  When `OnePiece.GracefulShutdown` receive a `SIGTERM` signal and the system will consider not to be running, the
  `Plug` will start sending `503` response to the clients.

  > #### Configuration Required {: .error}
  > `OnePiece.GracefulShutdown` must be also be started, or else this plug will fail at runtime. Make sure to register
  > `OnePiece.GracefulShutdown` in your application supervisor.

  ## Kubernetes Configuration
  Use the `/readiness` endpoint as the `readinessProbe` in your Pod's configuration, e.g.:

  ```yaml
    containers:
      readinessProbe:
        httpGet:
          path: /readiness
        initialDelaySeconds: 20
        periodSeconds: 2
  ```

  `periodSeconds` above means that `/readiness` will be polled every 2 seconds, you should take into account when
  setting the delay in `OnePiece.GracefulShutdown`, as not to shut-down before the K8S load-balancers have noticed
  that the endpoint has started rejecting traffic, allowing any pending requests to complete thereafter.
  """

  alias Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts) do
    %{request_path: Keyword.get(opts, :request_path, "/readiness")}
  end

  @impl Plug
  def call(%Plug.Conn{request_path: request_path} = conn, %{request_path: request_path} = _opts) do
    case OnePiece.GracefulShutdown.running?() do
      true ->
        conn
        |> Conn.resp(200, "")
        |> Conn.send_resp()
        |> Conn.halt()

      false ->
        conn
        |> Conn.resp(503, "")
        |> Conn.send_resp()
        |> Conn.halt()
    end
  end

  @impl Plug
  def call(conn, _opts) do
    conn
  end
end
