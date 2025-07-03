defmodule Trogon.Error.TestSupport do
  import Trogon.Error, only: [is_trogon_error?: 1]

  defmodule TestError do
    use Trogon.Error,
      domain: "com.test.app",
      reason: "TEST_ERROR",
      message: :UNKNOWN
  end

  defmodule InvalidCurrencyError do
    use Trogon.Error,
      domain: "com.test.currency",
      reason: "INVALID_CURRENCY",
      message: :INVALID_ARGUMENT
  end

  defmodule ValidationError do
    use Trogon.Error,
      domain: "com.test.app",
      reason: "VALIDATION_FAILED",
      message: :INVALID_ARGUMENT
  end

  defmodule PreconditionError do
    use Trogon.Error,
      domain: "com.test.app",
      reason: "FAILED_PRECONDITION",
      code: :FAILED_PRECONDITION
  end

  defmodule CompileTimeError do
    use Trogon.Error,
      domain: "com.test.compile",
      reason: "COMPILE_TIME_ERROR",
      code: :NOT_FOUND,
      message: "This is a compile-time message",
      visibility: :INTERNAL
  end

  defmodule CancelledError do
    use Trogon.Error,
      domain: "com.test",
      reason: "CANCELLED_ERROR",
      message: :CANCELLED
  end

  defmodule NotFoundError do
    use Trogon.Error,
      domain: "com.test",
      reason: "NOT_FOUND_ERROR",
      message: :NOT_FOUND,
      metadata: %{"resource" => "user"}
  end

  defmodule CustomMessageError do
    use Trogon.Error,
      domain: "com.test",
      reason: "CUSTOM_MESSAGE_ERROR",
      message: "This is a custom string message"
  end

  defmodule HelpfulError do
    use Trogon.Error,
      domain: "com.test.help",
      reason: "HELPFUL_ERROR",
      message: "helpful error",
      help: %{
        links: [
          %{description: "API Docs", url: "https://example.com/docs"}
        ]
      }
  end

  defmodule ValidTupleMetadataError do
    use Trogon.Error,
      domain: "com.test",
      reason: "VALID_TUPLE_METADATA",
      message: "Valid tuple metadata",
      metadata: %{
        "simple" => "value",
        "with_visibility" => {"secret", :PRIVATE}
      }
  end

  def trogon_error?(error) when is_trogon_error?(error), do: true
  def trogon_error?(_), do: false

  defmodule MetadataTestGuards do
    @moduledoc """
    Test module for demonstrating guard usage with Metadata.is_empty_metadata/1
    """

    import Trogon.Error.Metadata, only: [is_empty_metadata: 1]

    def test_empty(metadata) when is_empty_metadata(metadata), do: :empty
    def test_empty(_metadata), do: :not_empty
  end
end
