defmodule Trogon.ExunitReporter.Config do
  @moduledoc """
  Configuration parsing and validation for the ExUnit AI agent reporter.
  """

  @schema NimbleOptions.new!(
            file_path: [
              type: :string,
              default: "test-report.txt",
              doc: "File path for the test report."
            ],
            include_logs: [
              type: :boolean,
              default: true,
              doc: "Whether to include captured log output in failure details."
            ]
          )

  @type t :: %__MODULE__{
          file_path: String.t(),
          include_logs: boolean()
        }

  @enforce_keys [:file_path, :include_logs]
  defstruct [:file_path, :include_logs]

  @doc """
  Builds a `%Config{}` from the ExUnit options map.

  Extracts the `:trogon_exunit_reporter` key, validates it against the schema,
  and returns a config struct.
  """
  @spec from_exunit_opts(keyword()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def from_exunit_opts(exunit_opts) do
    opts = Keyword.get(exunit_opts, :trogon_exunit_reporter, [])

    case NimbleOptions.validate(opts, @schema) do
      {:ok, validated} -> {:ok, struct!(__MODULE__, validated)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Same as `from_exunit_opts/1` but raises on invalid configuration.
  """
  @spec from_exunit_opts!(keyword()) :: t()
  def from_exunit_opts!(exunit_opts) do
    opts = Keyword.get(exunit_opts, :trogon_exunit_reporter, [])
    validated = NimbleOptions.validate!(opts, @schema)
    struct!(__MODULE__, validated)
  end
end
