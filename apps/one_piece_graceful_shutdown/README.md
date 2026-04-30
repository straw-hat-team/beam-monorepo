# OnePiece.GracefulShutdown

**An Elixir library that intercepts SIGTERM to give your BEAM application a controlled, two-phase graceful shutdown.**

**OnePiece.GracefulShutdown hooks into the Erlang VM's signal server, transitions the application into a draining state that makes readiness probes return HTTP 503, waits a configurable delay for in-flight requests to complete, and then initiates an orderly `System.stop/0`. It includes a Plug-based readiness probe endpoint out of the box.**

**Container orchestrators like Kubernetes send SIGTERM before killing pods, but the BEAM does not cooperate with that signal by default — it may terminate mid-request, dropping live connections and losing in-flight work. This library bridges that gap so load balancers stop routing traffic before the VM shuts down.**

**OnePiece.GracefulShutdown is built for Elixir teams running on Kubernetes or similar orchestration platforms that use rolling deploys, horizontal autoscaling, or any scenario where pods are replaced and zero-downtime draining is required.**

## Documentation

### References

- [API Reference](api-reference.html)
