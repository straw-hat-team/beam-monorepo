# Trogon.Configurable

**A small Elixir library that gives a module a `get_config/1` function, which merges the module's static defaults, its OTP app environment, and runtime parameters into one keyword list.**

**Each source overrides the one before it, so defaults live next to the code, environments swap values through `Config`, and callers can still adjust a value for a single call.**

## Documentation

### References

- [API Reference](api-reference.html)
