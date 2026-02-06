defmodule Mutineer do
  @moduledoc """
    Mutineer macro system for introducing controlled failures into functions.

    This module provides macros to wrap functions and make them fail randomly,
    inspired by Netflix's Chaos Monkey. Useful for testing resilience and
    error handling in development and staging environments.

    ## Configuration

    Configure in `config/config.exs` or environment-specific config files:

        # Enable Mutineer globally
        config :mutineer,
          Mutineer,
          enabled: true,
          default_failure_rate: 0.1,  # 10% failure rate
          default_failure_type: :error

    ## Usage

    Use the `@chaos` attribute before function definitions:

        defmodule MyModule do
          use Mutineer

          # Will fail 10% of the time with default settings
          @chaos true
          def my_function(arg) do
            # normal implementation
          end

          # Custom failure rate (30%)
          @chaos failure_rate: 0.3
          def risky_function(arg) do
            # normal implementation
          end

          # Custom failure type and message
          @chaos failure_rate: 0.2, failure_type: :raise, message: "Chaos!"
          def another_function(arg) do
            # normal implementation
          end
        end

    Or use the `defchaos` macro directly:

        defmodule MyModule do
          use Mutineer

          defchaos my_function(arg), failure_rate: 0.2 do
            # normal implementation
          end
        end

    ## Failure Types

    - `:error` - Returns `{:error, :mutineer_chaos}` (default)
    - `:custom` - Returns a custom error object specified in the `custom_error` option (defaults to `{:error, :mutineer_chaos}`)
    - `:raise` - Raises a `Mutineer.ChaosError` exception
    - `:delay` - Introduces a random delay (1-5 seconds) before executing function
    - `:timeout` - Introduces a random delay (1-5 seconds) before failing
    - `:nil` - Returns `nil`
    - `:exit` - Calls `exit(:mutineer_chaos)`

    ## Important Notes

    - Mutineer is **disabled by default**
    - When disabled at runtime, functions execute normally with minimal overhead
    - Recommended to only enable in development/staging environments
    - Never enable in production unless you know what you're doing
    """

  defmodule ChaosError do
    @moduledoc """
    Exception raised when Mutineer triggers a failure with `:raise` type.
    """
    defexception [:message, :function, :module]

    @impl true
    def message(%{message: message, function: function, module: module}) do
      "Mutiny triggered in #{inspect(module)}.#{function}: #{message}"
    end
  end

  @doc """
  Returns whether Mutineer is globally enabled at runtime.
  """
  def enabled? do
    config()[:enabled] == true
  end

  @doc """
  Returns the default failure rate (0.0 to 1.0).
  """
  def default_failure_rate do
    config()[:default_failure_rate] || 0.1
  end

  @doc """
  Returns the default failure type.
  """
  def default_failure_type do
    config()[:default_failure_type] || :error
  end

  @doc """
  Determines if a failure should be triggered based on the given rate.
  """
  def should_fail?(rate) when is_float(rate) and rate >= 0.0 and rate <= 1.0 do
    :rand.uniform() < rate
  end

  def should_fail?(rate) when is_integer(rate) and rate in [0, 1] do
    should_fail?(rate * 1.0)
  end

  @doc """
  Triggers a failure of the specified type.
  """
  def trigger_failure(:error, _func, _opts), do: {:error, :mutineer_chaos}

  def trigger_failure(:custom, _func, opts) do
    opts[:custom_error] || {:error, :mutineer_chaos}
  end

  def trigger_failure(:raise, _func, opts) do
    raise ChaosError,
      message: opts[:message] || "Mutiny!",
      function: opts[:function],
      module: opts[:module]
  end

  def trigger_failure(:delay, func, opts) do
    delay = Keyword.get(opts, :delay, :rand.uniform(4000) + 1000)
    Process.sleep(delay)
    func.()
  end

  def trigger_failure(:timeout, _func, opts) do
    delay = Keyword.get(opts, :delay, :rand.uniform(4000) + 1000)
    Process.sleep(delay)
    {:error, :mutineer_chaos}
  end

  def trigger_failure(:nil, _func, _opts), do: nil

  def trigger_failure(:exit, _func, _opts), do: exit(:mutineer_chaos)

  defp config do
    Application.get_env(:mutineer, __MODULE__, [])
  end

  @doc """
  Wraps a function call with Mutineer logic.

  This is the runtime function that checks if chaos should trigger.
  When chaos is disabled, immediately executes the function with minimal overhead.
  """
  def maybe_chaos(func, opts) when is_function(func, 0) do
    if enabled?() do
      failure_rate = Keyword.get(opts, :failure_rate, default_failure_rate())
      failure_type = Keyword.get(opts, :failure_type, default_failure_type())

      if should_fail?(failure_rate) do
        trigger_failure(failure_type, func, opts)
      else
        func.()
      end
    else
      func.()
    end
  end

  defmacro __using__(_opts) do
    quote do
      import Mutineer, only: [defchaos: 2, defchaos: 3, defchaosp: 2, defchaosp: 3]
      Module.register_attribute(__MODULE__, :chaos, accumulate: false)
      @on_definition Mutineer
      @before_compile Mutineer
    end
  end

  @doc """
  Defines a public function that may randomly fail when Mutineer is enabled.

  ## Options

  - `:failure_rate` - Probability of failure (0.0 to 1.0), defaults to global setting
  - `:failure_type` - Type of failure (`:error`, `:raise`, `:timeout`, `:nil`, `:exit`)
  - `:message` - Custom error message for `:raise` type
  - `:delay` - Custom delay in ms for `:timeout` type
  - `:custom_error` - Custom error object for `:custom` type

  ## Examples

      defchaos my_function(arg1, arg2), failure_rate: 0.2 do
        # function body
      end

      defchaos api_call(url), failure_type: :timeout, delay: 3000 do
        # function body
      end
  """
  defmacro defchaos(call, expr_or_opts) do
    {body, chaos_opts} = resolve_expr_or_opts(expr_or_opts)
    define_chaos_function(:def, call, body, chaos_opts)
  end

  defmacro defchaos(call, opts, expr) do
    define_chaos_function(:def, call, expr, opts)
  end

  @doc """
  Defines a private function that may randomly fail when Mutineer is enabled.

  Same options as `defchaos/2`.
  """
  defmacro defchaosp(call, expr_or_opts) do
    {body, chaos_opts} = resolve_expr_or_opts(expr_or_opts)
    define_chaos_function(:defp, call, body, chaos_opts)
  end

  defmacro defchaosp(call, opts, expr) do
    define_chaos_function(:defp, call, expr, opts)
  end

  defp resolve_expr_or_opts(expr_or_opts) do
    cond do
      expr_or_opts == nil ->
        {[], nil}

      # expr_or_opts is expr
      Keyword.has_key?(expr_or_opts, :do) ->
        Keyword.pop(expr_or_opts, :do)

      # expr_or_opts is opts
      true ->
        {expr_or_opts, nil}
    end
  end

  defp define_chaos_function(type, call, body, chaos_opts) do
    func_name = extract_function_name(call)

    quote do
      unquote(type)(unquote(call)) do
        Mutineer.maybe_chaos(
          fn -> unquote(body) end,
          unquote(chaos_opts) ++ [function: unquote(func_name), module: __MODULE__]
        )
      end
    end
  end

  defp extract_function_name({:when, _, [{name, _, _} | _]}), do: name
  defp extract_function_name({name, _, _}), do: name

  # Callback for @on_definition - tracks functions with @chaos attribute
  def __on_definition__(env, kind, name, args, _guards, _body) do
    chaos_config = Module.get_attribute(env.module, :chaos)

    if chaos_config do
      Module.delete_attribute(env.module, :chaos)
      chaos_functions = Module.get_attribute(env.module, :chaos_functions) || []

      config = normalize_chaos_config(chaos_config)
      arity = length(args)

      Module.put_attribute(env.module, :chaos_functions, [
        {kind, name, arity, config} | chaos_functions
      ])
    end
  end

  defp normalize_chaos_config(true), do: []
  defp normalize_chaos_config(config) when is_list(config), do: config

  # Callback for @before_compile - wraps marked functions
  defmacro __before_compile__(env) do
    chaos_functions = Module.get_attribute(env.module, :chaos_functions) || []

    for {kind, name, arity, config} <- chaos_functions do
      args = Macro.generate_arguments(arity, env.module)

      quote do
        defoverridable [{unquote(name), unquote(arity)}]

        unquote(kind)(unquote(name)(unquote_splicing(args))) do
          Mutineer.maybe_chaos(
            fn -> super(unquote_splicing(args)) end,
            unquote(config) ++ [function: unquote(name), module: __MODULE__]
          )
        end
      end
    end
  end
end
