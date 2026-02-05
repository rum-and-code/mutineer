# Mutineer

A chaos engineering library for Elixir inspired by Netflix's Chaos Monkey.
Mutineer allows you to inject controlled, random failures into your functions to
test resilience and error handling.

## Features

- Wrap functions to randomly trigger failures at configurable rates
- Multiple failure types: errors, exceptions, timeouts, nil returns, and process exits
- Minimal runtime overhead when disabled
- Two flexible APIs: attribute-based decorators or explicit macros
- Disabled by default for safety

## Installation

Add `mutineer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mutineer, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure Mutineer in your `config/config.exs` (or environment-specific config):

```elixir
config :mutineer, Mutineer,
  enabled: true,
  default_failure_rate: 0.1,
  default_failure_type: :error
```

## Usage

### Attribute-based API

Add the `use Mutineer` statement to your module.
You can then use the `@chaos` attribute to mark functions for chaos injection:

```elixir
defmodule MyApp.Database do
  use Mutineer

  @chaos failure_rate: 0.2
  def query(sql) do
    # Your database query logic
  end

  @chaos failure_type: :timeout, delay: 3000
  def slow_query(sql) do
    # This will randomly timeout
  end
end
```

### Macro-based API

Use `defchaos` or `defchaosp` (for private functions) for explicit chaos wrapping:

```elixir
defmodule MyApp.ExternalService do
  use Mutineer

  defchaos call_api(endpoint), failure_rate: 0.3, failure_type: :raise do
    # Your API call logic
  end

  defchaosp internal_helper(data), failure_rate: 0.1 do
    # Private function with chaos
  end
end
```

## Failure Types

| Type       | Behavior                                                                                                    |
| ---------- | ----------------------------------------------------------------------------------------------------------- |
| `:error`   | Returns `{:error, :mutineer_chaos}`                                                                         |
| `:raise`   | Raises `Mutineer.ChaosError` exception                                                                      |
| `:delay`   | Introduces a random 1-5 second delay (or custom `delay` in ms) before execution the function                |
| `:timeout` | Introduces a random 1-5 second delay (or custom `delay` in ms) before returning `{:error, :mutineer_chaos}` |
| `:nil`     | Returns `nil`                                                                                               |
| `:exit`    | Calls `exit(:mutineer_chaos)` to crash the process                                                          |
| `:custom`  | Returns a custom error via `custom_error` option                                                            |

## Options

Options can be passed to `@chaos`, `defchaos`, or `defchaosp`:

| Option         | Description                                                   |
| -------------- | ------------------------------------------------------------- |
| `failure_rate` | Probability of failure (0.0 - 1.0)                            |
| `failure_type` | Type of failure to trigger                                    |
| `message`      | Custom message for `:raise` type                              |
| `delay`        | Custom delay in milliseconds for `:timeout` and `:delay` type |
| `custom_error` | Custom error value for `:custom` type                         |

## Example

```elixir
defmodule MyApp.PaymentGateway do
  use Mutineer

  @chaos failure_rate: 0.1, failure_type: :error
  def process_payment(amount, card) do
    # Payment processing logic
    {:ok, %{transaction_id: "txn_123", amount: amount}}
  end

  @chaos failure_rate: 0.05, failure_type: :raise, message: "Gateway timeout"
  def verify_card(card) do
    # Card verification logic
    {:ok, :valid}
  end
end

# In your tests or staging environment:
case MyApp.PaymentGateway.process_payment(100, card) do
  {:ok, result} -> handle_success(result)
  {:error, reason} -> handle_error(reason)
end
```

```elixir
# config/dev.exs
config :mutineer,
  Mutineer,
  enabled: true,
  default_failure_rate: 0.1

# config/prod.exs
config :mutineer,
  Mutineer,
  enabled: false
```
