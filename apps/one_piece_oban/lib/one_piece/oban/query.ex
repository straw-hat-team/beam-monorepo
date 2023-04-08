defmodule OnePiece.Oban.Query do
  @moduledoc """
  This module provides a series of helper functions to interact with `Oban.Job` queries.

  It simplifies the process of querying `Oban.Job` jobs by providing functions for common querying scenarios.
  """

  import Ecto.Query, only: [from: 2]

  @doc """
  Creates a new Oban.Job query.
  """
  @spec new() :: Ecto.Queryable.t()
  def new do
    Oban.Job
  end

  @doc """
  Filters the query by the worker name.

  ## Examples

      OnePiece.Oban.Query.new()
      |> Oban.Query.where_worker("MyApp.MyWorker")
      |> Oban.cancel_all_jobs()
  """
  @spec where_worker(query :: Ecto.Queryable.t(), worker_name :: String.t()) :: Ecto.Query.t()
  def where_worker(query, worker_name) do
    from(j in query, where: j.worker == ^worker_name)
  end

  @doc """
  Filters the query by the given queue name or job module.

  When a module is given, the queue name is inferred from the module `queue` configuration.

  ## Examples

      OnePiece.Oban.Query.new()
      |> Oban.Query.where_queue(MyApp.Job)
      |> Repo.all()

      OnePiece.Oban.Query.new()
      |> Oban.Query.where_queue("default")
      |> Repo.all()
  """
  @spec where_queue(query :: Ecto.Queryable.t(), queue_name_or_job_mod :: String.t() | module()) :: Ecto.Query.t()
  def where_queue(query, queue_name) when is_binary(queue_name) do
    from(j in query, where: j.queue == ^queue_name)
  end

  def where_queue(query, job_module) when is_atom(job_module) do
    queue_name =
      job_module
      |> queue_name()
      |> Kernel.to_string()

    where_queue(query, queue_name)
  end

  @doc """
  Filters the query to only include jobs whose arguments contain the given `args` map.

  ## Examples

      OnePiece.Oban.Query.new()
      |> Oban.Query.where_queue(MyApp.ConfirmationEmailJob)
      |> Oban.Query.where_contains_args(%{"user_id" => "user_id"})
      |> Repo.one()
  """
  @spec where_contains_args(query :: Ecto.Queryable.t(), args :: map()) :: Ecto.Query.t()
  def where_contains_args(query, args) do
    from(j in query, where: fragment("? @> ?", j.args, ^args))
  end

  @doc """
  Filters the query to only include jobs which are in the 'scheduled' state, i.e., jobs that are cancellable.

  ## Examples

      OnePiece.Oban.Query.new()
      |> Oban.Query.where_cancellable()
      |> Repo.all()
  """
  @spec where_cancellable(query :: Ecto.Queryable.t()) :: Ecto.Query.t()
  def where_cancellable(query) do
    from(j in query, where: j.state in ~w[scheduled])
  end

  defp queue_name(job_module) do
    Keyword.get(job_module.__opts__(), :queue)
  end
end
