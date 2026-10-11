# Trogon.Proto

**An Elixir runtime and integration layer for the trogon-proto Buf Schema Registry that ships pre-compiled protobuf modules and compile-time macros for schema-driven code generation.**

**Trogon.Proto provides two main macros: `Trogon.Proto.Env` reads proto field annotations to generate typed, secret-safe environment variable loaders with automatic type conversion and masked `Inspect` output; and `Trogon.Proto.Uuid.V1.UuidTemplate` reads proto enum annotations to generate deterministic UUIDv5 identity functions from versioned templates. It also ships shared proto message contracts for Relay cursor pagination, CQRS read-your-writes consistency, structured error templates, typed UUIDs, stream identity, and object ID prefixes.**

**Teams using protobuf as a cross-language contract layer accumulate boilerplate around environment config loading, deterministic ID generation, and shared primitives like pagination and consistency. Trogon.Proto encodes those conventions directly in the proto schema as custom extensions and generates correct Elixir code at compile time — eliminating drift between the schema definition and runtime behavior.**

**Trogon.Proto is built for Elixir teams that use protobuf as their service contract layer and need schema-driven code generation for config, identity, and shared API primitives across gRPC or event-driven architectures.**

## Documentation

### References
- [API Reference](api-reference.html)
