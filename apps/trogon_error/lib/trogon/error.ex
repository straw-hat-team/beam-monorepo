defmodule Trogon.Error do
  alias Trogon.Error.Metadata

  import Trogon.Error.Metadata, only: [is_empty_metadata: 1]

  @codes [
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
  ]

  @visibility_levels [:INTERNAL, :PRIVATE, :PUBLIC]

  @template_opts_schema NimbleOptions.new!(
                          domain: [
                            type: :string,
                            type_spec: quote(do: domain()),
                            required: true,
                            doc: "See `t:domain/0`."
                          ],
                          reason: [
                            type: :string,
                            type_spec: quote(do: reason()),
                            required: true,
                            doc: "See `t:reason/0`."
                          ],
                          message: [
                            type: {:or, [:atom, :string]},
                            type_spec: quote(do: atom() | message()),
                            required: false,
                            doc: "See `t:message/0`. Use `:code` if not provided as a string."
                          ],
                          metadata: [
                            type:
                              {:map, :string,
                               {:or, [:string, {:tuple, [:string, {:in, [:INTERNAL, :PRIVATE, :PUBLIC]}]}]}},
                            type_spec: quote(do: Metadata.raw()),
                            default: %{},
                            doc: "Default metadata merged with instance metadata. See `t:Trogon.Error.Metadata.raw/0`."
                          ],
                          code: [
                            type: {:in, @codes},
                            type_spec: quote(do: code()),
                            default: :UNKNOWN,
                            doc: "See `t:code/0`."
                          ],
                          visibility: [
                            type: {:in, @visibility_levels},
                            type_spec: quote(do: visibility()),
                            default: :INTERNAL,
                            doc: "See `t:visibility/0`."
                          ],
                          help: [
                            type: :map,
                            type_spec: quote(do: help()),
                            required: false,
                            keys: [
                              links: [
                                type:
                                  {:list,
                                   {:map,
                                    [
                                      description: [type: :string, required: false],
                                      url: [type: :string, required: true]
                                    ]}}
                              ]
                            ],
                            doc: "See `t:help/0`."
                          ]
                        )

  @moduledoc """
  [Error Specification](https://straw-hat-team.github.io/adr/adrs/0129349218/README.html) implementation for Elixir.

  ## Quick Start

      defmodule MyApp.NotFoundError do
        use Trogon.Error,
          domain: "com.myapp.resources",
          reason: "not_found",
          code: :NOT_FOUND,
          message: "Resource not found"
      end

      # Create an error instance with dynamic metadata
      MyApp.NotFoundError.new!(
        metadata: Trogon.Error.Metadata.new(%{
          "resource_type" => "user",
          "resource_id" => "123"
        })
      )

  ## Design Philosophy

  Trogon errors follow the "Error as Type" pattern where `t:domain/0` + `t:reason/0`
  uniquely identify the error type, `t:message/0` is a static compile-time description,
  and `t:metadata/0` carries instance-specific dynamic values.

  The message is intentionally **not overridable at runtime** to ensure consistent
  messages for logging/monitoring and predictable error contracts for API consumers.

  ## Key Types

  - `t:domain/0` + `t:reason/0` - Unique error identifier
  - `t:code/0` - Standard error code (Google RPC compatible)
  - `t:message/0` - Static error description
  - `t:metadata/0` - Dynamic instance data
  - `t:error_opt/0` - Instance creation options
  """

  @typedoc """
  The standard error code. See [Google RPC error codes](https://github.com/grpc/grpc/blob/master/doc/statuscodes.md)
  for more details.
  """
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

  @typedoc """
  Whether the error should be visible to end users or kept internal.

  - `:INTERNAL` - The error is not visible from outside the application.
  - `:PRIVATE` - The error is visible from applications belonging to the same organization.
  - `:PUBLIC` - The error is visible to everyone.
  """
  @type visibility :: :INTERNAL | :PRIVATE | :PUBLIC

  @typedoc """
  The error message template describing what went wrong.

  Defined at compile time and cannot be overridden at runtime. For dynamic values,
  treat the message as a template and pass runtime data via `:metadata`.
  """
  @type message :: String.t()

  @typedoc """
  The error domain identifying the service or component that generated the error.

  Examples: `"com.myapp.payments"`, `"com.stripe.api"`
  """
  @type domain :: String.t()

  @typedoc """
  A unique identifier for the specific error within the domain.

  Combined with `t:domain/0`, this creates a globally unique error identifier:

      # domain: "com.myapp.payments", reason: "card_declined"
      # domain: "com.myapp.users", reason: "not_found"
  """
  @type reason :: String.t()

  @typedoc """
  Instance-specific metadata as key-value pairs.

      Trogon.Error.Metadata.new(%{
        "user_id" => "123",
        "resource_type" => "order"
      })

  See `Trogon.Error.Metadata` for visibility controls and advanced usage.
  """
  @type metadata :: Metadata.t()

  @typedoc """
  A pointer to the field or element that caused the error.

  Examples: `"email"`, `"user.address.zipCode"`, `"/items/0/quantity"` (JSON Pointer)
  """
  @type subject :: String.t()

  @typedoc """
  Source identifier indicating where the error originated.
  """
  @type source_id :: String.t()

  @typedoc """
  Unique identifier for this error instance.
  """
  @type id :: String.t()

  @typedoc """
  Timestamp when the error occurred.
  """
  @type time :: DateTime.t()

  @typedoc """
  A single help link with a description and URL.
  """
  @type help_link :: %{
          description: String.t(),
          url: String.t()
        }

  @typedoc """
  Help information containing links to documentation or support resources.
  """
  @type help :: %{
          links: list(help_link())
        }

  @typedoc """
  Debug information for troubleshooting, including stack traces and details.
  """
  @type debug_info :: %{
          stack_entries: list(String.t()),
          detail: String.t()
        }

  @typedoc """
  Localized message for internationalization (i18n) support.

  The `locale` follows [IETF BCP-47](https://www.rfc-editor.org/rfc/bcp/bcp47.txt)
  (e.g., `"en-US"`, `"fr-CH"`, `"es-MX"`).
  """
  @type localized_message :: %{
          locale: String.t(),
          message: String.t()
        }

  @typedoc false
  @type retry_info_duration :: %{retry_offset: Duration.t()}

  # TODO: Enable retry info time after https://github.com/aip-dev/google.aip.dev/issues/1528 is resolved
  #  To avoid breaking changes, and strong incompatibility with Google RPC spec, we're not adding retry info time.
  # @type retry_info_time :: %{retry_time: DateTime.t()}

  @typedoc """
  Retry information for recoverable errors, indicating when to retry.

      retry_info: %{retry_offset: %Duration{second: 60}}
  """
  @type retry_info :: retry_info_duration()

  @typedoc """
  The Trogon error struct type, parameterized by the error module.

      @spec find_user(String.t()) ::
              {:ok, User.t()}
              | {:error, Trogon.Error.t(MyApp.NotFoundError)}
  """
  @type t(struct) :: %{
          __struct__: struct,
          __exception__: true,
          specversion: non_neg_integer(),
          code: code(),
          message: message(),
          domain: domain(),
          reason: reason(),
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

  @typedoc """
  Instance options for `new!/1`. See the type definition for available keys.

      MyApp.NotFoundError.new!(
        metadata: Trogon.Error.Metadata.new(%{"user_id" => "123"}),
        subject: "user:123",
        localized_message: %{locale: "es", message: "Usuario no encontrado"}
      )

  > #### The `:message` option is not supported {: .warning}
  >
  > Use `:localized_message` for i18n or `:metadata` for dynamic values.
  """
  @type error_opt ::
          {:metadata, metadata()}
          | {:causes, list(t(module()))}
          | {:subject, subject() | nil}
          | {:debug_info, debug_info() | nil}
          | {:localized_message, localized_message() | nil}
          | {:retry_info, retry_info() | nil}
          | {:id, id() | nil}
          | {:time, time() | nil}
          | {:source_id, source_id() | nil}

  @typedoc """
  A single template option for defining an error module with `use Trogon.Error`.

      defmodule MyApp.NotFoundError do
        use Trogon.Error,
          domain: "com.myapp.resources",
          reason: "not_found",
          code: :NOT_FOUND,
          message: "Resource not found"
      end

  ## Options

  #{NimbleOptions.docs(@template_opts_schema)}
  """
  @type template_opt :: unquote(NimbleOptions.option_typespec(@template_opts_schema))

  @spec_version 1

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

  @impl Exception
  def message(error) do
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

  @doc false
  def exception(struct_module, compile_opts, opts \\ []) do
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

  @doc false
  def validate_template_opts!(opts) do
    NimbleOptions.validate!(opts, @template_opts_schema)
  end

  defp validate_runtime_options!(opts) do
    code = opts[:code]

    if code && code not in @codes do
      raise ArgumentError, "Invalid code: #{inspect(code)}"
    end

    visibility = opts[:visibility]

    if visibility && visibility not in @visibility_levels do
      raise ArgumentError, "Invalid visibility: #{inspect(visibility)}"
    end

    domain = opts[:domain]

    if not is_binary(domain) do
      raise ArgumentError, "Invalid domain: #{inspect(domain)}"
    end

    reason = opts[:reason]

    if not is_binary(reason) do
      raise ArgumentError, "Invalid reason: #{inspect(reason)}"
    end

    opts
  end

  defdelegate metadata, to: Metadata, as: :new

  @template_opts [:domain, :reason, :code, :message, :visibility, :help, :metadata]

  @doc """
  Creates a new Trogon error at runtime with dynamic values.

  Useful for handling external errors from services you don't control,
  without needing predefined error modules.

  ## Examples

      # Basic external error
      Trogon.Error.new!(
        domain: "com.stripe.payment",
        reason: "card_declined",
        message: "Your card was declined"
      )

      # With additional metadata and options
      Trogon.Error.new!(
        domain: "com.external.api",
        reason: "rate_limit_exceeded",
        code: :RESOURCE_EXHAUSTED,
        message: "Rate limit exceeded",
        metadata: Trogon.Error.Metadata.new(%{
          "limit" => "100",
          "window" => "3600"
        }),
        subject: "api-client-123",
        retry_info: %{retry_offset: %Duration{second: 60}}
      )

  """
  @spec new!([template_opt() | error_opt()]) :: t(__MODULE__)
  def new!(opts) when is_list(opts) do
    {template_opts, instance_opts} = Keyword.split(opts, @template_opts)

    template_opts = validate_runtime_options!(template_opts)

    compiled_opts =
      [code: :UNKNOWN, visibility: :INTERNAL, help: nil, metadata: %{}]
      |> Keyword.merge(template_opts)
      |> Keyword.update!(:metadata, &to_metadata/1)
      |> then(&Keyword.put_new(&1, :message, &1[:code]))
      |> Keyword.update!(:message, &to_msg/1)

    exception(__MODULE__, compiled_opts, instance_opts)
  end

  defp to_metadata(%Metadata{} = metadata) do
    metadata
  end

  defp to_metadata(raw_metadata) when is_map(raw_metadata) do
    Metadata.new(raw_metadata)
  end

  @doc """
  Converts a code atom or error struct to its integer value.

  ## Examples

      iex> Trogon.Error.to_code_int(:CANCELLED)
      1

      iex> err = TestSupport.InvalidCurrencyError.new!()
      iex> Trogon.Error.to_code_int(err)
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
  Converts a code atom or error struct to its HTTP status code.

  ## Examples

      iex> Trogon.Error.to_http_status_code(:CANCELLED)
      499

      iex> err = TestSupport.InvalidCurrencyError.new!()
      iex> Trogon.Error.to_http_status_code(err)
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
  def to_http_status_code(:FAILED_PRECONDITION), do: 400
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
  Guard that checks if a term is a Trogon error.

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

  @doc false
  def compile_metadata(metadata) when is_map(metadata) do
    metadata
    |> Metadata.new()
    |> Macro.escape()
  end

  @doc "See `t:template_opt/0` for available options."
  @spec __using__([template_opt()]) :: Macro.t()
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts = Trogon.Error.validate_template_opts!(opts)

      compiled_opts =
        [code: :UNKNOWN, visibility: :INTERNAL, help: nil]
        |> Keyword.merge(opts)
        |> Keyword.update!(:help, &Macro.escape/1)
        |> Keyword.update!(:metadata, &Trogon.Error.compile_metadata(&1))
        |> then(&Keyword.put_new(&1, :message, &1[:code]))
        |> Keyword.update!(:message, &Trogon.Error.to_msg/1)

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

      @doc "Creates an error struct for use with `raise/2`."
      @impl Exception
      @spec exception([Trogon.Error.error_opt()]) :: Trogon.Error.t(module())
      def exception(opts \\ []) do
        Trogon.Error.exception(__MODULE__, unquote(compiled_opts), opts)
      end

      @doc "Creates a new error instance."
      @spec new!([Trogon.Error.error_opt()]) :: Trogon.Error.t(module())
      def new!(opts \\ []) when is_list(opts) do
        Trogon.Error.exception(__MODULE__, unquote(compiled_opts), opts)
      end

      @impl Exception
      def message(%__MODULE__{} = error) do
        Trogon.Error.message(error)
      end
    end
  end
end
