# Ratex

## Challenge
Access to most Web APIs (e.g Facebook, Instagram) are rate-limited. Which means your client app can access the service only so many times within a given period. Accessing more than maximum allowed number of requests can result termination of your app's access to the service and/or break your client app.

## Approach
Develop a library that keeps track of rate limits, pause access to the API when rate limit is reached and resume when necessary.
The library can start and manage multiple clients with different access tokens to the same service. In that case we switch between workers as they reach their respective limits.



# Example

```elixir

defmodule InstagramWorker do
  use Ratex.RateWorker,
  rate_limit: 250, # 250 api requests
  rate_seconds: 3600 # per hour

  # override work/2 to handle work sent by the client manager
  # must result a Ratex.WorkerResult struct
  def work(payload, worker_state)do

    token = worker_state.token
    # use token to get result from instagram service
    {:ok, Ratex.WorkerResult{...}}
  end

  def on_init(options) do
    # do additional initialization for the worker
    # and return a map
    %{options: options, token: options[:token]}
  end

end
defmodule InstagramClient do
  use Ratex.RateManager,
  pool_name: :ig_client,
  worker_module: InstagramWorker
  
end



iex> InstagramClient.instance()
iex> data = "instagram"
iex> key = "username"
iex> InstagramClient.add_item({key, data})

iex> InstagramClient.add_worker(%{token: <<Instagram token>>})




```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ratex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ratex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ratex](https://hexdocs.pm/ratex).

