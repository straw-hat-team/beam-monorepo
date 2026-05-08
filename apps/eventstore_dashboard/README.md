# EventStoreDashboard

**EventStoreDashboard is the missing UI for your [`eventstore`](https://hexdocs.pm/eventstore) database.** It plugs into the dashboard your application already exposes, so the same screen you watch processes and ETS tables on now shows the events you persist.

**It adds a page to [Phoenix LiveDashboard](https://hexdocs.pm/phoenix_live_dashboard) that browses streams, events, subscriptions, and snapshots on a running node.** Every page renders against the live `EventStore` instance over an Erlang RPC call — no read replica, no exported copy of the data, no extra deploy. Search and paginate large streams, follow correlation and causation chains across aggregates, and open any event, stream, or snapshot from a single screen.

**Inspecting an event-sourced system through generic database tools is painful.** The `eventstore` schema splits payloads across tables, encodes UUIDs as raw binaries, hides stream boundaries behind join tables, and tells you nothing about subscription lag — every question turns into ad-hoc SQL. EventStoreDashboard answers those questions in domain terms: which events are in this stream, what triggered this command, why is this projection behind.

**It is for Elixir teams already running `EventStore` and Phoenix LiveDashboard in production.** Backend engineers tracing a flow through correlation and causation, operators triaging a stuck subscription, and developers ramping up on an unfamiliar event-sourced codebase work from the same live view — without leaving the dashboard they already trust.

## Getting Started

Add EventStoreDashboard as a page in the `live_dashboard` macro in your router:

```elixir
live_dashboard "/dashboard",
  additional_pages: [
    eventstores: {EventStoreDashboard, event_stores: [MyEventStore]}
  ]
```

Omit `:event_stores` to auto-discover them:

```elixir
live_dashboard "/dashboard",
  additional_pages: [
    eventstores: EventStoreDashboard
  ]
```

Once configured, EventStoreDashboard is available at `/dashboard/eventstore`.
