defmodule TestSupport.Errors do
  defmodule TestError do
    use Trogon.Error,
      domain: "com.test.app",
      reason: "TEST_ERROR",
      message: :unknown
  end

  defmodule InvalidCurrencyError do
    use Trogon.Error,
      domain: "com.test.currency",
      reason: "INVALID_CURRENCY",
      message: :invalid_argument
  end

  defmodule ValidationError do
    use Trogon.Error,
      domain: "com.test.app",
      reason: "VALIDATION_FAILED",
      message: :invalid_argument
  end

  defmodule PreconditionError do
    use Trogon.Error,
      domain: "com.test.app",
      reason: "FAILED_PRECONDITION",
      code: :failed_precondition
  end

  defmodule CompileTimeError do
    use Trogon.Error,
      domain: "com.test.compile",
      reason: "COMPILE_TIME_ERROR",
      code: :not_found,
      message: "This is a compile-time message",
      visibility: :internal
  end

  defmodule CancelledError do
    use Trogon.Error,
      domain: "com.test",
      reason: "CANCELLED_ERROR",
      message: :cancelled
  end

  defmodule NotFoundError do
    use Trogon.Error,
      domain: "com.test",
      reason: "NOT_FOUND_ERROR",
      message: :not_found,
      metadata: %{resource: "user"}
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
end
