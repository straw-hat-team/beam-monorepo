# BEAM Monorepo

**An Elixir umbrella repository housing shared libraries for building event-sourced, protobuf-driven BEAM applications.** Each library ships as its own Hex package, versioned and released from this one repository.

**It contains packages for structured errors, result combinators, Commanded CQRS/ES extensions, command dispatch, protobuf integration, typed object IDs, Ecto value objects, type providers, custom Credo checks, ExUnit test support, and layered module configuration.** These are `trogon_error`, `trogon_result`, `trogon_commanded`, `trogon_dispatcher`, `trogon_proto`, `trogon_object_id`, `trogon_ecto`, `trogon_typeprovider`, `trogon_credo`, `trogon_test`, and `trogon_configurable`, alongside `eventstore_dashboard`, a LiveDashboard page for inspecting a Commanded EventStore.

**Keeping these foundational libraries in separate repositories leads to fragmented CI, version drift, and cross-cutting changes that span multiple PRs.** The umbrella structure keeps shared dependencies aligned, enables atomic cross-package changes, and provides a single test and release pipeline.

**This monorepo is maintained by the Straw Hat Team for Elixir engineers building distributed, event-sourced services.** Those services share contracts, conventions, and infrastructure primitives across the platform, and these packages are where they live.
