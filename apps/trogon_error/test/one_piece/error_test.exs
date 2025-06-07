defmodule Trogon.ErrorTest do
  use ExUnit.Case, async: true
  doctest Trogon.Error

  # Define test error modules
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

  defmodule CompileTimeError do
    use Trogon.Error,
      domain: "com.test.compile",
      reason: "COMPILE_TIME_ERROR",
      code: :not_found,
      message: "This is a compile-time message",
      visibility: :internal
  end

  describe "basic error creation" do
    test "creates error with default values" do
      error = TestError.exception()

      assert error.__exception__ == true
      assert error.specversion == 1
      assert error.code == :unknown
      assert error.message == "unknown error"
      assert error.info.domain == "com.test.app"
      assert error.info.reason == "TEST_ERROR"
      assert error.info.metadata == %{}
      assert error.causes == []
      assert error.visibility == :internal
      assert is_nil(error.source)
      assert is_nil(error.indeterministic_info)
    end

    test "creates error with custom values" do
      error =
        TestError.exception(
          code: :not_found,
          message: "User {user_id} not found",
          metadata: %{user_id: "123"},
          visibility: :internal
        )

      assert error.code == :not_found
      assert error.message == "User {user_id} not found"
      assert error.info.metadata == %{user_id: "123"}
      assert error.visibility == :internal
    end

    test "both exception/1 and new!/1 work identically" do
      opts = [code: :not_found, message: "Test error", metadata: %{key: "value"}]

      error1 = TestError.exception(opts)
      error2 = TestError.new!(opts)

      assert error1 == error2
      assert error1.code == :not_found
      assert error1.message == "Test error"
      assert error1.info.metadata == %{key: "value"}
    end
  end

  describe "error codes" do
    test "converts atom messages to strings at compile time" do
      # Test a few examples of compile-time atom to string conversion
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
          message: :not_found
      end

      cancelled_error = CancelledError.exception()
      assert cancelled_error.message == "the operation was cancelled"

      not_found_error = NotFoundError.exception()
      assert not_found_error.message == "resource not found"
    end

    test "uses string messages directly at compile time" do
      defmodule CustomMessageError do
        use Trogon.Error,
          domain: "com.test",
          reason: "CUSTOM_MESSAGE_ERROR",
          message: "This is a custom string message"
      end

      error = CustomMessageError.exception()
      assert error.message == "This is a custom string message"
    end
  end

  describe "validation errors" do
    test "creates error with subject" do
      error =
        InvalidCurrencyError.exception(
          code: :invalid_argument,
          source: %{subject: "/data/currency"},
          metadata: %{valid_currencies: ["USD", "EUR"]}
        )

      assert error.source == %{subject: "/data/currency"}
      assert error.info.metadata == %{valid_currencies: ["USD", "EUR"]}
    end

    test "wraps multiple validation errors" do
      currency_error =
        InvalidCurrencyError.exception(
          source: %{subject: "/data/currency"},
          metadata: %{valid_currencies: ["USD"]}
        )

      validation_error =
        ValidationError.exception(
          code: :invalid_argument,
          causes: [currency_error]
        )

      assert length(validation_error.causes) == 1
      assert hd(validation_error.causes).source.subject == "/data/currency"
    end

    test "validation errors creates error with subject" do
      error =
        ValidationError.exception(
          source: %{subject: "/data/currency"},
          metadata: %{valid_currencies: ["USD", "EUR"]}
        )

      assert error.source == %{subject: "/data/currency"}
      assert error.info.domain == "com.test.app"
      assert error.info.reason == "VALIDATION_FAILED"
      assert error.info.metadata == %{valid_currencies: ["USD", "EUR"]}
    end
  end

  describe "error wrapping" do
    test "wraps an error as a cause" do
      original_error = TestError.exception(code: :not_found)

      wrapped_error =
        ValidationError.exception(
          code: :failed_precondition,
          message: "Precondition check failed",
          causes: [original_error]
        )

      assert wrapped_error.code == :failed_precondition
      assert wrapped_error.message == "Precondition check failed"
      assert length(wrapped_error.causes) == 1
      assert hd(wrapped_error.causes) == original_error
    end
  end

  describe "optional fields" do
    test "creates error with all optional fields" do
      error =
        TestError.exception(
          code: :unavailable,
          help: %{
            links: [
              %{description: "Status Page", url: "https://status.example.com"}
            ]
          },
          localized_message: %{locale: "fr-CA", message: "Service non disponible"},
          retry_info: %{retry_delay: Duration.new!(second: 60)},
          debug_info: %{
            stack_entries: ["line 1", "line 2"],
            metadata: %{"request_id" => "abc123"}
          }
        )

      assert error.help.links == [%{description: "Status Page", url: "https://status.example.com"}]
      assert error.localized_message == %{locale: "fr-CA", message: "Service non disponible"}
      assert error.retry_info.retry_delay == Duration.new!(second: 60)
      assert error.debug_info.metadata == %{"request_id" => "abc123"}
    end
  end

  describe "compile-time options" do
    test "uses compile-time defaults" do
      error = CompileTimeError.exception()

      assert error.code == :not_found
      assert error.message == "This is a compile-time message"
      assert error.visibility == :internal
    end

    test "runtime options override compile-time defaults" do
      error =
        CompileTimeError.exception(
          code: :invalid_argument,
          message: "Runtime message overrides compile-time",
          visibility: :public
        )

      assert error.code == :invalid_argument
      assert error.message == "Runtime message overrides compile-time"
      assert error.visibility == :public
    end
  end

  describe "raising exceptions" do
    test "raises error with default values" do
      assert_raise TestError, fn ->
        raise TestError
      end
    end

    test "raises error with metadata" do
      assert_raise TestError, fn ->
        raise TestError, metadata: %{request_id: "abc123"}
      end
    end

    test "raises error with runtime options" do
      try do
        raise TestError,
          metadata: %{user_id: "123"},
          source: %{subject: "/users/123"}
      rescue
        error in TestError ->
          # compile-time default
          assert error.code == :unknown
          # compile-time default
          assert error.message == "unknown error"
          assert error.info.metadata == %{user_id: "123"}
          assert error.source == %{subject: "/users/123"}
          assert error.info.domain == "com.test.app"
          assert error.info.reason == "TEST_ERROR"
      end
    end

    test "raises validation error with source" do
      try do
        raise InvalidCurrencyError,
          source: %{subject: "/data/currency"},
          metadata: %{valid_currencies: ["USD", "EUR"]}
      rescue
        error in InvalidCurrencyError ->
          # compile-time default (no code specified)
          assert error.code == :unknown
          # from :invalid_argument atom
          assert error.message == "invalid argument provided"
          assert error.source == %{subject: "/data/currency"}
          assert error.info.metadata == %{valid_currencies: ["USD", "EUR"]}
          assert error.info.domain == "com.test.currency"
          assert error.info.reason == "INVALID_CURRENCY"
      end
    end

    test "raises error with causes" do
      original_error = TestError.exception(metadata: %{user_id: "123"})

      try do
        raise ValidationError,
          causes: [original_error],
          metadata: %{validation_context: "user_creation"}
      rescue
        error in ValidationError ->
          # compile-time default (no code specified)
          assert error.code == :unknown
          # from :invalid_argument atom
          assert error.message == "invalid argument provided"
          assert error.info.metadata == %{validation_context: "user_creation"}
          assert length(error.causes) == 1
          assert hd(error.causes) == original_error
      end
    end

    test "raises error with debug info" do
      assert_raise TestError, fn ->
        raise TestError,
          debug_info: %{
            stack_entries: ["line 1", "line 2"],
            metadata: %{"request_id" => "abc123"}
          }
      end
    end

    test "can re-raise caught exception" do
      original_error = TestError.exception(code: :unavailable, message: "Service unavailable")

      assert_raise TestError, fn ->
        raise original_error
      end
    end

    test "preserves runtime error properties when raising" do
      try do
        raise TestError,
          metadata: %{user_id: "123", context: "login"},
          source: %{subject: "/auth/login"},
          retry_info: %{retry_delay: Duration.new!(second: 30)},
          localized_message: %{locale: "en-US", message: "Login failed"}
      rescue
        error in TestError ->
          # compile-time default
          assert error.code == :unknown
          # compile-time default
          assert error.message == "unknown error"
          # compile-time default
          assert error.visibility == :internal
          assert error.info.metadata == %{user_id: "123", context: "login"}
          assert error.source == %{subject: "/auth/login"}
          assert error.retry_info.retry_delay == Duration.new!(second: 30)
          assert error.localized_message == %{locale: "en-US", message: "Login failed"}
          assert error.specversion == 1
      end
    end
  end

  describe "NimbleOptions validation" do
    test "validates required fields" do
      assert_raise NimbleOptions.ValidationError, ~r/required :domain option not found/, fn ->
        defmodule MissingDomainError do
          use Trogon.Error,
            reason: "MISSING_DOMAIN",
            message: "Missing domain"
        end
      end
    end

    test "validates invalid code values" do
      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :code option/, fn ->
        defmodule InvalidCodeError do
          use Trogon.Error,
            domain: "com.test",
            reason: "INVALID_CODE",
            message: "Invalid code",
            code: :invalid_code_value
        end
      end
    end

    test "validates invalid visibility values" do
      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :visibility option/, fn ->
        defmodule InvalidVisibilityError do
          use Trogon.Error,
            domain: "com.test",
            reason: "INVALID_VISIBILITY",
            message: "Invalid visibility",
            visibility: :invalid_visibility
        end
      end
    end

    test "validates message type" do
      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :message option/, fn ->
        defmodule InvalidMessageError do
          use Trogon.Error,
            domain: "com.test",
            reason: "INVALID_MESSAGE",
            # Should be atom or string
            message: 123
        end
      end
    end
  end
end
