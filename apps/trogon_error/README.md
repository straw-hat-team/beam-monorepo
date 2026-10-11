# Trogon.Error

**A structured error library for Elixir that treats errors as typed values with domain-scoped identity, metadata, and visibility controls.**

**Trogon.Error lets you define error modules using `use Trogon.Error` with a domain, reason, code, and message. Each error carries Google RPC-compatible status codes, visibility levels, structured metadata with per-field visibility, localization support, retry information, and help links. Errors can also be created dynamically at runtime for handling external service failures.**

**Applications that cross service boundaries, expose APIs, or feed errors into monitoring pipelines need errors that are machine-parseable, consistently shaped, and safe to surface to different audiences. Trogon.Error enforces compile-time message contracts and metadata visibility so that internal details never leak to end users by accident.**

**Trogon.Error is built for Elixir teams that operate distributed systems, build public or internal APIs, or need structured error contracts that integrate cleanly with gRPC, REST, and observability tooling.**

## Documentation

### References

- [API Reference](api-reference.html)
