# Trogon.GrpcHealth

[![Hex.pm](https://img.shields.io/hexpm/v/trogon_grpchealth.svg)](https://hex.pm/packages/trogon_grpchealth)
[![Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/trogon_grpchealth/)
[![License](https://img.shields.io/hexpm/l/trogon_grpchealth.svg)](https://github.com/straw-hat-team/beam-monorepo/blob/master/LICENSE)

A production-ready gRPC health check service for Elixir, compatible with Google's gRPC health check protocol.

Works with `grpcurl`, `grpc-health-probe`, and Kubernetes liveness/readiness probes.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:trogon_grpchealth, "~> 0.1"}
  ]
end
```

## Quick Start

### 1. Create a Health Service

```elixir
defmodule MyApp.HealthService do
  use Trogon.GrpcHealth.StaticHealth, otp_app: :my_app
end
```

### 2. Configure Services

In `config/config.exs`:

```elixir
config :my_app, MyApp.HealthService,
  services: %{
    "my.service.v1.MyService" => :serving,
    "" => :serving  # Process-wide health
  }
```

### 3. Mount on gRPC Endpoint

```elixir
defmodule MyApp.Endpoint do
  use GRPC.Endpoint

  run(MyApp.HealthService)
end
```

Done! Your service now responds to health checks.

## Testing

```bash
# Check a service
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check \
  -d '{"service":"my.service.v1.MyService"}'

# Check process-wide health
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check \
  -d '{"service":""}'
```

## Runtime Changes

Update services dynamically:

```elixir
Application.put_env(:my_app, MyApp.HealthService,
  services: %{"new.service" => :serving})
```

The next health check will see the updated configuration.

## Kubernetes Integration

```yaml
livenessProbe:
  grpc:
    port: 50051
    service: "my.service.v1.MyService"
  initialDelaySeconds: 10
  periodSeconds: 10
```

## How It Works

- The macro generates a complete gRPC service implementation
- Each health check reads `Application.get_env/2`
- Returns `SERVING` if the service is configured, `NOT_SERVING` otherwise
- Watch (streaming) returns `Unimplemented` per the gRPC spec

## Documentation

Full API documentation available at [hexdocs.pm](https://hexdocs.pm/trogon_grpchealth/)

## License

MIT - See LICENSE file
