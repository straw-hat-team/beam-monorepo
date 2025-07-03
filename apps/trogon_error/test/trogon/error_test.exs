defmodule Trogon.ErrorTest do
  alias Trogon.Error.TestSupport
  alias Trogon.Error.{Metadata, MetadataValue}

  use ExUnit.Case, async: true
  doctest Trogon.Error

  test "creates error with default values" do
    error = TestSupport.TestError.new!()
    assert error.__exception__ == true
    assert error.specversion == 1
    assert error.code == :UNKNOWN
    assert error.message == "unknown error"
    assert error.domain == "com.test.app"
    assert error.reason == "TEST_ERROR"
    assert error.metadata == %Trogon.Error.Metadata{entries: %{}}
    assert error.causes == []
    assert error.visibility == :INTERNAL
    refute error.subject
    refute error.id
    refute error.time
  end

  test "creates error with custom values" do
    error = TestSupport.TestError.new!(metadata: Metadata.new(%{user_id: "123"}))
    assert error.code == :UNKNOWN
    assert error.metadata == %Metadata{entries: %{"user_id" => %MetadataValue{value: "123", visibility: :INTERNAL}}}
    assert error.visibility == :INTERNAL
  end

  test "both exception/1 and new!/1 work identically" do
    opts = [metadata: Metadata.new(%{key: "value"})]
    error1 = TestSupport.TestError.exception(opts)
    error2 = TestSupport.TestError.new!(opts)
    assert error1 == error2
    assert error1.code == :UNKNOWN
    assert error1.message == "unknown error"
    assert error1.metadata == %Metadata{entries: %{"key" => %MetadataValue{value: "value", visibility: :INTERNAL}}}
  end

  test "converts atom messages to strings at compile time" do
    cancelled_error = TestSupport.CancelledError.new!()
    assert cancelled_error.message == "the operation was cancelled"
    not_found_error = TestSupport.NotFoundError.new!(metadata: Metadata.new(%{resource_id: "user:123"}))
    assert not_found_error.message == "resource not found"

    assert not_found_error.metadata ==
             %Metadata{
               entries: %{
                 "resource" => %MetadataValue{value: "user", visibility: :INTERNAL},
                 "resource_id" => %MetadataValue{value: "user:123", visibility: :INTERNAL}
               }
             }
  end

  test "uses string messages directly at compile time" do
    error = TestSupport.CustomMessageError.new!()
    assert error.message == "This is a custom string message"
  end

  test "creates validation error with subject" do
    error =
      TestSupport.ValidationError.new!(
        subject: "/data/currency",
        metadata: Metadata.new(%{valid_currencies: "[\"USD\", \"EUR\"]"})
      )

    assert error.subject == "/data/currency"
    assert error.domain == "com.test.app"
    assert error.reason == "VALIDATION_FAILED"

    assert error.metadata ==
             %Metadata{
               entries: %{
                 "valid_currencies" => %MetadataValue{value: "[\"USD\", \"EUR\"]", visibility: :INTERNAL}
               }
             }
  end

  test "wraps causes in a validation error" do
    currency_error =
      TestSupport.InvalidCurrencyError.new!(
        subject: "/data/currency",
        metadata: Metadata.new(%{valid_currencies: "[\"USD\"]"})
      )

    test_error = TestSupport.TestError.new!()

    validation_error =
      TestSupport.ValidationError.new!(
        code: :INVALID_ARGUMENT,
        causes: [currency_error, test_error]
      )

    assert length(validation_error.causes) == 2
    assert hd(validation_error.causes) == currency_error
    assert hd(tl(validation_error.causes)) == test_error
    assert hd(validation_error.causes).subject == "/data/currency"
  end

  test "wraps an error as a cause" do
    original_error = TestSupport.TestError.new!(code: :NOT_FOUND)
    wrapped_error = TestSupport.PreconditionError.new!(causes: [original_error])
    assert wrapped_error.code == :FAILED_PRECONDITION
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
          detail: "Request processing failed at validation step"
        }
      )

    assert error.id == "err-123"
    assert error.time == time
    assert error.source_id == "instance-abc"
    assert error.localized_message == %{locale: "fr-CA", message: "Service non disponible"}
    assert error.retry_info.retry_offset == Duration.new!(second: 60)
    assert error.debug_info.detail == "Request processing failed at validation step"
  end

  test "uses compile-time defaults" do
    error = TestSupport.CompileTimeError.new!()
    assert error.code == :NOT_FOUND
    assert error.message == "This is a compile-time message"
    assert error.visibility == :INTERNAL
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
      raise TestSupport.TestError, metadata: Metadata.new(%{request_id: "abc123"})
    end
  end

  test "raises error with runtime options" do
    try do
      raise TestSupport.TestError,
        metadata: Metadata.new(%{user_id: "123"}),
        subject: "/users/123"
    rescue
      error in TestSupport.TestError ->
        assert error.code == :UNKNOWN
        assert error.message == "unknown error"
        assert error.metadata == %Metadata{entries: %{"user_id" => %MetadataValue{value: "123", visibility: :INTERNAL}}}
        assert error.subject == "/users/123"
        assert error.domain == "com.test.app"
        assert error.reason == "TEST_ERROR"
    end
  end

  test "raises validation error with subject" do
    try do
      raise TestSupport.InvalidCurrencyError,
        subject: "/data/currency",
        metadata: Metadata.new(%{valid_currencies: ~s(["USD", "EUR"])})
    rescue
      error in TestSupport.InvalidCurrencyError ->
        assert error.code == :UNKNOWN
        assert error.message == "invalid argument provided"
        assert error.subject == "/data/currency"

        assert error.metadata ==
                 %Metadata{
                   entries: %{
                     "valid_currencies" => %MetadataValue{value: ~s(["USD", "EUR"]), visibility: :INTERNAL}
                   }
                 }

        assert error.domain == "com.test.currency"
        assert error.reason == "INVALID_CURRENCY"
    end
  end

  test "raises error with causes" do
    original_error = TestSupport.TestError.new!(metadata: Metadata.new(%{user_id: "123"}))

    try do
      raise TestSupport.ValidationError,
        causes: [original_error],
        metadata: Metadata.new(%{validation_context: "user_creation"})
    rescue
      error in TestSupport.ValidationError ->
        assert error.code == :UNKNOWN
        assert error.message == "invalid argument provided"

        assert error.metadata ==
                 %Metadata{
                   entries: %{
                     "validation_context" => %MetadataValue{value: "user_creation", visibility: :INTERNAL}
                   }
                 }

        assert length(error.causes) == 1
        assert hd(error.causes) == original_error
    end
  end

  test "raises error with debug info" do
    assert_raise TestSupport.TestError, fn ->
      raise TestSupport.TestError,
        debug_info: %{
          stack_entries: ["line 1", "line 2"],
          detail: "Request processing failed at validation step"
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
        metadata: Metadata.new(%{user_id: "123", context: "login"}),
        subject: "/auth/login",
        retry_info: %{retry_offset: Duration.new!(second: 30)},
        localized_message: %{locale: "en-US", message: "Login failed"}
    rescue
      error in TestSupport.TestError ->
        assert error.code == :UNKNOWN
        assert error.message == "unknown error"
        assert error.visibility == :INTERNAL

        assert error.metadata ==
                 %Metadata{
                   entries: %{
                     "user_id" => %MetadataValue{value: "123", visibility: :INTERNAL},
                     "context" => %MetadataValue{value: "login", visibility: :INTERNAL}
                   }
                 }

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

  test "validates metadata type" do
    assert_raise NimbleOptions.ValidationError, ~r/invalid value for :metadata option/, fn ->
      defmodule InvalidMetadataError do
        use Trogon.Error,
          domain: "com.test",
          reason: "INVALID_METADATA",
          message: "Invalid metadata",
          metadata: "not a map"
      end
    end
  end

  test "validates metadata key types" do
    assert_raise NimbleOptions.ValidationError,
                 ~r/invalid map in :metadata option.*expected string, got: :atom_key/,
                 fn ->
                   defmodule InvalidMetadataKeyError do
                     use Trogon.Error,
                       domain: "com.test",
                       reason: "INVALID_METADATA_KEY",
                       message: "Invalid metadata key",
                       metadata: %{atom_key: "value"}
                   end
                 end
  end

  test "validates metadata value types" do
    assert_raise NimbleOptions.ValidationError, ~r/invalid value for map key "key": expected.*got: 123/, fn ->
      defmodule InvalidMetadataValueError do
        use Trogon.Error,
          domain: "com.test",
          reason: "INVALID_METADATA_VALUE",
          message: "Invalid metadata value",
          metadata: %{"key" => 123}
      end
    end
  end

  test "validates tuple format visibility values" do
    assert_raise NimbleOptions.ValidationError,
                 ~r/expected one of \[:INTERNAL, :PRIVATE, :PUBLIC\], got: :invalid_visibility/,
                 fn ->
                   defmodule InvalidTupleVisibilityError do
                     use Trogon.Error,
                       domain: "com.test",
                       reason: "INVALID_TUPLE_VISIBILITY",
                       message: "Invalid tuple visibility",
                       metadata: %{"key" => {"value", :invalid_visibility}}
                   end
                 end
  end

  test "accepts valid metadata with simple values" do
    error = TestSupport.NotFoundError.new!()
    assert error.metadata["resource"].visibility == :INTERNAL
    assert error.metadata["resource"].value == "user"

    error_with_runtime = TestSupport.TestError.new!(metadata: Metadata.new(%{user_id: "123", action: "login"}))
    assert error_with_runtime.metadata["user_id"].visibility == :INTERNAL
    assert error_with_runtime.metadata["action"].visibility == :INTERNAL
    assert error_with_runtime.metadata["user_id"].value == "123"
    assert error_with_runtime.metadata["action"].value == "login"
  end

  test "supports tuple format for specifying visibility" do
    error =
      TestSupport.TestError.new!(
        metadata:
          Metadata.new(%{
            "resource" => "user",
            "api_key" => {"secret-key-123", :PRIVATE},
            "user_id" => {"user-123", :PUBLIC}
          })
      )

    assert error.metadata["resource"].visibility == :INTERNAL
    assert error.metadata["resource"].value == "user"

    assert error.metadata["api_key"].visibility == :PRIVATE
    assert error.metadata["api_key"].value == "secret-key-123"

    assert error.metadata["user_id"].visibility == :PUBLIC
    assert error.metadata["user_id"].value == "user-123"
  end

  test "accepts valid compile-time metadata with tuple format" do
    error = TestSupport.ValidTupleMetadataError.new!()
    assert error.metadata["simple"].visibility == :INTERNAL
    assert error.metadata["simple"].value == "value"
    assert error.metadata["with_visibility"].visibility == :PRIVATE
    assert error.metadata["with_visibility"].value == "secret"
  end

  describe "to_msg/1" do
    test "converts error atom or string to string" do
      assert Trogon.Error.to_msg("random message") == "random message"
      assert Trogon.Error.to_msg(:CANCELLED) == "the operation was cancelled"
      assert Trogon.Error.to_msg(:UNKNOWN) == "unknown error"
      assert Trogon.Error.to_msg(:INVALID_ARGUMENT) == "invalid argument provided"
      assert Trogon.Error.to_msg(:DEADLINE_EXCEEDED) == "deadline exceeded"
      assert Trogon.Error.to_msg(:NOT_FOUND) == "resource not found"
      assert Trogon.Error.to_msg(:ALREADY_EXISTS) == "resource already exists"
      assert Trogon.Error.to_msg(:PERMISSION_DENIED) == "permission denied"
      assert Trogon.Error.to_msg(:RESOURCE_EXHAUSTED) == "resource exhausted"
      assert Trogon.Error.to_msg(:FAILED_PRECONDITION) == "failed precondition"
      assert Trogon.Error.to_msg(:ABORTED) == "operation aborted"
      assert Trogon.Error.to_msg(:OUT_OF_RANGE) == "out of range"
      assert Trogon.Error.to_msg(:UNIMPLEMENTED) == "not implemented"
      assert Trogon.Error.to_msg(:INTERNAL) == "internal error"
      assert Trogon.Error.to_msg(:UNAVAILABLE) == "service unavailable"
      assert Trogon.Error.to_msg(:DATA_LOSS) == "data loss or corruption"
      assert Trogon.Error.to_msg(:UNAUTHENTICATED) == "unauthenticated"
    end
  end

  describe "to_code_int/1" do
    test "converts code atom or error struct to integer" do
      assert Trogon.Error.to_code_int(:CANCELLED) == 1
      assert Trogon.Error.to_code_int(:UNKNOWN) == 2
      assert Trogon.Error.to_code_int(:INVALID_ARGUMENT) == 3
      assert Trogon.Error.to_code_int(:DEADLINE_EXCEEDED) == 4
      assert Trogon.Error.to_code_int(:NOT_FOUND) == 5
      assert Trogon.Error.to_code_int(:ALREADY_EXISTS) == 6
      assert Trogon.Error.to_code_int(:PERMISSION_DENIED) == 7
      assert Trogon.Error.to_code_int(:RESOURCE_EXHAUSTED) == 8
      assert Trogon.Error.to_code_int(:FAILED_PRECONDITION) == 9
      assert Trogon.Error.to_code_int(:ABORTED) == 10
      assert Trogon.Error.to_code_int(:OUT_OF_RANGE) == 11
      assert Trogon.Error.to_code_int(:UNIMPLEMENTED) == 12
      assert Trogon.Error.to_code_int(:INTERNAL) == 13
      assert Trogon.Error.to_code_int(:UNAVAILABLE) == 14
      assert Trogon.Error.to_code_int(:DATA_LOSS) == 15
      assert Trogon.Error.to_code_int(:UNAUTHENTICATED) == 16
      error = TestSupport.CompileTimeError.new!()
      assert Trogon.Error.to_code_int(error) == 5
    end
  end

  describe "message/1" do
    test "formats the error message" do
      error = TestSupport.HelpfulError.new!(source_id: "")

      assert Exception.message(error) == """
             helpful error
               visibility: :INTERNAL
               domain: com.test.help
               reason: HELPFUL_ERROR
               code: :UNKNOWN
             - API Docs: https://example.com/docs\
             """

      error = TestSupport.TestError.new!(metadata: Metadata.new(%{user_id: "123"}))

      assert Exception.message(error) == """
             unknown error
               visibility: :INTERNAL
               domain: com.test.app
               reason: TEST_ERROR
               code: :UNKNOWN
               metadata:
                 - user_id: 123 visibility=internal\
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
