# Trogon.Configurable

**Trogon.Configurable gives an Elixir module one place to read its configuration from.** A single `use` line adds a `get_config/1` function that returns a keyword list.

**The function merges three sources, where each one overrides the one before it.** The defaults passed to `use` come first, then the module's entry in its OTP app environment when an `otp_app` is given, and finally the options passed to `get_config/1` at the call site.

**Modules that read configuration from more than one place tend to reimplement the same merge, each with its own precedence.** One module lets the call site win, another lets the environment win, and a value that works in one place silently loses in the next. Fixing the precedence in one package keeps defaults next to the code, lets each environment swap values through `Config`, and still lets a caller adjust a value for a single call.

**This is for Elixir developers writing libraries or application modules that need sensible defaults which an application, or a single call, can override.** Clients for external services, adapters, and workers that read endpoints, timeouts, or credentials are typical examples.

## Documentation

### References

- [API Reference](api-reference.html)
