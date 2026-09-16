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
    {:trogon_credo, "~> 0.0.1", only: [:dev, :test], runtime: false}
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

Every check documents what it flags and the parameters it accepts in its own
module documentation, so the two never drift apart. Browse them under
`Trogon.Credo.Check` in the [published documentation](https://hexdocs.pm/trogon_credo),
or read one from a project that already depends on the package:

```console
$ mix credo explain Trogon.Credo.Check.Warning.ForbiddenImport
```
