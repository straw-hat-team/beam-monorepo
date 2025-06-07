defmodule Trogon.Error do
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
                      type: :map,
                      default: %{},
                      doc: "Default metadata to be merged with runtime metadata."
                    ],
                    code: [
                      type:
                        {:in,
                         [
                           :cancelled,
                           :unknown,
                           :invalid_argument,
                           :deadline_exceeded,
                           :not_found,
                           :already_exists,
                           :permission_denied,
                           :unauthenticated,
                           :resource_exhausted,
                           :failed_precondition,
                           :aborted,
                           :out_of_range,
                           :unimplemented,
                           :internal,
                           :unavailable,
                           :data_loss
                         ]},
                      default: :unknown,
                      doc: "The standard error code"
                    ],
                    visibility: [
                      type: {:in, [:internal, :private, :public]},
                      default: :internal,
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
        metadata: %{resource: "user"}
      )
  """

  # Error codes as per the spec
  @type code ::
          :cancelled
          | :unknown
          | :invalid_argument
          | :deadline_exceeded
          | :not_found
          | :already_exists
          | :permission_denied
          | :unauthenticated
          | :resource_exhausted
          | :failed_precondition
          | :aborted
          | :out_of_range
          | :unimplemented
          | :internal
          | :unavailable
          | :data_loss

  @type visibility :: :internal | :private | :public

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
          metadata: %{String.t() => String.t()}
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
          metadata: %{String.t() => String.t()},
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
          code: code(),
          message: String.t(),
          metadata: map(),
          causes: list(t(module())),
          subject: subject(),
          debug_info: debug_info(),
          localized_message: localized_message(),
          retry_info: retry_info(),
          id: id(),
          time: time(),
          help: help(),
          visibility: visibility(),
          source_id: source_id()
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
        [code: :unknown, visibility: :internal, help: nil]
        |> Keyword.merge(opts)
        |> Keyword.update!(:help, &Macro.escape/1)
        |> Keyword.update!(:metadata, &Macro.escape/1)
        |> then(&Keyword.put_new(&1, :message, &1[:code]))
        |> Keyword.update!(:message, &Error.to_msg/1)

      @enforce_keys [:specversion, :code, :message, :domain, :reason, :metadata]
      defexception [
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
      > raise MyApp.NotFoundError, metadata: %{resource: "user"}
      > ```
      >
      > Otherwise, use `new!/1` to create an error instance.
      """
      @impl Exception
      @spec exception(Trogon.Error.error_opts()) :: Trogon.Error.t(__MODULE__)
      def exception(opts \\ []) do
        Error.__exception__(__MODULE__, unquote(compiled_opts), opts)
      end

      @doc """
      Creates a new error instance with the given options.
      """
      @spec new!(Trogon.Error.error_opts()) :: Trogon.Error.t(__MODULE__)
      def new!(opts \\ []) do
        Error.__exception__(__MODULE__, unquote(compiled_opts), opts)
      end

      @impl Exception
      def message(%__MODULE__{} = error) do
        Error.__message__(error)
      end
    end
  end

  @spec __message__(t(module())) :: String.t()
  def __message__(error) do
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

  defp put_key_msg_line(msg, key, value)
  defp put_key_msg_line(msg, _key, nil), do: msg
  defp put_key_msg_line(msg, _key, ""), do: msg
  defp put_key_msg_line(msg, _key, map) when is_map(map) and map_size(map) == 0, do: msg
  defp put_key_msg_line(msg, key, value), do: "#{msg}\n#{key}: #{pretty_print(value)}"

  defp put_help_msg_line(msg, ""), do: msg
  defp put_help_msg_line(msg, help), do: "#{msg}\n#{help}"

  defp pretty_print(term) when is_binary(term), do: term
  defp pretty_print(term), do: inspect(term, pretty: true)

  @spec __exception__(module(), keyword(), error_opts()) :: t(module())
  def __exception__(struct_module, compile_opts, opts \\ []) do
    domain = Keyword.fetch!(compile_opts, :domain)
    reason = Keyword.fetch!(compile_opts, :reason)
    code = Keyword.fetch!(compile_opts, :code)
    message = Keyword.fetch!(compile_opts, :message)
    visibility = Keyword.fetch!(compile_opts, :visibility)
    help = Keyword.get(compile_opts, :help)
    metadata = merge_map(Keyword.fetch!(compile_opts, :metadata), Keyword.get(opts, :metadata))

    causes = Keyword.get(opts, :causes, [])
    subject = Keyword.get(opts, :subject)
    debug_info = Keyword.get(opts, :debug_info)
    localized_message = Keyword.get(opts, :localized_message)
    retry_info = Keyword.get(opts, :retry_info)
    id = Keyword.get(opts, :id)
    time = Keyword.get(opts, :time)
    source_id = Keyword.get(opts, :source_id)

    struct(struct_module, %{
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

  @spec validate_options!(keyword()) :: keyword()
  def validate_options!(opts) do
    NimbleOptions.validate!(opts, @options_schema)
  end

  @doc """
  Converts an atom to an integer code.

  ## Examples

      iex> Trogon.Error.to_code_int(:cancelled)
      1
      iex> err = TestSupport.Errors.InvalidCurrencyError.new!()
      ...> Trogon.Error.to_code_int(err)
      2
  """
  @spec to_code_int(atom() | t(module())) :: non_neg_integer()
  def to_code_int(%{code: code}), do: to_code_int(code)
  def to_code_int(:cancelled), do: 1
  def to_code_int(:unknown), do: 2
  def to_code_int(:invalid_argument), do: 3
  def to_code_int(:deadline_exceeded), do: 4
  def to_code_int(:not_found), do: 5
  def to_code_int(:already_exists), do: 6
  def to_code_int(:permission_denied), do: 7
  def to_code_int(:resource_exhausted), do: 8
  def to_code_int(:failed_precondition), do: 9
  def to_code_int(:aborted), do: 10
  def to_code_int(:out_of_range), do: 11
  def to_code_int(:unimplemented), do: 12
  def to_code_int(:internal), do: 13
  def to_code_int(:unavailable), do: 14
  def to_code_int(:data_loss), do: 15
  def to_code_int(:unauthenticated), do: 16

  @spec to_msg(atom() | String.t()) :: String.t()
  def to_msg(msg) when is_binary(msg), do: msg
  def to_msg(:cancelled), do: "the operation was cancelled"
  def to_msg(:unknown), do: "unknown error"
  def to_msg(:invalid_argument), do: "invalid argument provided"
  def to_msg(:deadline_exceeded), do: "deadline exceeded"
  def to_msg(:not_found), do: "resource not found"
  def to_msg(:already_exists), do: "resource already exists"
  def to_msg(:permission_denied), do: "permission denied"
  def to_msg(:unauthenticated), do: "unauthenticated"
  def to_msg(:resource_exhausted), do: "resource exhausted"
  def to_msg(:failed_precondition), do: "failed precondition"
  def to_msg(:aborted), do: "operation aborted"
  def to_msg(:out_of_range), do: "out of range"
  def to_msg(:unimplemented), do: "not implemented"
  def to_msg(:internal), do: "internal error"
  def to_msg(:unavailable), do: "service unavailable"
  def to_msg(:data_loss), do: "data loss or corruption"

  defp merge_map(map1, nil), do: map1
  defp merge_map(map1, map2), do: Map.merge(map1, map2)
end
