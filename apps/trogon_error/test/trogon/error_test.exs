defmodule Trogon.ErrorTest do
  alias Trogon.Error.TestSupport

  use ExUnit.Case, async: true
  doctest Trogon.Error

  test "creates error with default values" do
    error = TestSupport.TestError.new!()
    assert error.__exception__ == true
    assert error.specversion == 1
    assert error.code == :unknown
    assert error.message == "unknown error"
    assert error.domain == "com.test.app"
    assert error.reason == "TEST_ERROR"
    assert error.metadata == %{}
    assert error.causes == []
    assert error.visibility == :internal
    refute error.subject
    refute error.id
    refute error.time
  end

  test "creates error with custom values" do
    error = TestSupport.TestError.new!(metadata: %{user_id: "123"})
    assert error.code == :unknown
    assert error.metadata == %{user_id: "123"}
    assert error.visibility == :internal
  end

  test "both exception/1 and new!/1 work identically" do
    opts = [metadata: %{key: "value"}]
    error1 = TestSupport.TestError.exception(opts)
    error2 = TestSupport.TestError.new!(opts)
    assert error1 == error2
    assert error1.code == :unknown
    assert error1.message == "unknown error"
    assert error1.metadata == %{key: "value"}
  end

  test "converts atom messages to strings at compile time" do
    cancelled_error = TestSupport.CancelledError.new!()
    assert cancelled_error.message == "the operation was cancelled"
    not_found_error = TestSupport.NotFoundError.new!(metadata: %{resource_id: "user:123"})
    assert not_found_error.message == "resource not found"
    assert not_found_error.metadata == %{resource: "user", resource_id: "user:123"}
  end

  test "uses string messages directly at compile time" do
    error = TestSupport.CustomMessageError.new!()
    assert error.message == "This is a custom string message"
  end

  test "creates validation error with subject" do
    error =
      TestSupport.ValidationError.new!(
        subject: "/data/currency",
        metadata: %{valid_currencies: ["USD", "EUR"]}
      )

    assert error.subject == "/data/currency"
    assert error.domain == "com.test.app"
    assert error.reason == "VALIDATION_FAILED"
    assert error.metadata == %{valid_currencies: ["USD", "EUR"]}
  end

  test "wraps causes in a validation error" do
    currency_error =
      TestSupport.InvalidCurrencyError.new!(
        subject: "/data/currency",
        metadata: %{valid_currencies: ["USD"]}
      )

    test_error = TestSupport.TestError.new!()

    validation_error =
      TestSupport.ValidationError.new!(
        code: :invalid_argument,
        causes: [currency_error, test_error]
      )

    assert length(validation_error.causes) == 2
    assert hd(validation_error.causes) == currency_error
    assert hd(tl(validation_error.causes)) == test_error
    assert hd(validation_error.causes).subject == "/data/currency"
  end

  test "wraps an error as a cause" do
    original_error = TestSupport.TestError.new!(code: :not_found)
    wrapped_error = TestSupport.PreconditionError.new!(causes: [original_error])
    assert wrapped_error.code == :failed_precondition
    assert wrapped_error.message == "failed precondition"
    assert length(wrapped_error.causes) == 1
    assert hd(wrapped_error.causes) == original_error
  end

  test "creates error with all optional fields" do
    time = DateTime.utc_now()

    error =
      TestSupport.TestError.new!(
        id: "err-123",
        time: time,
        source_id: "instance-abc",
        localized_message: %{locale: "fr-CA", message: "Service non disponible"},
        retry_info: %{retry_offset: Duration.new!(second: 60)},
        debug_info: %{
          stack_entries: ["line 1", "line 2"],
          metadata: %{"request_id" => "abc123"}
        }
      )

    assert error.id == "err-123"
    assert error.time == time
    assert error.source_id == "instance-abc"
    assert error.localized_message == %{locale: "fr-CA", message: "Service non disponible"}
    assert error.retry_info.retry_offset == Duration.new!(second: 60)
    assert error.debug_info.metadata == %{"request_id" => "abc123"}
  end

  test "uses compile-time defaults" do
    error = TestSupport.CompileTimeError.new!()
    assert error.code == :not_found
    assert error.message == "This is a compile-time message"
    assert error.visibility == :internal
  end

  test "uses compile-time help option" do
    error = TestSupport.HelpfulError.new!()

    assert error.help == %{
             links: [
               %{description: "API Docs", url: "https://example.com/docs"}
             ]
           }
  end

  test "raises error with default values" do
    assert_raise TestSupport.TestError, fn ->
      raise TestSupport.TestError
    end
  end

  test "raises error with metadata" do
    assert_raise TestSupport.TestError, fn ->
      raise TestSupport.TestError, metadata: %{request_id: "abc123"}
    end
  end

  test "raises error with runtime options" do
    try do
      raise TestSupport.TestError,
        metadata: %{user_id: "123"},
        subject: "/users/123"
    rescue
      error in TestSupport.TestError ->
        assert error.code == :unknown
        assert error.message == "unknown error"
        assert error.metadata == %{user_id: "123"}
        assert error.subject == "/users/123"
        assert error.domain == "com.test.app"
        assert error.reason == "TEST_ERROR"
    end
  end

  test "raises validation error with subject" do
    try do
      raise TestSupport.InvalidCurrencyError,
        subject: "/data/currency",
        metadata: %{valid_currencies: ["USD", "EUR"]}
    rescue
      error in TestSupport.InvalidCurrencyError ->
        assert error.code == :unknown
        assert error.message == "invalid argument provided"
        assert error.subject == "/data/currency"
        assert error.metadata == %{valid_currencies: ["USD", "EUR"]}
        assert error.domain == "com.test.currency"
        assert error.reason == "INVALID_CURRENCY"
    end
  end

  test "raises error with causes" do
    original_error = TestSupport.TestError.new!(metadata: %{user_id: "123"})

    try do
      raise TestSupport.ValidationError,
        causes: [original_error],
        metadata: %{validation_context: "user_creation"}
    rescue
      error in TestSupport.ValidationError ->
        assert error.code == :unknown
        assert error.message == "invalid argument provided"
        assert error.metadata == %{validation_context: "user_creation"}
        assert length(error.causes) == 1
        assert hd(error.causes) == original_error
    end
  end

  test "raises error with debug info" do
    assert_raise TestSupport.TestError, fn ->
      raise TestSupport.TestError,
        debug_info: %{
          stack_entries: ["line 1", "line 2"],
          metadata: %{"request_id" => "abc123"}
        }
    end
  end

  test "can re-raise caught exception" do
    original_error = TestSupport.TestError.new!()

    assert_raise TestSupport.TestError, fn ->
      raise original_error
    end
  end

  test "preserves runtime error properties when raising" do
    try do
      raise TestSupport.TestError,
        metadata: %{user_id: "123", context: "login"},
        subject: "/auth/login",
        retry_info: %{retry_offset: Duration.new!(second: 30)},
        localized_message: %{locale: "en-US", message: "Login failed"}
    rescue
      error in TestSupport.TestError ->
        assert error.code == :unknown
        assert error.message == "unknown error"
        assert error.visibility == :internal
        assert error.metadata == %{user_id: "123", context: "login"}
        assert error.subject == "/auth/login"
        assert error.retry_info.retry_offset == Duration.new!(second: 30)
        assert error.localized_message == %{locale: "en-US", message: "Login failed"}
        assert error.specversion == 1
    end
  end

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
          message: 123
      end
    end
  end

  describe "to_msg/1" do
    test "converts error atom or string to string" do
      assert Trogon.Error.to_msg("random message") == "random message"
      assert Trogon.Error.to_msg(:cancelled) == "the operation was cancelled"
      assert Trogon.Error.to_msg(:unknown) == "unknown error"
      assert Trogon.Error.to_msg(:invalid_argument) == "invalid argument provided"
      assert Trogon.Error.to_msg(:deadline_exceeded) == "deadline exceeded"
      assert Trogon.Error.to_msg(:not_found) == "resource not found"
      assert Trogon.Error.to_msg(:already_exists) == "resource already exists"
      assert Trogon.Error.to_msg(:permission_denied) == "permission denied"
      assert Trogon.Error.to_msg(:resource_exhausted) == "resource exhausted"
      assert Trogon.Error.to_msg(:failed_precondition) == "failed precondition"
      assert Trogon.Error.to_msg(:aborted) == "operation aborted"
      assert Trogon.Error.to_msg(:out_of_range) == "out of range"
      assert Trogon.Error.to_msg(:unimplemented) == "not implemented"
      assert Trogon.Error.to_msg(:internal) == "internal error"
      assert Trogon.Error.to_msg(:unavailable) == "service unavailable"
      assert Trogon.Error.to_msg(:data_loss) == "data loss or corruption"
      assert Trogon.Error.to_msg(:unauthenticated) == "unauthenticated"
    end
  end

  describe "to_code_int/1" do
    test "converts code atom or error struct to integer" do
      assert Trogon.Error.to_code_int(:cancelled) == 1
      assert Trogon.Error.to_code_int(:unknown) == 2
      assert Trogon.Error.to_code_int(:invalid_argument) == 3
      assert Trogon.Error.to_code_int(:deadline_exceeded) == 4
      assert Trogon.Error.to_code_int(:not_found) == 5
      assert Trogon.Error.to_code_int(:already_exists) == 6
      assert Trogon.Error.to_code_int(:permission_denied) == 7
      assert Trogon.Error.to_code_int(:resource_exhausted) == 8
      assert Trogon.Error.to_code_int(:failed_precondition) == 9
      assert Trogon.Error.to_code_int(:aborted) == 10
      assert Trogon.Error.to_code_int(:out_of_range) == 11
      assert Trogon.Error.to_code_int(:unimplemented) == 12
      assert Trogon.Error.to_code_int(:internal) == 13
      assert Trogon.Error.to_code_int(:unavailable) == 14
      assert Trogon.Error.to_code_int(:data_loss) == 15
      assert Trogon.Error.to_code_int(:unauthenticated) == 16
      error = TestSupport.CompileTimeError.new!()
      assert Trogon.Error.to_code_int(error) == 5
    end
  end

  describe "message/1" do
    test "formats the error message" do
      error = TestSupport.HelpfulError.new!(source_id: "")

      assert Exception.message(error) == """
             helpful error
               visibility: :internal
               domain: com.test.help
               reason: HELPFUL_ERROR
               code: :unknown
             - API Docs: https://example.com/docs\
             """

      error = TestSupport.TestError.new!(metadata: %{user_id: "123"})

      assert Exception.message(error) == """
             unknown error
               visibility: :internal
               domain: com.test.app
               reason: TEST_ERROR
               code: :unknown
               metadata: %{user_id: "123"}\
             """
    end
  end

  describe "is_trogon_error?/1" do
    test "returns true for Trogon errors" do
      error = TestSupport.TestError.new!()
      assert TestSupport.trogon_error?(error)
      refute TestSupport.trogon_error?(%{})
      refute TestSupport.trogon_error?(:something_went_wrong)
    end
  end
end
