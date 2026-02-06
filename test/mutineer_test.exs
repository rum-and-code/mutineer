defmodule MutineerTest do
  use ExUnit.Case, async: true

  alias Mutineer

  describe "should_fail?/1" do
    test "returns true approximately at the given rate" do
      # Run 10_000 trials to get a statistically significant sample
      trials = 10_000
      rate = 0.1

      failures =
        Enum.count(1..trials, fn _ ->
          Mutineer.should_fail?(rate)
        end)

      # With 10% rate over 10_000 trials, we expect ~1_000 failures
      # Allow for statistical variance (roughly 3 standard deviations)
      # std dev = sqrt(n * p * (1-p)) = sqrt(10_000 * 0.1 * 0.9) = 30
      # 3 * 30 = 90, so we allow 1000 ± 90
      assert failures >= 910 and failures <= 1090,
             "Expected ~1000 failures (±90), got #{failures}"
    end

    test "returns false when rate is 0" do
      refute Mutineer.should_fail?(0.0)
    end

    test "returns true when rate is 1" do
      assert Mutineer.should_fail?(1.0)
    end
  end

  describe "trigger_failure/2" do
    test "returns {:error, :mutineer_chaos} for :error type" do
      assert Mutineer.trigger_failure(:error, fn -> :ok end, []) == {:error, :mutineer_chaos}
    end

    test "returns nil for :nil type" do
      assert Mutineer.trigger_failure(:nil, fn -> :ok end, []) == nil
    end

    test "raises ChaosError for :raise type" do
      assert_raise Mutineer.ChaosError, fn ->
        Mutineer.trigger_failure(:raise, fn -> :ok end, function: :test_func, module: __MODULE__)
      end
    end

    test "raises ChaosError with custom message" do
      assert_raise Mutineer.ChaosError, ~r/Custom chaos message/, fn ->
        Mutineer.trigger_failure(
          :raise,
          fn -> :ok end,
          function: :test_func,
          module: __MODULE__,
          message: "Custom chaos message"
        )
      end
    end

    test "delays then executes function for :delay type" do
      func = fn -> {:ok, "delayed_result"} end
      start = System.monotonic_time(:millisecond)
      result = Mutineer.trigger_failure(:delay, func, delay: 50)
      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:ok, "delayed_result"}
      assert elapsed >= 50
    end

    test "delays then returns error for :timeout type" do
      func = fn -> {:ok, "should_not_return"} end
      start = System.monotonic_time(:millisecond)
      result = Mutineer.trigger_failure(:timeout, func, delay: 50)
      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:error, :mutineer_chaos}
      assert elapsed >= 50
    end
  end

  describe "maybe_chaos/2" do
    setup do
      # Temporarily disable Mutineer for this test
      original_config = Application.get_env(:mutineer, Mutineer, [])
      Application.put_env(:mutineer, Mutineer, enabled: false)

      on_exit(fn ->
        Application.put_env(:mutineer, Mutineer, original_config)
      end)

      :ok
    end

    test "executes function when chaos is disabled" do
      result = Mutineer.maybe_chaos(fn -> {:ok, "success"} end, failure_rate: 1.0)
      assert result == {:ok, "success"}
    end
  end

  defmodule TestModule do
    use Mutineer

    @chaos failure_rate: 0.1
    def query do
      {:ok, "success"}
    end

    defchaos macro_test(arity) when arity == 3, failure_rate: 1.0 do
      {:ok, "defchaos/3"}
    end

    defchaos macro_test(arity) when arity == 2 do
      {:ok, "defchaos/2"}
    end
  end

  describe "integration test with enabled chaos" do
    setup do
      original_config = Application.get_env(:mutineer, Mutineer, [])
      Application.put_env(:mutineer, Mutineer, enabled: true, default_failure_rate: 0.1)

      on_exit(fn ->
        Application.put_env(:mutineer, Mutineer, original_config)
      end)

      :ok
    end

    test "function fails approximately 10% of the time with 0.1 failure rate" do
      iterations = 10_000

      results =
        Enum.map(1..iterations, fn _ ->
          TestModule.query()
        end)

      failures = Enum.count(results, &(&1 == {:error, :mutineer_chaos}))
      successes = Enum.count(results, &(&1 == {:ok, "success"}))

      assert failures >= 800 and failures <= 1200,
             "Expected 800-1200 failures, got #{failures} (successes: #{successes})"

      assert successes == iterations - failures
    end

    test "macro defchaos/3 works when provided with opts" do
      iterations = 1_000

      results =
        Enum.map(1..iterations, fn _ ->
          TestModule.macro_test(3)
        end)

      assert Enum.all?(results, &(&1 == {:error, :mutineer_chaos}))
    end

    test "macro defchaos/2 works without opts" do
      iterations = 1_000

      results =
        Enum.map(1..iterations, fn _ ->
          TestModule.macro_test(2)
        end)

      assert Enum.any?(results, &(&1 == {:error, :mutineer_chaos}))
    end

    test "function never fails when failure_rate is 0" do
      iterations = 100

      results =
        Enum.map(1..iterations, fn _ ->
          Mutineer.maybe_chaos(
            fn -> {:ok, "success"} end,
            failure_rate: 0.0,
            failure_type: :error
          )
        end)

      failures = Enum.count(results, &(&1 == {:error, :mutineer_chaos}))
      assert failures == 0
    end

    test "function always fails when failure_rate is 1.0" do
      iterations = 100

      results =
        Enum.map(1..iterations, fn _ ->
          Mutineer.maybe_chaos(
            fn -> {:ok, "success"} end,
            failure_rate: 1.0,
            failure_type: :error
          )
        end)

      failures = Enum.count(results, &(&1 == {:error, :mutineer_chaos}))
      assert failures == iterations
    end

    test "supports different failure types" do
      # Test :nil failure type
      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :nil
        )

      assert result == nil

      # Test :raise failure type
      assert_raise Mutineer.ChaosError, fn ->
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :raise
        )
      end
    end

    test "supports custom failure types" do
      # Test :custom failure type
      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :custom,
          custom_error: {:error, :custom_error}
        )

      assert result == {:error, :custom_error}
    end

    test "supports custom failure types with custom error" do
      # Test :custom failure type with custom error
      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :custom,
          custom_error: {:error, %{status_code: 500, body: "Mutiny!"}}
        )

      assert result == {:error, %{status_code: 500, body: "Mutiny!"}}
    end

    test ":delay failure type adds delay then returns function result" do
      start = System.monotonic_time(:millisecond)

      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "delayed"} end,
          failure_rate: 1.0,
          failure_type: :delay,
          delay: 50
        )

      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:ok, "delayed"}
      assert elapsed >= 50
    end

    test ":timeout failure type adds delay then returns error" do
      start = System.monotonic_time(:millisecond)

      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :timeout,
          delay: 50
        )

      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:error, :mutineer_chaos}
      assert elapsed >= 50
    end

    test ":delay executes function normally when chaos does not trigger" do
      start = System.monotonic_time(:millisecond)

      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "no_delay"} end,
          failure_rate: 0.0,
          failure_type: :delay,
          delay: 90_000_000
        )

      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 90_000_000
      assert result == {:ok, "no_delay"}
    end

    test ":timeout executes function normally when chaos does not trigger" do
      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "no_timeout"} end,
          failure_rate: 0.0,
          failure_type: :timeout,
          delay: 50
        )

      assert result == {:ok, "no_timeout"}
    end
  end
end
