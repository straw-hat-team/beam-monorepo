defmodule OnePiece.Oban do
  @moduledoc """
  Provides a simplified interface to the `Oban` library.
  """

  @doc """
  It creates a facade for the `Oban` functions.

  It allows you to avoid having to pass the `t:Oban.name/0` value to the `Oban` functions, as it is automatically set to
  the module name. As well as allowing you to configure the `Oban` instance in the application's configuration using
  the module name under a given OTP application key.

  ## Examples

  ### In an application module

      defmodule MyApp.Oban do
        use OnePiece.Oban,
          otp_app: :my_app,
          repo: MyApp.Repo
      end

  Now you can register the `MyApp.Oban` module in the application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            MyApp.Repo,
            MyApp.Oban
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  ### Avoiding the need of passing the `Oban` instance

  Instead of calling `Oban` functions passing the `Oban` instance, you can use the `OnePiece.Oban` module directly:

      OnePiece.Oban.insert(MyApp.MyJob.new(args: %{ "field" => "value" }))
  """
  defmacro __using__(opts \\ []) do
    {opts, child_opts} = Keyword.split(opts, [:otp_app])
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote do
      @doc """
      Returns the Oban child spec for the application. This should be added to the application's supervision tree.

      The `:name` option is ignored and set to `#{inspect(__MODULE__)}`.

      ## Examples

          defmodule MyApp.Application do
            use Application

            children = [
              {#{inspect(__MODULE__)}, prefix: "special"}
            ]

            opts = [strategy: :one_for_one, name: MyApp.Supervisor]
            Supervisor.start_link(children, opts)
          end
      """
      def child_spec(opts) do
        unquote(child_opts)
        |> Keyword.merge(Application.get_env(unquote(otp_app), __MODULE__, []))
        |> Keyword.merge(opts)
        |> Keyword.put(:name, __MODULE__)
        |> Oban.child_spec()
      end

      @doc """
      A facade for `Oban.cancel_all_jobs/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec cancel_all_jobs(queryable :: Ecto.Queryable.t()) :: {:ok, non_neg_integer()}
      def cancel_all_jobs(queryable) do
        Oban.insert(__MODULE__, queryable)
      end

      @doc """
      A facade for `Oban.cancel_job/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec cancel_job(job_or_id :: Oban.Job.t() | integer()) :: :ok
      def cancel_job(job_or_id) do
        Oban.cancel_job(__MODULE__, job_or_id)
      end

      @doc """
      A facade for `Oban.check_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec check_queue(opts :: [{:queue, Oban.queue_name()}]) :: Oban.queue_state()
      def check_queue(opts) do
        Oban.check_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.config/1` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec config :: Oban.Config.t()
      def config do
        Oban.config(__MODULE__)
      end

      @doc """
      A facade for `Oban.drain_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec drain_queue(opts :: [Oban.drain_option()]) :: Oban.drain_result()
      def drain_queue(opts) do
        Oban.drain_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.insert/3` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec insert(changeset :: Oban.Job.changeset(), opts :: Keyword.t()) ::
              {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset() | term()}
      def insert(changeset, opts \\ []) do
        Oban.insert(__MODULE__, changeset, opts)
      end

      @doc """
      A facade for `Oban.insert/5` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec insert(Oban.multi(), Oban.multi_name(), Oban.changeset_or_fun(), Keyword.t()) :: Oban.multi()
      def insert(multi, multi_name, changeset, opts \\ []) do
        Oban.insert(__MODULE__, multi, multi_name, changeset, opts)
      end

      @doc """
      A facade for `Oban.insert!/3` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec insert!(Job.changeset(), opts :: Keyword.t()) :: Job.t()
      def insert!(changeset, opts \\ []) do
        Oban.insert!(__MODULE__, changeset, opts)
      end

      @doc """
      A facade for `Oban.insert_all/3` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec insert_all(
              Oban.changesets_or_wrapper() | Oban.multi_name(),
              Keyword.t() | Oban.changesets_or_wrapper_or_fun()
            ) :: [Job.t()] | Oban.multi()
      def insert_all(changesets, opts) do
        Oban.insert_all(__MODULE__, changesets, opts)
      end

      @doc """
      A facade for `Oban.insert_all/5` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec insert_all(Oban.multi(), Oban.multi_name(), Oban.changesets_or_wrapper_or_fun(), Keyword.t()) ::
              Oban.multi()
      def insert_all(multi, multi_name, changesets, opts) do
        Oban.insert_all(__MODULE__, multi, multi_name, changesets, opts)
      end

      @doc """
      A facade for `Oban.start_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec start_queue(opts :: Keyword.t()) :: :ok
      def start_queue(opts) do
        Oban.start_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.pause_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec pause_queue(opts :: [Oban.queue_option()]) :: :ok
      def pause_queue(opts) do
        Oban.pause_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.resume_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec resume_queue(opts :: [Oban.queue_option()]) :: :ok
      def resume_queue(opts) do
        Oban.resume_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.scale_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec scale_queue(opts :: [Oban.queue_option()]) :: :ok
      def scale_queue(opts) do
        Oban.scale_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.stop_queue/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec stop_queue(opts :: [Oban.queue_option()]) :: :ok
      def stop_queue(opts) do
        Oban.stop_queue(__MODULE__, opts)
      end

      @doc """
      A facade for `Oban.retry_job/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec retry_job(job_or_id :: Job.t() | integer()) :: :ok
      def retry_job(job_or_id) do
        Oban.retry_job(__MODULE__, job_or_id)
      end

      @doc """
      A facade for `Oban.retry_all_jobs/2` that uses the `#{inspect(__MODULE__)}` module as the `t:Oban.name/0` argument.
      """
      @spec retry_all_jobs(queryable :: Ecto.Queryable.t()) :: {:ok, non_neg_integer()}
      def retry_all_jobs(queryable) do
        Oban.retry_all_jobs(__MODULE__, queryable)
      end
    end
  end
end
