defmodule Trogon.Error do
  alias Trogon.Error.Metadata
  import Trogon.Error.Metadata, only: [is_empty_metadata: 1]

  @options_schema NimbleOptions.new!(
                    domain: [
                      type: :string,
                      required: true,
                      doc: "The error domain identifying the service or component that generated the error"
                    ],
                    reason: [
                      type: :string,
                      required: true,
                      doc: "A unique identifier for the specific error within the domain"
                    ],
                    message: [
                      type: {:or, [:atom, :string]},
                      required: false,
                      doc: "The error message, either an atom that maps to a standard message or a custom string"
                    ],
                    metadata: [
                      type:
                        {:map, :string, {:or, [:string, {:tuple, [:string, {:in, [:INTERNAL, :PRIVATE, :PUBLIC]}]}]}},
                      default: %{},
                      doc:
                        "Default metadata to be merged with runtime metadata. Values will be automatically converted to MetadataValue structs."
                    ],
                    code: [
                      type:
                        {:in,
                         [
                           :CANCELLED,
                           :UNKNOWN,
                           :INVALID_ARGUMENT,
                           :DEADLINE_EXCEEDED,
                           :NOT_FOUND,
                           :ALREADY_EXISTS,
                           :PERMISSION_DENIED,
                           :RESOURCE_EXHAUSTED,
                           :FAILED_PRECONDITION,
                           :ABORTED,
                           :OUT_OF_RANGE,
                           :UNIMPLEMENTED,
                           :INTERNAL,
                           :UNAVAILABLE,
                           :DATA_LOSS,
                           :UNAUTHENTICATED
                         ]},
                      default: :UNKNOWN,
                      doc: "The standard error code"
                    ],
                    visibility: [
                      type: {:in, [:INTERNAL, :PRIVATE, :PUBLIC]},
                      default: :INTERNAL,
                      doc: "Whether the error should be visible to end users or kept internal"
                    ],
                    help: [
                      type: :map,
                      required: false,
                      keys: [
                        links: [
                          type:
                            {:list,
                             {:map,
                              [description: [type: :string, required: false], url: [type: :string, required: true]]}}
                        ]
                      ],
                      doc: "Help information with links to documentation"
                    ]
                  )

  @moduledoc """
  Universal Error Specification implementation for Elixir.

  This module provides a `use` macro to define structured exceptions
  following the Universal Error Specification ADR.

  ## Usage

      defmodule MyApp.NotFoundError do
        use Trogon.Error,
          domain: "com.myapp.mydomain",
          reason: "not_found",
          message: "The {resource} was not found"
      end

  ## Creating Errors

      MyApp.NotFoundError.new!(
        metadata: Trogon.Error.Metadata.new(%{resource: "user"})
      )
  """

  # Error codes as per the spec
  @type code ::
          :CANCELLED
          | :UNKNOWN
          | :INVALID_ARGUMENT
          | :DEADLINE_EXCEEDED
          | :NOT_FOUND
          | :ALREADY_EXISTS
          | :PERMISSION_DENIED
          | :RESOURCE_EXHAUSTED
          | :FAILED_PRECONDITION
          | :ABORTED
          | :OUT_OF_RANGE
          | :UNIMPLEMENTED
          | :INTERNAL
          | :UNAVAILABLE
          | :DATA_LOSS
          | :UNAUTHENTICATED

  @type visibility :: :INTERNAL | :PRIVATE | :PUBLIC

  @type metadata :: Metadata.t()

  @type subject :: String.t()

  @type source_id :: String.t()

  @type id :: String.t()
  @type time :: DateTime.t()

  @type help_link :: %{
          description: String.t(),
          url: String.t()
        }

  @type help :: %{
          links: list(help_link())
        }

  @type debug_info :: %{
          stack_entries: list(String.t()),
          detail: String.t()
        }

  @type localized_message :: %{
          locale: String.t(),
          message: String.t()
        }

  @type retry_info_duration :: %{retry_offset: Duration.t()}
  # TODO: Enable retry info time aftr https://github.com/aip-dev/google.aip.dev/issues/1528 is resolved
  #  To avoid breaking changes, and strong incompatibility with Google RPC spec, we're not adding retry info time.
  # @type retry_info_time :: %{retry_time: DateTime.t()}
  @type retry_info :: retry_info_duration()

  @type t(struct) :: %{
          __struct__: struct,
          __exception__: true,
          specversion: non_neg_integer(),
          code: code(),
          message: String.t(),
          domain: String.t(),
          reason: String.t(),
          metadata: metadata(),
          causes: list(t(module())),
          visibility: visibility(),
          subject: subject() | nil,
          id: id() | nil,
          time: time() | nil,
          help: help() | nil,
          debug_info: debug_info() | nil,
          localized_message: localized_message() | nil,
          retry_info: retry_info() | nil,
          source_id: source_id() | nil
        }

  @type error_opts :: [
          {:metadata, metadata()}
          | {:causes, list(t(module()))}
          | {:subject, subject() | nil}
          | {:debug_info, debug_info() | nil}
          | {:localized_message, localized_message() | nil}
          | {:retry_info, retry_info() | nil}
          | {:id, id() | nil}
          | {:time, time() | nil}
          | {:source_id, source_id() | nil}
        ]

  @spec_version 1

  @doc """
  Defines an error module with the given options.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Trogon.Error

      opts = Error.validate_options!(opts)

      compiled_opts =
        [code: :UNKNOWN, visibility: :INTERNAL, help: nil]
        |> Keyword.merge(opts)
        |> Keyword.update!(:help, &Macro.escape/1)
        |> Keyword.update!(:metadata, &Error._compile_metadata(&1))
        |> then(&Keyword.put_new(&1, :message, &1[:code]))
        |> Keyword.update!(:message, &Error.to_msg/1)

      @derive {Inspect, except: [:__trogon_error__]}
      @enforce_keys [:specversion, :code, :message, :domain, :reason, :metadata]
      defexception [
        :__trogon_error__,
        :specversion,
        :code,
        :message,
        :domain,
        :reason,
        :metadata,
        :causes,
        :visibility,
        :subject,
        :id,
        :time,
        :help,
        :debug_info,
        :localized_message,
        :retry_info,
        :source_id
      ]

      @doc """
      Raises an error with the given options.

      > #### When to use `exception/1` {: .info}
      > Use `exception/1` when you want to raise an error.
      >
      > Example:
      >
      > ```elixir
      > raise MyApp.NotFoundError, metadata: Trogon.Error.Metadata.new(%{resource: "user"})
      > ```
      >
      > Otherwise, use `new!/1` to create an error instance.
      """
      @impl Exception
      @spec exception(Trogon.Error.error_opts()) :: Trogon.Error.t(__MODULE__)
      def exception(opts \\ []) do
        Error._exception(__MODULE__, unquote(compiled_opts), opts)
      end

      @doc """
      Creates a new error instance with the given options.
      """
      @spec new!(Trogon.Error.error_opts()) :: Trogon.Error.t(__MODULE__)
      def new!(opts \\ []) when is_list(opts) do
        Error._exception(__MODULE__, unquote(compiled_opts), opts)
      end

      @impl Exception
      def message(%__MODULE__{} = error) do
        Error._message(error)
      end
    end
  end

  def _message(error) do
    help =
      (error.help || %{})
      |> Map.get(:links, [])
      |> Enum.map_join("\n", fn link -> "- #{link.description}: #{link.url}" end)

    info_msg =
      ""
      |> put_key_msg_line("  visibility", error.visibility)
      |> put_key_msg_line("  domain", error.domain)
      |> put_key_msg_line("  reason", error.reason)
      |> put_key_msg_line("  code", error.code)
      |> put_key_msg_line("  metadata", error.metadata)
      |> put_key_msg_line("  id", error.id)
      |> put_key_msg_line("  time", error.time)
      |> put_key_msg_line("  subject", error.subject)
      |> put_key_msg_line("  source_id", error.source_id)
      |> put_key_msg_line("  retry_info", error.retry_info)
      |> put_key_msg_line("  debug_info", error.debug_info)
      |> put_help_msg_line(help)

    String.trim_trailing(error.message) <> info_msg
  end

  defp put_key_msg_line(msg, _key, nil), do: msg
  defp put_key_msg_line(msg, _key, ""), do: msg
  defp put_key_msg_line(msg, _key, map) when is_map(map) and map_size(map) == 0, do: msg
  defp put_key_msg_line(msg, _key, metadata) when is_empty_metadata(metadata), do: msg
  defp put_key_msg_line(msg, key, %Metadata{} = metadata), do: "#{msg}\n#{key}:\n#{pretty_print(metadata)}"
  defp put_key_msg_line(msg, key, value), do: "#{msg}\n#{key}: #{pretty_print(value)}"

  defp put_help_msg_line(msg, ""), do: msg
  defp put_help_msg_line(msg, help), do: "#{msg}\n#{help}"

  defp pretty_print(term) when is_binary(term), do: term

  defp pretty_print(%Metadata{entries: entries}) do
    Enum.map_join(entries, "\n", fn {key, value} ->
      "    - #{key}: #{value.value} visibility=#{value.visibility}"
    end)
  end

  defp pretty_print(term), do: inspect(term, pretty: true)

  def _exception(struct_module, compile_opts, opts \\ []) do
    domain = Keyword.fetch!(compile_opts, :domain)
    reason = Keyword.fetch!(compile_opts, :reason)
    code = Keyword.fetch!(compile_opts, :code)
    message = Keyword.fetch!(compile_opts, :message)
    visibility = Keyword.fetch!(compile_opts, :visibility)
    help = Keyword.get(compile_opts, :help)
    compile_metadata = Keyword.fetch!(compile_opts, :metadata)
    runtime_metadata = Keyword.get(opts, :metadata, Metadata.new())
    metadata = Metadata.merge(compile_metadata, runtime_metadata)

    causes = Keyword.get(opts, :causes, [])
    subject = Keyword.get(opts, :subject)
    debug_info = Keyword.get(opts, :debug_info)
    localized_message = Keyword.get(opts, :localized_message)
    retry_info = Keyword.get(opts, :retry_info)
    id = Keyword.get(opts, :id)
    time = Keyword.get(opts, :time)
    source_id = Keyword.get(opts, :source_id)

    struct(struct_module, %{
      __trogon_error__: true,
      specversion: @spec_version,
      code: code,
      message: message,
      domain: domain,
      reason: reason,
      metadata: metadata,
      causes: causes,
      visibility: visibility,
      subject: subject,
      id: id,
      time: time,
      help: help,
      debug_info: debug_info,
      localized_message: localized_message,
      retry_info: retry_info,
      source_id: source_id
    })
  end

  @doc """
  Validates compile-time options using NimbleOptions.

  ## Examples

      iex> opts = [domain: "com.test", reason: "TEST"]
      iex> validated = Trogon.Error.validate_options!(opts)
      iex> validated[:domain]
      "com.test"
      iex> validated[:reason]
      "TEST"

  """
  @spec validate_options!(keyword()) :: keyword()
  def validate_options!(opts) do
    NimbleOptions.validate!(opts, @options_schema)
  end

  defdelegate metadata, to: Metadata, as: :new

  @doc """
  Converts an atom to an integer code.

  ## Examples

      iex> Trogon.Error.to_code_int(:CANCELLED)
      1
      iex> err = TestSupport.InvalidCurrencyError.new!()
      ...> Trogon.Error.to_code_int(err)
      2
  """
  @spec to_code_int(atom() | t(module())) :: non_neg_integer()
  def to_code_int(%{code: code}), do: to_code_int(code)
  def to_code_int(:CANCELLED), do: 1
  def to_code_int(:UNKNOWN), do: 2
  def to_code_int(:INVALID_ARGUMENT), do: 3
  def to_code_int(:DEADLINE_EXCEEDED), do: 4
  def to_code_int(:NOT_FOUND), do: 5
  def to_code_int(:ALREADY_EXISTS), do: 6
  def to_code_int(:PERMISSION_DENIED), do: 7
  def to_code_int(:RESOURCE_EXHAUSTED), do: 8
  def to_code_int(:FAILED_PRECONDITION), do: 9
  def to_code_int(:ABORTED), do: 10
  def to_code_int(:OUT_OF_RANGE), do: 11
  def to_code_int(:UNIMPLEMENTED), do: 12
  def to_code_int(:INTERNAL), do: 13
  def to_code_int(:UNAVAILABLE), do: 14
  def to_code_int(:DATA_LOSS), do: 15
  def to_code_int(:UNAUTHENTICATED), do: 16

  @doc """
  Converts an error code to its corresponding HTTP status code.

  ## Examples

      iex> Trogon.Error.to_http_status_code(:CANCELLED)
      499
      iex> err = TestSupport.InvalidCurrencyError.new!()
      ...> Trogon.Error.to_http_status_code(err)
      500
  """
  @spec to_http_status_code(atom() | t(module())) :: non_neg_integer()
  def to_http_status_code(%{code: code}), do: to_http_status_code(code)
  def to_http_status_code(:CANCELLED), do: 499
  def to_http_status_code(:UNKNOWN), do: 500
  def to_http_status_code(:INVALID_ARGUMENT), do: 400
  def to_http_status_code(:DEADLINE_EXCEEDED), do: 504
  def to_http_status_code(:NOT_FOUND), do: 404
  def to_http_status_code(:ALREADY_EXISTS), do: 409
  def to_http_status_code(:PERMISSION_DENIED), do: 403
  def to_http_status_code(:RESOURCE_EXHAUSTED), do: 429
  def to_http_status_code(:FAILED_PRECONDITION), do: 422
  def to_http_status_code(:ABORTED), do: 409
  def to_http_status_code(:OUT_OF_RANGE), do: 400
  def to_http_status_code(:UNIMPLEMENTED), do: 501
  def to_http_status_code(:INTERNAL), do: 500
  def to_http_status_code(:UNAVAILABLE), do: 503
  def to_http_status_code(:DATA_LOSS), do: 500
  def to_http_status_code(:UNAUTHENTICATED), do: 401

  @spec to_msg(atom() | String.t()) :: String.t()
  def to_msg(msg) when is_binary(msg), do: msg
  def to_msg(:CANCELLED), do: "the operation was cancelled"
  def to_msg(:UNKNOWN), do: "unknown error"
  def to_msg(:INVALID_ARGUMENT), do: "invalid argument provided"
  def to_msg(:DEADLINE_EXCEEDED), do: "deadline exceeded"
  def to_msg(:NOT_FOUND), do: "resource not found"
  def to_msg(:ALREADY_EXISTS), do: "resource already exists"
  def to_msg(:PERMISSION_DENIED), do: "permission denied"
  def to_msg(:UNAUTHENTICATED), do: "unauthenticated"
  def to_msg(:RESOURCE_EXHAUSTED), do: "resource exhausted"
  def to_msg(:FAILED_PRECONDITION), do: "failed precondition"
  def to_msg(:ABORTED), do: "operation aborted"
  def to_msg(:OUT_OF_RANGE), do: "out of range"
  def to_msg(:UNIMPLEMENTED), do: "not implemented"
  def to_msg(:INTERNAL), do: "internal error"
  def to_msg(:UNAVAILABLE), do: "service unavailable"
  def to_msg(:DATA_LOSS), do: "data loss or corruption"

  @doc """
  Checks if a term is a Trogon error.

  ## Examples

      iex> error = TestSupport.TestError.new!()
      iex> require Trogon.Error
      iex> Trogon.Error.is_trogon_error?(error)
      true

      iex> require Trogon.Error
      iex> Trogon.Error.is_trogon_error?(%{})
      false

  """
  defguard is_trogon_error?(term)
           when is_map(term) and is_map_key(term, :__trogon_error__) and
                  :erlang.map_get(:__trogon_error__, term) == true

  def _compile_metadata(metadata) when is_map(metadata) do
    metadata
    |> Metadata.new()
    |> Macro.escape()
  end
end
