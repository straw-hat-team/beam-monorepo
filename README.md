# BEAM Monorepo

**An Elixir umbrella repository housing shared libraries for building event-sourced, protobuf-driven BEAM applications.**

**This monorepo contains packages for structured error handling (`trogon_error`), result type combinators (`trogon_result`), Commanded CQRS/ES extensions (`trogon_commanded`), protobuf schema integration (`trogon_proto`), typed object IDs (`trogon_object_id`), and compile-time type providers (`trogon_typeprovider`).**

**Managing these foundational libraries in separate repositories leads to fragmented CI, version drift, and cross-cutting changes that span multiple PRs. The umbrella structure keeps shared dependencies aligned, enables atomic cross-package changes, and provides a single test and release pipeline.**

**This monorepo is maintained by the Straw Hat Team for Elixir engineers building distributed, event-sourced services that share contracts, conventions, and infrastructure primitives across the platform.**
