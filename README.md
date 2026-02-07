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
    {:mutineer, "~> 0.2.0"}
  ]
end
```

## Configuration

Configure Mutineer in your `config/config.exs` (or environment-specific config):

```elixir
config :mutineer, Mutineer,
  enabled: true,
  default_failure_rate: 0.1,
  default_failure_types: :error
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

## Global configuration options

- `enabled` - Enables or disables chaos globally (default: `false`)
- `default_failure_types` - Sets the default failure types for all functions, can be a list of failure types or a single failure type (default: `:error`)
- `default_failure_rate` - Sets the default failure rate for all functions (default: `0.1`)

## Failure Types

- `:error` - Returns `{:error, :mutineer_chaos}` (default) or a random error from the `errors` option
- `:raise` - Raises either a `Mutineer.ChaosError` exception (default) or a custom error specified in the `raised_errors` option
- `:delay` - Introduces a random delay (1-5 seconds) before executing function
- `:timeout` - Same as `:raise`, but with a random delay before raising the exception
- `:nil` - Returns `nil`
- `:exit` - Calls `exit(:mutineer_chaos)`; the atom can be specified in the `exit_errors` option

## Failure Options

Options can be passed to `@chaos`, `defchaos`, or `defchaosp`:

- `failure_rate` is the probability of failure for a given function (`0.0` - `1.0`), where `1.0` or above will always fail
- `failure_types` (or `failure_type`) is either a list of failure types to trigger (e.g. `[:error, :delay]`) or a single failure type (e.g. `:error`)
- `errors` (or `error`) is either a list of objects to be randomly selected from or a single object to return when the `:error` type is triggered
- `raised_errors` (or `raised_error`) is a list of errors to be randomly selected from or a single error to be raised when the `:raise` type is triggered
- `exit_errors` (or `exit_error`) is a list of errors to be randomly selected from or a single error to be raised when the `:exit` type is triggered
- `delay` is the upperbound of the delay in milliseconds or a range of milliseconds for `:timeout` and `:delay` types

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
