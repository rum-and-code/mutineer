defmodule Mutineer.Failures do
  @doc """
  Triggers a failure of the specified type.
  """
  def trigger_failure(:error, _func, opts), do: error_failure(opts[:errors] || opts[:error])

  def trigger_failure(:raise, _func, opts),
    do: raise_failure(opts[:raised_errors] || opts[:raised_error], opts)

  def trigger_failure(:delay, func, opts), do: delay_failure(func, opts[:delay])
  def trigger_failure(nil, _func, _opts), do: nil

  def trigger_failure(:exit, _func, opts),
    do: exit_failure(opts[:exit_errors] || opts[:exit_error])

  def trigger_failure(:timeout, _func, opts),
    do: timeout_failure(opts[:delay], opts[:raised_errors] || opts[:raised_error], opts)

  defp error_failure(nil), do: {:error, :mutineer_chaos}
  defp error_failure(errors) when is_list(errors), do: Enum.random(errors)
  defp error_failure(error), do: error

  defp raise_failure(nil, opts) do
    raise Mutineer.ChaosError,
      message: opts[:message] || "Mutiny!",
      function: opts[:function],
      module: opts[:module]
  end

  defp raise_failure(raised_errors, opts) when is_list(raised_errors) do
    raise Enum.random(raised_errors),
      message: opts[:message] || "Mutiny!",
      function: opts[:function],
      module: opts[:module]
  end

  defp raise_failure(error, opts) do
    raise error,
      message: opts[:message] || "Mutiny!",
      function: opts[:function],
      module: opts[:module]
  end

  defp delay_failure(func, %Range{} = delay) do
    delay
    |> Enum.random()
    |> Process.sleep()

    func.()
  end

  defp delay_failure(func, delay) when is_nil(delay) or is_integer(delay) do
    delay = delay || :rand.uniform(4000) + 1000
    Process.sleep(delay)

    func.()
  end

  defp delay_failure(func, %Range{} = delay) do
    delay
    |> Enum.random()
    |> Process.sleep()

    func.()
  end

  defp timeout_failure(%Range{} = delay, raised_errors, opts) do
    delay
    |> Enum.random()
    |> Process.sleep()

    raise_failure(raised_errors, opts)
  end

  defp timeout_failure(delay, raised_errors, opts) when is_nil(delay) or is_integer(delay) do
    delay = delay || :rand.uniform(4000) + 1000
    Process.sleep(delay)

    raise_failure(raised_errors, opts)
  end

  defp exit_failure(exit_errors) when is_list(exit_errors) do
    exit_errors
    |> Enum.random()
    |> exit()
  end

  defp exit_failure(nil), do: exit(:mutineer_chaos)

  defp exit_failure(exit_error), do: exit(exit_error)
end
