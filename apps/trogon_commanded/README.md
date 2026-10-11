# Trogon.Commanded

**An opinionated extension layer for the Commanded framework that provides macros, conventions, and building blocks for Domain-Driven Design, Event Sourcing, and CQRS in Elixir.**

**Trogon.Commanded supplies `use`-able modules for defining aggregates, commands, events, value objects, and enums as Ecto embedded schemas with built-in validation, JSON encoding, and factory functions. It enforces a one-command-per-handler Transaction Script pattern via `register_transaction_script`, ships Protobuf-aware and JSONB event store serializers, a compile-time type provider registry, read-after-write consistency policies for the query side, and an infrastructure-free test case template for pure command handler testing.**

**The raw Commanded library provides the mechanics of event sourcing but leaves structural decisions — how to define domain types, wire up routing, serialize events, enforce stream identity naming, handle eventual consistency, and test handlers in isolation — entirely to the developer. Trogon.Commanded fills that gap with a cohesive set of conventions that eliminate boilerplate and prevent common pitfalls like God Object aggregates and stale in-memory processes.**

**Trogon.Commanded is built for Elixir teams that use Commanded as their CQRS/ES framework, follow Domain-Driven Design, store events in PostgreSQL as JSONB, and want strongly-typed domain structs with Ecto validation without requiring a full Ecto Repo.**

## Documentation

### References

- [API Reference](api-reference.html)
