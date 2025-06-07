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
                      type: {:in, [:internal, :public]},
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

  @type visibility :: :internal | :public

  @type error_info :: %{
          domain: String.t(),
          reason: String.t(),
          metadata: map()
        }

  @type source :: %{
          optional(:subject) => String.t()
        }

  @type indeterministic_info :: %{
          id: String.t(),
          time: DateTime.t()
        }

  @type help_link :: %{
          description: String.t(),
          url: String.t()
        }

  @type help :: %{
          links: list(help_link())
        }

  @type debug_info :: %{
          stack_entries: list(String.t()),
          metadata: map()
        }

  @type localized_message :: %{
          locale: String.t(),
          message: String.t()
        }

  @type retry_info :: %{
          retry_delay: Duration.t()
        }

  @type t(struct) :: %{
          __struct__: struct,
          __exception__: true,
          specversion: non_neg_integer(),
          code: code(),
          message: String.t(),
          info: error_info(),
          causes: list(t(module())),
          visibility: visibility(),
          source: source() | nil,
          indeterministic_info: indeterministic_info() | nil,
          help: help() | nil,
          debug_info: debug_info() | nil,
          localized_message: localized_message() | nil,
          retry_info: retry_info() | nil
        }

  @type error_opts :: [
          code: code(),
          message: String.t(),
          metadata: map(),
          causes: list(t(module())),
          source: source(),
          debug_info: debug_info(),
          localized_message: localized_message(),
          retry_info: retry_info(),
          indeterministic_info: indeterministic_info(),
          help: help(),
          visibility: visibility()
        ]

  @spec_version 1

  @doc """
  Defines an error module with the given options.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """
  defmacro __using__(opts) do
    compiled_opts =
      opts
      |> NimbleOptions.validate!(@options_schema)
      |> Keyword.put_new(:code, :unknown)
      |> Keyword.put_new(:visibility, :internal)
      |> Keyword.update!(:message, &to_msg/1)

    quote do
      defexception [
        :specversion,
        :code,
        :message,
        :info,
        :causes,
        :visibility,
        :source,
        :indeterministic_info,
        :help,
        :debug_info,
        :localized_message,
        :retry_info
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
        Trogon.Error.__exception__(__MODULE__, unquote(compiled_opts), opts)
      end

      @doc """
      Creates a new error instance with the given options.
      """
      @spec new!(Trogon.Error.error_opts()) :: Trogon.Error.t(__MODULE__)
      def new!(opts \\ []) do
        Trogon.Error.__exception__(__MODULE__, unquote(compiled_opts), opts)
      end

      @impl Exception
      def message(%__MODULE__{} = error) do
        Trogon.Error.__message__(error)
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
      visibility: #{inspect(error.visibility)}
      code: #{inspect(error.code)}
      info: #{inspect(error.info, pretty: true, printable_limit: :infinity)}
      debug_info: #{inspect(error.debug_info, pretty: true, printable_limit: :infinity)}
      retry_info: #{inspect(error.retry_info, pretty: true, printable_limit: :infinity)}
      source: #{inspect(error.source, pretty: true, printable_limit: :infinity)}
      indeterministic_info: #{inspect(error.indeterministic_info, pretty: true, printable_limit: :infinity)}
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

    metadata = Keyword.get(opts, :metadata, %{})
    causes = Keyword.get(opts, :causes, [])
    source = Keyword.get(opts, :source)
    debug_info = Keyword.get(opts, :debug_info)
    localized_message = Keyword.get(opts, :localized_message)
    retry_info = Keyword.get(opts, :retry_info)
    indeterministic_info = Keyword.get(opts, :indeterministic_info)

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
      source: source,
      indeterministic_info: indeterministic_info,
      help: help,
      debug_info: debug_info,
      localized_message: localized_message,
      retry_info: retry_info
    })
  end

  defp to_msg(msg) when is_binary(msg), do: msg
  defp to_msg(:cancelled), do: "the operation was cancelled"
  defp to_msg(:unknown), do: "unknown error"
  defp to_msg(:invalid_argument), do: "invalid argument provided"
  defp to_msg(:deadline_exceeded), do: "deadline exceeded"
  defp to_msg(:not_found), do: "resource not found"
  defp to_msg(:already_exists), do: "resource already exists"
  defp to_msg(:permission_denied), do: "permission denied"
  defp to_msg(:unauthenticated), do: "unauthenticated"
  defp to_msg(:resource_exhausted), do: "resource exhausted"
  defp to_msg(:failed_precondition), do: "failed precondition"
  defp to_msg(:aborted), do: "operation aborted"
  defp to_msg(:out_of_range), do: "out of range"
  defp to_msg(:unimplemented), do: "not implemented"
  defp to_msg(:internal), do: "internal error"
  defp to_msg(:unavailable), do: "service unavailable"
  defp to_msg(:data_loss), do: "data loss or corruption"
end
