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
                      required: true,
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
                      keys: [
                        description: [type: :string, required: true],
                        links: [
                          type: {:list, :map},
                          keys: [
                            description: [type: :string, required: true],
                            url: [type: :string, required: true]
                          ]
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

  @type error_info :: %{
          domain: String.t(),
          reason: String.t(),
          metadata: %{String.t() => String.t()}
        }

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

  @type retry_info :: %{retry_offset: Duration.t()} | %{retry_time: DateTime.t()}

  @type t(struct) :: %{
          __struct__: struct,
          __exception__: true,
          specversion: non_neg_integer(),
          code: code(),
          message: String.t(),
          info: error_info(),
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

      compiled_opts =
        opts
        |> Error.validate_options!()
        |> Keyword.put_new(:code, :unknown)
        |> Keyword.put_new(:visibility, :internal)
        |> Keyword.update!(:message, &Error.to_msg/1)
        |> Keyword.update!(:metadata, &Macro.escape/1)

      defexception [
        :specversion,
        :code,
        :message,
        :info,
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
      |> Enum.map_join("\n", fn link -> "    - #{link.description}: #{link.url}" end)

    message = """
    #{error.message}
      id: #{error.id}
      time: #{error.time}
      visibility: #{error.visibility}
      code: #{error.code}
      info: #{inspect(error.info, pretty: true)}
      debug_info: #{inspect(error.debug_info, pretty: true)}
      retry_info: #{inspect(error.retry_info, pretty: true)}
      subject: #{error.subject}
      source_id: #{error.source_id}

      #{help}
    """

    case help do
      "" -> message
      _ -> "#{message}\n#{help}"
    end
  end

  @spec __exception__(module(), keyword(), error_opts()) :: t(module())
  def __exception__(struct_module, compile_opts, opts \\ []) do
    domain = Keyword.fetch!(compile_opts, :domain)
    reason = Keyword.fetch!(compile_opts, :reason)
    code = Keyword.get(opts, :code, Keyword.fetch!(compile_opts, :code))
    message = Keyword.get(opts, :message, Keyword.fetch!(compile_opts, :message))
    visibility = Keyword.get(opts, :visibility, Keyword.fetch!(compile_opts, :visibility))
    help = Keyword.get(opts, :help, Keyword.get(compile_opts, :help))
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
      info: %{
        domain: domain,
        reason: reason,
        metadata: metadata
      },
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
