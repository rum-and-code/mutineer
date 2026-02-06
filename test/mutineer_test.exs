defmodule MutineerTest do
  use ExUnit.Case, async: true

  alias Mutineer

  defmodule TestChaosErrorA do
    defexception [:message, :function, :module]
  end

  defmodule TestChaosErrorB do
    defexception [:message, :function, :module]
  end

  defmodule TestModule do
    use Mutineer

    @chaos failure_rate: 0.1
    def query do
      {:ok, "success"}
    end

    defchaos macro_test(3), failure_rate: 0.5 do
      {:ok, "defchaos/3"}
    end

    defchaos macro_test(2) do
      {:ok, "defchaos/2"}
    end
  end

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
      # Allow for statistical variance (roughly 4 standard deviations)
      # std dev = sqrt(n * p * (1-p)) = sqrt(10_000 * 0.1 * 0.9) = 30
      # 4 * 30 = 90, so we allow 1000 ± 120
      assert failures >= 880 and failures <= 1120,
             "Expected ~1000 failures (±120), got #{failures}"
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
      assert Mutineer.Failures.trigger_failure(:error, fn -> :ok end, []) ==
               {:error, :mutineer_chaos}
    end

    test "returns nil for :nil type" do
      assert Mutineer.Failures.trigger_failure(nil, fn -> :ok end, []) == nil
    end

    test "raises ChaosError for :raise type" do
      assert_raise Mutineer.ChaosError, fn ->
        Mutineer.Failures.trigger_failure(:raise, fn -> :ok end,
          function: :test_func,
          module: __MODULE__
        )
      end
    end

    test "raises ChaosError with custom message" do
      assert_raise Mutineer.ChaosError, ~r/Custom chaos message/, fn ->
        Mutineer.Failures.trigger_failure(
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
      result = Mutineer.Failures.trigger_failure(:delay, func, delay: 50)
      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:ok, "delayed_result"}
      assert elapsed >= 50
    end

    test "delays then raises an error for :timeout type" do
      func = fn -> {:ok, "should_not_return"} end
      start = System.monotonic_time(:millisecond)

      assert_raise Mutineer.ChaosError, fn ->
        Mutineer.Failures.trigger_failure(:timeout, func, delay: 50)
      end

      elapsed = System.monotonic_time(:millisecond) - start

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

      assert Enum.any?(results, &(&1 == {:error, :mutineer_chaos}))
      assert Enum.any?(results, &(&1 == {:ok, "defchaos/3"}))
    end

    test "macro defchaos/2 works without opts" do
      iterations = 1_000

      results =
        Enum.map(1..iterations, fn _ ->
          TestModule.macro_test(2)
        end)

      assert Enum.any?(results, &(&1 == {:error, :mutineer_chaos}))
      assert Enum.any?(results, &(&1 == {:ok, "defchaos/2"}))
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
          failure_type: nil
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

    test "supports custom errors" do
      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :error,
          error: {:error, :custom_error}
        )

      assert result == {:error, :custom_error}
    end

    test "supports custom errors with map as error" do
      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :error,
          error: {:error, %{status_code: 500, body: "Mutiny!"}}
        )

      assert result == {:error, %{status_code: 500, body: "Mutiny!"}}
    end

    test "supports custom errors with list as errors" do
      results =
        Enum.map(
          1..100,
          fn _ ->
            Mutineer.maybe_chaos(
              fn -> {:ok, "success"} end,
              failure_rate: 1.0,
              failure_type: :error,
              errors: [{:error, "code_1"}, {:error, "code_2"}, {:error, "code_3"}]
            )
          end
        )

      assert Enum.all?(results, fn result ->
               result == {:error, "code_1"} || result == {:error, "code_2"} ||
                 result == {:error, "code_3"}
             end)

      assert Enum.any?(results, fn result -> result == {:error, "code_1"} end)
      assert Enum.any?(results, fn result -> result == {:error, "code_2"} end)
      assert Enum.any?(results, fn result -> result == {:error, "code_3"} end)
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

    test ":timeout failure type adds delay then raises an error" do
      start = System.monotonic_time(:millisecond)

      assert_raise(
        Mutineer.ChaosError,
        fn ->
          Mutineer.maybe_chaos(
            fn -> {:ok, "success"} end,
            failure_rate: 1.0,
            failure_type: :timeout,
            delay: 50
          )
        end
      )

      elapsed = System.monotonic_time(:millisecond) - start

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

    test "failure_types selects randomly from a list of failure types" do
      results =
        Enum.map(
          1..200,
          fn _ ->
            Mutineer.maybe_chaos(
              fn -> {:ok, "success"} end,
              failure_rate: 1.0,
              failure_types: [:error, nil]
            )
          end
        )

      error_count = Enum.count(results, &(&1 == {:error, :mutineer_chaos}))
      nil_count = Enum.count(results, &is_nil/1)

      assert error_count > 0, "Expected some :error failures"
      assert nil_count > 0, "Expected some nil failures"
      assert error_count + nil_count == 200
    end

    test "raised_errors selects randomly from a list of error modules" do
      results =
        Enum.map(1..200, fn _ ->
          try do
            Mutineer.maybe_chaos(
              fn -> {:ok, "success"} end,
              failure_rate: 1.0,
              failure_type: :raise,
              raised_errors: [MutineerTest.TestChaosErrorA, MutineerTest.TestChaosErrorB]
            )
          rescue
            e -> e.__struct__
          end
        end)

      a_count = Enum.count(results, &(&1 == MutineerTest.TestChaosErrorA))
      b_count = Enum.count(results, &(&1 == MutineerTest.TestChaosErrorB))

      assert a_count > 0, "Expected some TestChaosErrorA raises"
      assert b_count > 0, "Expected some TestChaosErrorB raises"
      assert a_count + b_count == 200
    end

    test "exit_errors selects randomly from a list of exit reasons" do
      results =
        Enum.map(1..200, fn _ ->
          try do
            Mutineer.maybe_chaos(
              fn -> {:ok, "success"} end,
              failure_rate: 1.0,
              failure_type: :exit,
              exit_errors: [:chaos_a, :chaos_b, :chaos_c]
            )
          catch
            :exit, reason -> reason
          end
        end)

      a_count = Enum.count(results, &(&1 == :chaos_a))
      b_count = Enum.count(results, &(&1 == :chaos_b))
      c_count = Enum.count(results, &(&1 == :chaos_c))

      assert a_count > 0, "Expected some :chaos_a exits"
      assert b_count > 0, "Expected some :chaos_b exits"
      assert c_count > 0, "Expected some :chaos_c exits"
      assert a_count + b_count + c_count == 200
    end

    test ":delay with a Range delays within that range" do
      start = System.monotonic_time(:millisecond)

      result =
        Mutineer.maybe_chaos(
          fn -> {:ok, "range_delayed"} end,
          failure_rate: 1.0,
          failure_type: :delay,
          delay: 50..100
        )

      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:ok, "range_delayed"}
      assert elapsed >= 50
    end

    test ":timeout with a Range delays within that range then raises" do
      start = System.monotonic_time(:millisecond)

      assert_raise Mutineer.ChaosError, fn ->
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :timeout,
          delay: 50..100
        )
      end

      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 50
    end

    test ":timeout with raised_errors selects randomly from a list" do
      results =
        Enum.map(1..200, fn _ ->
          try do
            Mutineer.maybe_chaos(
              fn -> {:ok, "success"} end,
              failure_rate: 1.0,
              failure_type: :timeout,
              delay: 1..2,
              raised_errors: [MutineerTest.TestChaosErrorA, MutineerTest.TestChaosErrorB]
            )
          rescue
            e -> e.__struct__
          end
        end)

      a_count = Enum.count(results, &(&1 == MutineerTest.TestChaosErrorA))
      b_count = Enum.count(results, &(&1 == MutineerTest.TestChaosErrorB))

      assert a_count > 0, "Expected some TestChaosErrorA raises"
      assert b_count > 0, "Expected some TestChaosErrorB raises"
    end

    test "single exit_error exits with that specific reason" do
      result =
        try do
          Mutineer.maybe_chaos(
            fn -> {:ok, "success"} end,
            failure_rate: 1.0,
            failure_type: :exit,
            exit_error: :custom_exit
          )
        catch
          :exit, reason -> reason
        end

      assert result == :custom_exit
    end

    test "single raised_error raises that specific error" do
      assert_raise MutineerTest.TestChaosErrorA, fn ->
        Mutineer.maybe_chaos(
          fn -> {:ok, "success"} end,
          failure_rate: 1.0,
          failure_type: :raise,
          raised_error: MutineerTest.TestChaosErrorA
        )
      end
    end
  end
end
