# Trogon.Credo

**Trogon.Credo is a shared library of Credo checks you depend on instead of copy.** It turns the custom check modules that accumulate in a project's `.credo/checks/` directory into a versioned Hex package that many repositories can point at.

**The package ships check modules and Credo plugins that enable them.** Each check lives under the `Trogon.Credo.Check.<Category>.<Name>` namespace, mirroring Credo's own layout, and is built on Credo's public API so a Credo patch release cannot break it. A consumer either enables the checks it wants one by one in its own `.credo.exs`, or adds a plugin under `Trogon.Credo.Plugin` that enables the checks for one library, such as Ecto, in a single line.

**Custom Credo checks have no distribution story of their own.** A check written for one repository gets copied into the next, then the two drift: a false positive fixed in one copy stays broken in the other, and neither version is tested anywhere. Shipping the checks as a dependency gives them a single source, a test suite, and a version number, so a fix reaches every project that upgrades.

**This is for teams running Credo across more than one Elixir repository**, and for anyone who has already written a custom check worth keeping. Checks that encode an architectural convention, such as where a layer's modules must live, are parameterized and ship inert, so the conventions stay in each project's configuration while the code that enforces them stays here.

## How-to

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

### Use a plugin

Add the plugin to the `plugins:` list of the config in your project's `.credo.exs`, with the params it accepts:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [{Trogon.Credo.Plugin.Ecto, [repos: [MyApp.Repo]]}]
    }
  ]
}
```

The plugin enables its checks whether the config lists checks with `enabled:`, `extra:`, or a plain list, and whichever config `--config-name` selects. Each plugin documents the checks it enables and the params it forwards to them in its own module documentation.

To leave one of the plugin's checks out, name it in `except:`:

```elixir
plugins: [{Trogon.Credo.Plugin.Ecto, [except: [Trogon.Credo.Check.Ecto.RepoTransact]]}]
```

To configure one of them differently, list it in `checks:` yourself. Your entry replaces the one the plugin would add, so `{Trogon.Credo.Check.Ecto.RepoTransact, false}` disables it, and a `# credo:disable-for-next-line Trogon.Credo.Check.Ecto.RepoTransact` comment silences a single line.

### Keep tests from writing application env

Add the ExUnit plugin, naming the seam your tests stub instead in `hint:`:

```elixir
plugins: [{Trogon.Credo.Plugin.ExUnit, [hint: "Read config through MyApp.Config and stub it per test."]}]
```

Every `Application.put_env`, `Application.put_all_env`, `Application.delete_env`, `:application.set_env`, and `:application.unset_env` call in a `*_test.exs` file or under `test/support` is reported, since application env is global to the node and a test that writes it changes config for every test running at the same time.

### Read environment variables only in config/runtime.exs

Add the Config plugin, naming your own configuration module in `hint:` if you have one:

```elixir
plugins: [{Trogon.Credo.Plugin.Config, [hint: "Read config through MyApp.Config."]}]
```

Every `System.get_env`, `System.fetch_env`, `System.fetch_env!`, `:os.getenv`, and `:os.env` call outside `config/runtime.exs` is reported, since a read anywhere else happens at compile time or scatters configuration across the code base. Read the variable once in `config/runtime.exs` and hand it to the rest of the project through application config. Credo does not analyze `config/` by default, so in practice the check reports reads under `lib` and `test`. If you add `mix.exs` to the analyzed files, list it in `allowed_files:` as a `{path, reason}` tuple, `allowed_files: [{"config/runtime.exs", "Read once at boot."}, {"mix.exs", "The Mix project file runs at compile time by design."}]`. The reason is required and non-blank, so whoever reads `.credo.exs` learns why each file may read the environment, and a bare path raises `ArgumentError`. Replacing the default drops `config/runtime.exs`, so list it again to keep it allowed.

## References

Every check documents what it flags and the parameters it accepts in its own
module documentation, so the two never drift apart. Browse them under
`Trogon.Credo.Check` in the [published documentation](https://hexdocs.pm/trogon_credo),
or read one from a project that already depends on the package:

```console
$ mix credo explain Trogon.Credo.Check.Warning.ForbiddenImport
```
