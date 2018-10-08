# Ratex

**TODO: Add description**

## Problem
Access to most Web APIs (e.g Facebook, Instagram) are rate-limited. Which means your client app can access the service only so many times within a given period. Accessing more than maximum allowed number of requests can result termination of your app's access to the service and/or break your client app.

## Solution
Develop a library that keeps track of rate limits, pause access to the API when rate limit is reached and resume when necessary.
Library can start and manage multiple clients with different access tokens to the same service. In that case we switch between workers as they reach their respective limits.

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

