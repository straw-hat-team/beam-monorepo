defmodule Inngest.SdkRequestStack do
  @derive [Jason.Encoder]
  defstruct [:current, :stack]
end

defmodule Inngest.SdkRequestCtx do
  @derive [Jason.Encoder]
  defstruct [:env, :fn_id, :run_id, :step_id, :stack]
end

defmodule Inngest.SdkRequest do
  @derive [Jason.Encoder]
  defstruct [:event, :steps, :ctx]
end

defmodule Inngest.EventTrigger do
  @derive [Jason.Encoder]
  defstruct [:event, :expression]
end

defmodule Inngest.Input do
  @derive [Jason.Encoder]
  defstruct [:event, :ctx]
end

defmodule Inngest.InputContext do
  @derive [Jason.Encoder]
  defstruct [:fn_id, :run_id, :step_id]
end

defmodule Inngest.RateLimit do
  @derive [Jason.Encoder]
  defstruct [:limit, :period, :key]
end

defmodule Inngest.Cancel do
  @derive [Jason.Encoder]
  defstruct [:event, :timeout, :if]
end

defmodule Inngest.CronTrigger do
  @derive [Jason.Encoder]
  defstruct [:cron]
end

defmodule Inngest.StepRetries do
  @derive [Jason.Encoder]
  defstruct [:attempts]
end

defmodule Inngest.SdkStep do
  @derive [Jason.Encoder]
  defstruct [
    :name,
    :id,
    :runtime,
    :retries
  ]
end

defmodule Inngest.FunctionRegistration do
  defstruct [
    :name,
    :id,
    :trigger,
    :concurrency,
    :idempotency,
    :retries,
    :callback
  ]
end

defmodule Inngest.SdkFunction do
  @derive [Jason.Encoder]
  defstruct [
    :name,
    :id,
    :trigger,
    :concurrency,
    :idempotency,
    :rateLimit,
    :retries,
    :cancel,
    :steps
  ]
end

defmodule Inngest.Headers do
  @derive [Jason.Encoder]
  defstruct [:env, :platform]
end

defmodule Inngest.RegisterRequest do
  @derive [Jason.Encoder]
  defstruct [
    :url,
    :v,
    :deployType,
    :sdk,
    :framework,
    :appName,
    :functions,
    :headers
  ]
end
