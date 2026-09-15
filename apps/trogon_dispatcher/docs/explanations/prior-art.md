# Prior art

Middleware pipelines have been built many times, in many languages, in many problem domains. This page collects the
ones that shaped `Trogon.Dispatcher`, with a working snippet from each, so the design decisions here can be read
against what already exists rather than taken on trust.

The same three questions come up every time, and every project in this page answers them:

1. How does a stage pass control to the rest of the pipeline?
2. How many types travel through it?
3. How does a stage know whether it is on the way in or the way out?

## Two axes, often conflated

**Shape.** A *reduce* pipeline applies each stage in turn: stage N's output is stage N+1's input, and once a stage
returns it is finished. A *wrap* pipeline hands each stage a function representing the rest of the pipeline, so the
stage keeps a frame open across everything downstream. A third family, *hooks*, registers named callbacks and lets
the framework call them at the right moment.

**Type count.** A *one bag* pipeline threads a single value carrying both the request and the response. A *two type*
pipeline takes one type in and returns a different type out.

The axes are orthogonal. Plug is one bag and a reduce. MediatR is two types and a wrap. Koa is one bag and a wrap.
Conflating the two axes is where most of the confusion about these designs comes from.

## The map

| Project | Language | Domain | Shape | Types | Phase signal |
| --- | --- | --- | --- | --- | --- |
| [Commanded](https://hexdocs.pm/commanded/Commanded.Middleware.html) | Elixir | command dispatch | reduce | one (`Pipeline`) | **explicit callbacks** |
| [MediatR](https://github.com/jbogard/MediatR/wiki/Behaviors) | C# | command dispatch | wrap | two | position |
| [Brighter](https://github.com/BrighterCommand/Brighter) | C# | command dispatch | wrap | one (the request) | position |
| [MassTransit](https://masstransit.io/documentation/configuration/middleware) | C# | message dispatch | wrap | one (`ConsumeContext`) | position |
| [NServiceBus](https://docs.particular.net/nservicebus/pipeline/manipulate-with-behaviors) | C# | message dispatch | wrap | one (context per stage) | position |
| [Axon](https://docs.axoniq.io/) | Java | command dispatch | wrap | one (`UnitOfWork`) | position |
| [Redux](https://redux.js.org/understanding/history-and-design/middleware) | JS | action dispatch | wrap | two | position |
| [Plug](https://hexdocs.pm/plug/Plug.html) | Elixir | HTTP server | reduce | one (`conn`) | no return trip |
| [Absinthe](https://hexdocs.pm/absinthe/Absinthe.Middleware.html) | Elixir | GraphQL | reduce | one (`Resolution`) | `:state` field |
| [Rack](https://github.com/rack/rack/blob/main/SPEC.rdoc) | Ruby | HTTP server | wrap | two | position |
| [Ring](https://github.com/ring-clojure/ring/wiki/Concepts) | Clojure | HTTP server | wrap | two | position |
| [WSGI](https://peps.python.org/pep-3333/) | Python | HTTP server | wrap | two | position |
| [ASGI](https://asgi.readthedocs.io/) | Python | HTTP server | wrap | messages | **message type** |
| [Starlette](https://www.starlette.io/middleware/) | Python | HTTP server | wrap | two | position |
| [Django](https://docs.djangoproject.com/en/stable/topics/http/middleware/) | Python | HTTP server | wrap | two | position |
| [Flask](https://flask.palletsprojects.com/en/stable/lifecycle/) | Python | HTTP server | hooks | two | **explicit decorators** |
| [Scrapy](https://docs.scrapy.org/en/latest/topics/downloader-middleware.html) | Python | scraping | hooks | two | **explicit methods** |
| [Koa](https://github.com/koajs/koa) | JS | HTTP server | wrap | one (`ctx`) | position |
| [Hono](https://hono.dev/docs/guides/middleware) | JS | HTTP server | wrap | one (`c`) | position |
| [Express](https://expressjs.com/en/guide/writing-middleware.html) | JS | HTTP server | reduce | two | no return trip |
| [Fastify](https://fastify.dev/docs/latest/Reference/Hooks/) | JS | HTTP server | hooks | two | **explicit hooks** |
| [NestJS](https://docs.nestjs.com/interceptors) | JS | HTTP server | wrap | two | position (RxJS) |
| [tRPC](https://trpc.io/docs/server/middlewares) | TS | RPC | wrap | two | position |
| [ASP.NET Core](https://learn.microsoft.com/aspnet/core/fundamentals/middleware/) | C# | HTTP server | wrap | one (`HttpContext`) | position |
| [Servlet Filter](https://jakarta.ee/specifications/servlet/) | Java | HTTP server | wrap | two | position |
| [Spring `HandlerInterceptor`](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-config/interceptors.html) | Java | HTTP server | hooks | two | **explicit methods** |
| [Ktor](https://ktor.io/docs/server-custom-plugins.html) | Kotlin | HTTP server | wrap | one (`ApplicationCall`) | position (+ named phases for order) |
| [net/http](https://pkg.go.dev/net/http#Handler) | Go | HTTP server | wrap | two | position, response is a sink |
| [Gin](https://gin-gonic.com/docs/examples/custom-middleware/) | Go | HTTP server | wrap | one (`*gin.Context`) | position |
| [Echo](https://echo.labstack.com/docs/middleware) | Go | HTTP server | wrap | one (`echo.Context`) | position |
| [gRPC interceptors](https://github.com/grpc/grpc-go/blob/master/examples/features/interceptor/README.md) | Go | RPC | wrap | two | position |
| [tower](https://docs.rs/tower/latest/tower/trait.Service.html) | Rust | services | wrap | two | position |
| [axum](https://docs.rs/axum/latest/axum/middleware/index.html) | Rust | HTTP server | wrap | two | position |
| [actix-web](https://actix.rs/docs/middleware/) | Rust | HTTP server | wrap | two | position |
| [PSR-15](https://www.php-fig.org/psr/psr-15/) | PHP | HTTP server | wrap | two | position |
| [Laravel](https://laravel.com/docs/middleware) | PHP | HTTP server | wrap | two | position |
| [Vapor](https://docs.vapor.codes/advanced/middleware/) | Swift | HTTP server | wrap | two | position |
| [Rails callbacks](https://guides.rubyonrails.org/action_controller_overview.html#filters) | Ruby | HTTP server | both | two | **both** |
| [Tesla](https://hexdocs.pm/tesla/Tesla.Middleware.html) | Elixir | HTTP client | wrap | one (`Tesla.Env`) | position |
| [OkHttp](https://square.github.io/okhttp/features/interceptors/) | Java | HTTP client | wrap | two | position |
| [Faraday](https://lostisland.github.io/faraday/#/middleware/index) | Ruby | HTTP client | wrap | one (`Faraday::Env`) | **explicit callbacks** |
| [Axios](https://axios-http.com/docs/interceptors) | JS | HTTP client | hooks | two | **two registries** |
| [Apollo Link](https://www.apollographql.com/docs/react/api/link/introduction) | JS | GraphQL client | wrap | two | position |
| [`DelegatingHandler`](https://learn.microsoft.com/dotnet/api/system.net.http.delegatinghandler) | C# | HTTP client | wrap | two | position |
| [Sidekiq](https://github.com/sidekiq/sidekiq/wiki/Middleware) | Ruby | jobs | wrap | one (the job) | position (`yield`) |
| [Middy](https://middy.js.org/docs/intro/how-it-works) | JS | lambda | hooks | two | **explicit hooks** |
| [Netty](https://netty.io/4.1/api/io/netty/channel/ChannelPipeline.html) | Java | network | hooks | messages | **two interfaces** |
| [Envoy](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/http_filters) | C++ | proxy | hooks | messages | **decode vs encode** |
| **Trogon.Dispatcher** | Elixir | command dispatch | wrap | one (`Context`) | position |

## Command and message dispatchers

The closest family to this library. Worth noting how few of them agree.

### Commanded (Elixir)

The direct ancestor, and the design this library was asked to be architecture-neutral about.
`Commanded.Middleware.Pipeline` is **one struct carrying the response**, with `correlation_id`, `causation_id`,
`assigns`, `halted` and `response` fields. The lineage of `Trogon.Dispatcher.Context` is obvious.

```elixir
defmodule MyApp.Middleware.Validate do
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Commanded.Middleware.Pipeline

  def before_dispatch(%Pipeline{command: command} = pipeline) do
    case MyApp.Validator.validate(command) do
      :ok -> pipeline
      {:error, reason} -> pipeline |> respond({:error, reason}) |> halt()
    end
  end

  def after_dispatch(pipeline), do: pipeline
  def after_failure(pipeline), do: pipeline
end
```

Commanded proved the one-struct-carrying-a-response shape in this exact problem domain. What this library changes is
only the *shape*: three callbacks and a `halted` flag become one callback and an explicit `next`. Everything
`before_dispatch` did happens before `next.(context)`, everything `after_dispatch` did happens after it, and
`after_failure` is a `try/rescue` around it, in one function body with no state stashed between calls.

### MediatR (C#)

The canonical mediator in .NET, and the design most often cited when people ask for "a dispatcher". Its pipeline
behaviour is a wrap, but across two generic parameters.

```csharp
public class LoggingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        var sw = Stopwatch.StartNew();
        var response = await next();
        _logger.LogInformation("{Request} took {Ms}ms", typeof(TRequest).Name, sw.ElapsedMilliseconds);
        return response;
    }
}
```

Two details matter. First, `next()` takes **no argument**: a behaviour cannot hand a modified request downstream, it
can only mutate the object in place. Second, MediatR has no context object at all, so ambient data such as a tenant
or a correlation id travels by DI-scoped services or `AsyncLocal`, outside the pipeline entirely.

MediatR also offers separate one-leg interfaces:

```csharp
public interface IRequestPreProcessor<in TRequest>
{
    Task Process(TRequest request, CancellationToken cancellationToken);
}

public interface IRequestPostProcessor<in TRequest, in TResponse>
{
    Task Process(TRequest request, TResponse response, CancellationToken cancellationToken);
}
```

The post-processor has to be handed *both* the request and the response to be useful. Splitting the type means
re-joining it at the point of use.

### MassTransit (C#)

Explicitly models itself on pipes and filters, and lands on one context type per pipeline with a wrap.

```csharp
public class TimerFilter<T> : IFilter<ConsumeContext<T>> where T : class
{
    public async Task Send(ConsumeContext<T> context, IPipe<ConsumeContext<T>> next)
    {
        var sw = Stopwatch.StartNew();
        await next.Send(context);
        _log.LogInformation("{MessageType} took {Elapsed}", typeof(T).Name, sw.Elapsed);
    }
}
```

`Send(context, next)` is the same arity and the same meaning as this library's `call(context, next, options)`.

### NServiceBus (C#)

Same conclusion, different vocabulary. A behaviour wraps, over a context type that is specific to the pipeline stage
it runs in, and each context carries an `Extensions` bag for cross-cutting data.

```csharp
public class TimerBehavior : Behavior<IIncomingLogicalMessageContext>
{
    public override async Task Invoke(IIncomingLogicalMessageContext context, Func<Task> next)
    {
        var sw = Stopwatch.StartNew();
        await next();
        log.Info($"{context.Message.MessageType.Name} took {sw.Elapsed}");
    }
}
```

Note that `next` takes no argument here, as in MediatR, because the context is mutable and shared.

### Brighter (C#)

A command processor whose handler returns the request it was given, making the pipeline one type end to end.
Attributes declare the middleware and its order.

```csharp
public class GreetingCommandHandler : RequestHandler<GreetingCommand>
{
    [RequestLogging(step: 1, timing: HandlerTiming.Before)]
    [UsePolicy(CommandProcessor.RETRYPOLICY, step: 2)]
    public override GreetingCommand Handle(GreetingCommand command)
    {
        Console.WriteLine($"Hello {command.Name}");
        return base.Handle(command);
    }
}
```

Brighter also ships an `IRequestContext` with a `Bag` dictionary, for exactly the cross-cutting data problem that
`Context.assigns` and `Context.private` solve here.

### Axon (Java)

The JVM's CQRS framework. Interceptors wrap, over a `UnitOfWork` that is the one-bag context, and they are split by
*direction of travel* rather than by phase: `MessageDispatchInterceptor` on the way out of a sender,
`MessageHandlerInterceptor` on the way in to a handler.

```java
public class TimerInterceptor implements MessageHandlerInterceptor<CommandMessage<?>> {
    @Override
    public Object handle(UnitOfWork<? extends CommandMessage<?>> unitOfWork,
                         InterceptorChain chain) throws Exception {
        long start = System.nanoTime();
        Object result = chain.proceed();
        log.info("took {}ns", System.nanoTime() - start);
        return result;
    }
}
```

`UnitOfWork` also carries a resource map, which is Axon's `assigns`.

### Redux (JS)

The most widely read middleware signature in the industry, and a dispatcher rather than an HTTP pipeline. Curried
three times: store, then next, then action.

```js
const logger = store => next => action => {
  console.log('dispatching', action)
  const result = next(action)
  console.log('next state', store.getState())
  return result
}
```

Two types (an action in, a result out) and a wrap. Redux has no context object, so ambient data comes from `store`,
captured in the outermost closure. That is the same answer MediatR gives with DI, reached independently.

## HTTP server pipelines

### Plug (Elixir)

One type, but a reduce, which is the combination this library deliberately did not take.

```elixir
def call(conn, _opts) do
  if authorized?(conn) do
    assign(conn, :user, current_user(conn))
  else
    conn |> send_resp(401, "") |> halt()
  end
end
```

Two consequences fall out of the reduce shape, and both are instructive:

- `halt/1` has to exist. A reduce cannot stop on its own, so halting is a flag on the struct that `Plug.Builder`
  checks between stages. A wrap needs no flag: not calling `next` *is* the stop.
- `Plug.Conn.register_before_send/2` has to exist. A reduce has no upstream leg, so getting one back means
  registering callbacks that fire later.

```elixir
register_before_send(conn, fn conn ->
  put_resp_header(conn, "x-runtime", to_string(elapsed()))
end)
```

### Koa (JS)

Koa was written as a reaction to Express, and collapsing `req` and `res` into one `ctx` is its headline feature. The
docs call the two legs "downstream" and "upstream".

```js
app.use(async (ctx, next) => {
  const start = Date.now()
  await next()                                              // downstream
  ctx.set('X-Response-Time', `${Date.now() - start}ms`)     // upstream
})
```

No phase flag, no halt flag. Not calling `await next()` is the halt. Hono, a modern successor, kept the shape
exactly, down to the name of the context variable.

### Express (JS)

The most widely used, and the weakest on the upstream leg. There is no return trip at all, so observing the response
means subscribing to an event:

```js
app.use((req, res, next) => {
  const start = Date.now()
  res.on('finish', () => console.log(`${res.statusCode} in ${Date.now() - start}ms`))
  next()
})
```

Koa exists because of this.

### Rack (Ruby) and Ring (Clojure)

The ancestors of most of this list. Rack takes a hash in and returns a three-element array:

```ruby
class Timer
  def initialize(app)
    @app = app
  end

  def call(env)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    headers["x-runtime"] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to_s
    [status, headers, body]
  end
end
```

Ring is the same idea with maps, and makes the wrapping shape most obvious of anything here, because a Ring
middleware is literally a function that returns a function:

```clojure
(defn wrap-timer [handler]
  (fn [request]
    (let [start (System/nanoTime)
          response (handler request)]
      (assoc-in response [:headers "x-runtime"] (str (- (System/nanoTime) start))))))
```

In both, the request half is a one-bag map where every middleware stashes cross-cutting data, and the response half
has nowhere to put annotations.

### Django (Python)

The strongest single piece of evidence against an explicit phase marker, because Django shipped one and removed it.

Before 1.10, middleware declared its phases as separate methods:

```python
class TimerMiddleware:
    def process_request(self, request):
        request.start = time.monotonic()

    def process_response(self, request, response):
        response["X-Runtime"] = str(time.monotonic() - request.start)
        return response
```

From 1.10 on, middleware is a wrap and the phases are positional:

```python
def timer_middleware(get_response):
    def middleware(request):
        start = time.monotonic()
        response = get_response(request)
        response["X-Runtime"] = str(time.monotonic() - start)
        return response

    return middleware
```

The old style needed `process_request`, `process_response`, `process_view` and `process_template_response`, each
with its own ordering rule. The replacement needs none of them, because position says everything the four method
names used to say.

### ASGI (Python)

The interesting outlier: a streaming protocol, so there is no single response value to return. Phase is known by
**message type**, and the middleware wraps `send` rather than wrapping a call.

```python
class TimerMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        start = time.monotonic()

        async def send_wrapper(message):
            if message["type"] == "http.response.start":
                elapsed = str(time.monotonic() - start).encode()
                message["headers"].append((b"x-runtime", elapsed))
            await send(message)

        await self.app(scope, receive, send_wrapper)
```

This is the honest case for an explicit phase marker, and note what makes it honest: the response arrives in pieces
over time, so position genuinely cannot tell you where you are. A synchronous, single-response dispatch has no such
problem.

### ASP.NET Core (C#)

`HttpContext` carries `.Request`, `.Response`, and `.Items`, a bag that is the direct analogue of `Context.assigns`.

```csharp
app.Use(async (context, next) =>
{
    var sw = Stopwatch.StartNew();
    await next(context);
    logger.LogInformation("{Path} {Status} in {Ms}ms",
        context.Request.Path, context.Response.StatusCode, sw.ElapsedMilliseconds);
});
```

C# contains both models: this, and MediatR above.

### Go: net/http, and Gin

The cautionary tale first. In `net/http` the response is not a value, it is a sink you write into, so there is no
way to observe it after calling downstream. Every logging and metrics middleware in Go hand-rolls the same wrapper:

```go
type statusRecorder struct {
    http.ResponseWriter
    status int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.status = code
    r.ResponseWriter.WriteHeader(code)
}

func Timer(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
        next.ServeHTTP(rec, r)
        log.Printf("%d in %s", rec.status, time.Since(start))
    })
}
```

Go's forward channel, by contrast, is excellent, and its shape is the one this library copied for `assigns`: an
immutable value, threaded explicitly, carried on the request rather than in a global.

```go
ctx := context.WithValue(r.Context(), tenantKey, tenant)
next.ServeHTTP(w, r.WithContext(ctx))
```

Gin routes around the problem with one context object, and shows what happens when a framework hedges between the
two shapes. `c.Next()` advances an index into a handler slice, which is a wrap wearing a reduce's clothes, and
because it is really an index, Gin still needs `c.Abort()`:

```go
func Timer() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        c.Next()
        log.Printf("%d in %s", c.Writer.Status(), time.Since(start))
    }
}
```

### Java: Servlet Filter and Spring `HandlerInterceptor`

Java ships both answers in the same framework. `Filter` is a wrap:

```java
public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
        throws IOException, ServletException {
    long start = System.nanoTime();
    chain.doFilter(req, res);
    log.info("took {}ns", System.nanoTime() - start);
}
```

`HandlerInterceptor` is not, so it needs explicit phase methods:

```java
public interface HandlerInterceptor {
    default boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        return true;
    }

    default void postHandle(HttpServletRequest request, HttpServletResponse response,
                            Object handler, ModelAndView modelAndView) {
    }

    default void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                 Object handler, Exception ex) {
    }
}
```

`preHandle` returns `boolean` rather than simply not continuing. That is the same tax as Plug's `halt/1`: a shape
that cannot express stopping has to encode it.

### PSR-15 (PHP)

The most precisely specified two-type wrap in this list, and worth reading for that reason.

```php
public function process(ServerRequestInterface $request, RequestHandlerInterface $handler): ResponseInterface
{
    $start = microtime(true);
    $response = $handler->handle($request);

    return $response->withHeader('X-Runtime', (string) (microtime(true) - $start));
}
```

Laravel's is the same shape with a closure instead of an interface:

```php
public function handle(Request $request, Closure $next)
{
    $response = $next($request);

    return $response->header('X-Runtime', microtime(true) - LARAVEL_START);
}
```

### Rust: tower, axum, actix-web

`tower` is the foundation, with two types as associated types on the trait:

```rust
pub trait Service<Request> {
    type Response;
    type Error;
    type Future: Future<Output = Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>>;
    fn call(&mut self, req: Request) -> Self::Future;
}
```

`axum` sands this down to a function, which reads almost exactly like Koa with two types instead of one:

```rust
async fn timer(req: Request, next: Next) -> Response {
    let start = Instant::now();
    let mut res = next.run(req).await;
    res.headers_mut().insert("x-runtime", elapsed_header(start));
    res
}
```

The interesting part is what the `http` crate had to add. `Extensions` is a typed map, and it lives on **both**
`Request` and `Response`, precisely so a service can annotate either leg:

```rust
req.extensions_mut().insert(TenantId(tenant));
// ... and on the way back
res.extensions_mut().insert(Elapsed(start.elapsed()));
```

Two types means two annotation bags. One type means one.

### Ktor (Kotlin)

Worth singling out because it separates two things most frameworks confuse. Ktor has one bag (`ApplicationCall`,
holding `.request` and `.response`), a wrap (`proceed()`), **and** named phases. But the phases are about
*ordering* between plugins, not about which leg you are on:

```kotlin
val Timer = createApplicationPlugin(name = "Timer") {
    onCall { call ->
        call.attributes.put(startKey, System.nanoTime())
    }
    onCallRespond { call, _ ->
        val elapsed = System.nanoTime() - call.attributes[startKey]
        call.response.headers.append("X-Runtime", elapsed.toString())
    }
}
```

Named phases for ordering is a real problem worth solving. It is not the same problem as knowing which leg you are
on, and this library solves ordering by declaration order at compile time instead.

### Rails callbacks (Ruby)

Rails is the clearest demonstration that when a framework offers both, the wrap is what people reach for when they
need both legs.

```ruby
class ApplicationController < ActionController::Base
  before_action :authenticate
  after_action  :log

  around_action :timer

  private

  def timer
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Rails.logger.info(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)
  end
end
```

`before_action` and `after_action` are hooks. `around_action` is a wrap, using `yield` as `next`. Anything needing
both legs at once has to be `around_action`, because the hook pair cannot hold state between them without an
instance variable.

## HTTP and RPC clients

The same problem, solved again, usually by different people.

### Tesla (Elixir)

The closest relative in shape, and the direct model for this library's `call/3`. `Tesla.Env` is one struct holding
both the request (`:method`, `:url`, `:body`) and the response (`:status`, `:body`). `:status` is `nil` on the way
in and set on the way out, which is precisely how `Context.response` behaves here.

```elixir
defmodule Tesla.Middleware.Timer do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    start = System.monotonic_time()

    with {:ok, env} <- Tesla.run(env, next) do
      {:ok, Tesla.put_opt(env, :duration, System.monotonic_time() - start)}
    end
  end
end
```

`Trogon.Dispatcher` differs only in returning a bare context rather than a `{:ok, env}` tuple, because the response
contract already lives in `Context.response`.

### OkHttp (Java)

The cleanest two-type wrap in this list, and notably `chain.proceed(request)` *does* take the request, so an
interceptor can replace it on the way down, unlike MediatR.

```java
class TimerInterceptor implements Interceptor {
    @Override public Response intercept(Chain chain) throws IOException {
        Request request = chain.request();

        long start = System.nanoTime();
        Response response = chain.proceed(request);
        logger.info("took {}ns", System.nanoTime() - start);

        return response;
    }
}
```

### Faraday (Ruby)

One bag (`Faraday::Env` carries `method`, `url`, `request_body`, `status` and `response_body`), but explicit
callbacks rather than position:

```ruby
class Timer < Faraday::Middleware
  def on_request(env)
    env[:start] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def on_complete(env)
    puts "#{env.status} in #{Process.clock_gettime(Process::CLOCK_MONOTONIC) - env[:start]}"
  end
end
```

This is the closest thing in this page to the one-bag-plus-explicit-phase design, and it shows the cost: the start
time has to be stashed *in the bag* to survive between the two callbacks. A wrap keeps it in a local variable.

### Axios (JS) and `DelegatingHandler` (C#)

Axios splits the two legs into two separate registries, which makes correlating them the user's problem:

```js
axios.interceptors.request.use(config => {
  config.metadata = { start: Date.now() }
  return config
})

axios.interceptors.response.use(response => {
  console.log(Date.now() - response.config.metadata.start)
  return response
})
```

Note `config.metadata`, invented by the user to carry state across the split. Compare `DelegatingHandler`, which is
a plain wrap and needs no such thing:

```csharp
protected override async Task<HttpResponseMessage> SendAsync(
    HttpRequestMessage request, CancellationToken cancellationToken)
{
    var sw = Stopwatch.StartNew();
    var response = await base.SendAsync(request, cancellationToken);
    _logger.LogInformation("{Uri} in {Ms}ms", request.RequestUri, sw.ElapsedMilliseconds);

    return response;
}
```

Same language family, same company's ecosystem, opposite conclusions.

## Jobs, GraphQL, and the network layer

### Sidekiq (Ruby)

The most idiomatic wrap in this page: `yield` is `next`.

```ruby
class TimerMiddleware
  include Sidekiq::ServerMiddleware

  def call(job_instance, job_payload, queue)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    logger.info("#{job_payload['class']} took #{Process.clock_gettime(Process::CLOCK_MONOTONIC) - start}")
  end
end
```

Not calling `yield` drops the job. No halt flag anywhere.

### Absinthe (Elixir)

One type, a reduce, and an explicit `:state` field on the resolution, which is what a one-bag reduce needs in place
of `halt/1`.

```elixir
defmodule MyApp.Middleware.Authorize do
  @behaviour Absinthe.Middleware

  def call(%{context: %{current_user: nil}} = resolution, _config) do
    Absinthe.Resolution.put_result(resolution, {:error, "unauthorized"})
  end

  def call(resolution, _config), do: resolution
end
```

Worth comparing directly with `Trogon.Dispatcher`: same one-type discipline, same "put the result on the struct"
move, but a reduce, so it needs the state field.

### Netty (Java) and Envoy (C++)

The far end of the spectrum: the two directions are not two phases of one interface, they are two different
interfaces. Netty has `ChannelInboundHandler` and `ChannelOutboundHandler`, and a handler that wants both implements
both. Envoy HTTP filters have `decodeHeaders` and `encodeHeaders`.

This is the right answer at that layer, for the same reason as ASGI: data arrives in frames over time, connections
are long-lived, and there is no single call whose position could tell you anything. It is the wrong answer for a
synchronous single-response dispatch, and it is useful to know exactly why the difference exists.

## What recurs

Reading all of them together, four patterns show up repeatedly.

**Explicit phase markers appear only where position cannot work.** Spring `HandlerInterceptor`, Flask, Fastify,
Scrapy, Axios, Middy, Netty and Envoy all split the legs, and every one of them is either a hook registry or a
streaming protocol. No wrapping single-response pipeline in this page carries a phase flag. Django had one and
removed it. Rails has both and the wrap is what you reach for when you need both legs.

**Two-type designs grow a backward channel afterwards, and grow it badly.** Go's hand-rolled `statusRecorder`,
tower's second `Extensions` map, Plug's `register_before_send/2`, MediatR's post-processor needing the request
handed back, Axios's user-invented `config.metadata`. Five ecosystems, same bolt-on.

**A shape that cannot stop has to encode stopping.** Plug's `halt/1`, Absinthe's `:state`, Spring's
`preHandle -> boolean`, Gin's `c.Abort()`, Commanded's `halted`. Every one of those is a reduce or a hook registry.
No wrap in this page needs one.

**Ecosystems that ran the experiment twice moved toward one bag.** Rack to Plug. Express to Koa. Express to Hono.
`req`/`res` to `HttpContext`. The move is always in that direction and never back.

## What this library took, and what it left

**Took the wrap**, from Koa, Tesla, MediatR, MassTransit, OkHttp and Sidekiq. Timing, spans, `try/rescue` and retry
all need a frame held open across the rest of the pipeline, and only a wrap gives that. It also means no `halt/1`
and no `halted` field: not calling `next` is the halt, and it is visible in the code instead of encoded in a flag.

**Took the one bag**, from Commanded, Koa, Tesla, ASP.NET Core, MassTransit and Plug. `Trogon.Dispatcher.Context`
carries the message and the response on one struct, exactly as `Commanded.Middleware.Pipeline` and `Tesla.Env` do.

**Took `assigns` and `private` from Plug**, the namespaced-by-owner convention from `Plug.Conn.private`, and the
immutable explicit threading style from Go's `context.Context`.

**Took compile-time composition** from Plug's `Plug.Builder` and Brighter's attributes, rather than building the
chain per dispatch.

**Left the explicit phase marker**, for the reasons the survey makes plain. In a wrap, the line above `next.()` is
the request phase and the line below is the response phase.

**Left the reduce**, and with it `halt/1`, `register_before_send/2`, `:state`, `c.Abort()` and the
`preHandle -> boolean` convention. Each is a workaround for something the wrapping shape gets for free.

**Left the split callbacks**, which Commanded, Faraday, Axios and Spring all use. The cost is visible in every one
of those examples: state that belongs in a local variable has to be stashed somewhere that survives between calls.

## See also

- [Why wrapping middleware](why-wrapping-middleware.md) for the argument in this library's own terms.
- [The response contract](../references/response-contract.md) for where the response lives on the context.
- [Write a middleware](../how-to/write-middleware.md) for the practical version.
