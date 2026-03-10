# Trogon.ExunitReporter

An ExUnit formatter that writes a token-optimized test report for AI coding agents.

## Design Principles

- **Silent on success** — passing tests produce zero output, only the summary line
- **Dense on failure** — assertion code, left/right values, error message, trimmed stacktrace
- **Runs alongside the CLI formatter** — humans see normal terminal output, agents read the file
- **Plain text** — no JSON overhead, LLMs parse text natively

## Installation

Add `trogon_exunit_reporter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trogon_exunit_reporter, "~> 0.1.0", only: :test}
  ]
end
```

## Usage

Add the reporter alongside the default CLI formatter in `test/test_helper.exs`:

```elixir
ExUnit.configure(
  formatters: [ExUnit.CLIFormatter, Trogon.ExunitReporter]
)

ExUnit.start()
```

After running `mix test`, the agent reads `test-report.txt`.

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `file_path` | `String.t()` | `"test-report.txt"` | Output file path |
| `include_logs` | `boolean()` | `true` | Include captured logs in failure output |

```elixir
ExUnit.configure(
  formatters: [ExUnit.CLIFormatter, Trogon.ExunitReporter],
  trogon_exunit_reporter: [
    file_path: "test-report.txt",
    include_logs: true
  ]
)
```

## Output Format

When all tests pass — one line:

```
ALL PASSED | 42 tests, 42 passed | 150ms
```

When tests fail — only failures appear, followed by the summary:

```
FAIL test this assertion fails (ExampleFailingTest)
  test/example_test.exs:19
  ** (error)
  message: Assertion with == failed
  code:    assert [1, 2, 3] == [1, 2, 4]
  left:    [1, 2, 3]
  right:   [1, 2, 4]
  stacktrace:
    test/example_test.exs:20 ExampleFailingTest.test this assertion fails/1

FAIL test runtime error (ExampleFailingTest)
  test/example_test.exs:22
  ** (error)
  something broke
  stacktrace:
    test/example_test.exs:23 ExampleFailingTest.test runtime error/1

FAILURES | 5 tests, 2 passed, 2 failed, 1 skipped | 5ms
```
