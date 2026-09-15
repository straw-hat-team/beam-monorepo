# Trogon.Credo

**Trogon.Credo is a shared library of Credo checks you depend on instead of copy.** It turns the custom check modules that accumulate in a project's `.credo/checks/` directory into a versioned Hex package that many repositories can point at.

**The package ships check modules and nothing else.** Each check lives under the `Trogon.Credo.Check.<Category>.<Name>` namespace, mirroring Credo's own layout, and is built entirely on Credo's public API so a Credo patch release cannot break it. There is no Credo plugin here, so every consumer enables the checks it wants in its own `.credo.exs` and leaves the rest out.

**Custom Credo checks have no distribution story of their own.** A check written for one repository gets copied into the next, then the two drift: a false positive fixed in one copy stays broken in the other, and neither version is tested anywhere. Shipping the checks as a dependency gives them a single source, a test suite, and a version number, so a fix reaches every project that upgrades.

**This is for teams running Credo across more than one Elixir repository**, and for anyone who has already written a custom check worth keeping. Checks that encode an architectural convention, such as where a layer's modules must live, are parameterized and ship inert, so the conventions stay in each project's configuration while the code that enforces them stays here.

## How-to

### Install

```elixir
def deps do
  [
    {:trogon_credo, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

### Enable a check

Add the check module to the `checks: %{enabled: [...]}` list in your project's `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: %{
        enabled: [
          {Trogon.Credo.Check.Warning.ForbiddenImport,
           [modules: [{MyApp.Fixtures, "Call MyApp.Fixtures functions with the full name."}]]}
        ]
      }
    }
  ]
}
```

Run `mix credo` as usual and the enabled checks run alongside Credo's built-in ones.

## References

### `Trogon.Credo.Check.Warning.ForbiddenImport`

Flags `import` of modules that should always be called explicitly. The `import` counterpart to Credo's built-in `Credo.Check.Warning.ForbiddenModule`. Calls to the module are never flagged, only `import` directives, including the multi-import form `import Foo.{Bar, Baz}`.

```elixir
{Trogon.Credo.Check.Warning.ForbiddenImport,
 [modules: [MyApp.Fixtures, {MyApp.Helpers, "Call MyApp.Helpers functions explicitly."}]]}
```

| Param | Default | Meaning |
| --- | --- | --- |
| `modules` | `[]` | Modules, or `{Module, "message"}` tuples, that must not be imported. |

### `Trogon.Credo.Check.Warning.UnpinnedDependency`

Flags dependencies that are not pinned to an immutable reference, so builds stay reproducible. Only analyzes `mix.exs`. A dependency counts as pinned when it is a git dependency with `ref:` set to a full 40 character commit sha, or a Hex dependency with an exact version such as `"0.5.0"`. A `branch:`, a `tag:`, a short sha, and operator requirements like `~> 0.5.0` are all rejected.

```elixir
{Trogon.Credo.Check.Warning.UnpinnedDependency,
 [deps: [:some_dep, {:other_dep, "This fork must stay pinned to a commit sha."}]]}
```

| Param | Default | Meaning |
| --- | --- | --- |
| `deps` | `[]` | Dependency atoms, or `{:dep, "message"}` tuples, that must be pinned. |

### `Trogon.Credo.Check.Warning.PreferredModule`

Flags calls to a module when a drop in replacement should be used instead, for example a wrapper that preserves OpenTelemetry context across a spawned process. Aliases are resolved before comparing, so `alias OpentelemetryProcessPropagator.Task` followed by `Task.async/1` is correctly left alone. Aliases are collected for the whole file rather than per lexical scope.

This is the one check that ships with a non empty default, so a project that does not use OpenTelemetry should override `modules`.

```elixir
{Trogon.Credo.Check.Warning.PreferredModule,
 [modules: [{Logger, MyApp.Logger, "Use MyApp.Logger so request metadata is attached."}]]}
```

| Param | Default | Meaning |
| --- | --- | --- |
| `modules` | the two `OpentelemetryProcessPropagator` pairs | `{Discouraged, Preferred}` or `{Discouraged, Preferred, "message"}` tuples. |

The OpenTelemetry process propagator rule this check generalizes was originally described by David Bernheisel.

### `Trogon.Credo.Check.Readability.MechanicalModuleName`

Flags modules named after the execution mechanism that runs them rather than the domain role they perform. Whether a module runs as a background job or a GenServer is already visible from its `use` line, so restating it in the name is redundant and forces a rename whenever the mechanism changes. The corresponding file name suffix is flagged too, at most once per file.

The default `suffixes` list is deliberately opinionated. Trim it to the conventions you actually want enforced, and set `for_use` to narrow the check to one mechanism.

```elixir
{Trogon.Credo.Check.Readability.MechanicalModuleName,
 [for_use: [Oban.Worker], suffixes: ["Worker"]]}
```

| Param | Default | Meaning |
| --- | --- | --- |
| `for_use` | `[]` | Modules to narrow the check to. Empty means every module in the analyzed files. |
| `suffixes` | `["Worker", "Job", "Manager", "Helper", "Util", "Utils"]` | Mechanical suffixes rejected on the last segment of the module name. |

### `Trogon.Credo.Check.Readability.ModuleLocation`

Flags modules that belong to an architectural layer but do not live where that layer is expected to live. Ships inert, because there is no universal expected location; configure it per project.

```elixir
{Trogon.Credo.Check.Readability.ModuleLocation,
 [for_use: [Oban.Worker], path_segment: "jobs", namespace_segment: :Jobs]}
```

| Param | Default | Meaning |
| --- | --- | --- |
| `for_use` | `[]` | Modules to apply the check to. Empty makes the check inert. |
| `path_segment` | `nil` | Directory name a matching module's file must live under. `nil` skips the check. |
| `namespace_segment` | `nil` | Module name segment that must appear in a matching module's namespace. `nil` skips the check. |

Note that moving or renaming a module referenced by persisted data, such as a background job row naming its worker module, may need a data migration or an alias.
