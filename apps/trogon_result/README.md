# Trogon.Result

**A zero-dependency Elixir library that provides a composable, pipe-friendly API for working with `{:ok, value}` / `{:error, reason}` tuples, inspired by Rust's `std::result::Result`.**

**Trogon.Result offers construction helpers, predicate checks, guards usable in function heads, ok-side and error-side transformations, short-circuit combinators, side-effect taps for observability, safe and raising unwrap variants, nil rejection, result flattening, and list collection into a single result. Every function is designed to chain cleanly in pipelines.**

**Elixir code that chains operations returning result tuples often accumulates repetitive pattern-matching boilerplate and inconsistent ad-hoc helpers spread across projects. Trogon.Result unifies those operations behind a single, well-typed API so that transforming, inspecting, and composing results is concise and consistent across the codebase.**

**Trogon.Result is useful for any Elixir developer who writes functions returning `{:ok, _}` / `{:error, _}` tuples and wants richer combinators for composing them — especially in codebases with heavy pipeline-style code or where tapping into results for logging and metrics matters.**

## Documentation

### References

- [API Reference](api-reference.html)
