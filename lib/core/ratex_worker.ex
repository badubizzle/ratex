defmodule Ratex.RateWorker do
  defmacro __using__(options: options) do
    quote do
      use GenServer
      alias Ratex.WorkerResult

      
      def work(payload, state)
      # defp rate_limit do
      #     Map.get(unquote(options), :rate_limit, 1000)
      # end

      # defp rate_seconds do
      #     Map.get(unquote(options), :rate_seconds, 3600)
      # end            

      defp instance(work_fun, opt) do
        opt =
          opt
          |> Map.update(:rate_limit, 1000, fn v -> v end)
          |> Map.update(:rate_seconds, 300, fn v -> v end)

        start_link(%{
          worker: work_fun,
          options: opt
        })
      end

      def on_init(options) do
        %{options: options, api_calls: %{}}
      end

      defoverridable on_init: 1

      def init({:start, opt}) do
        new_state = on_init(opt[:options])

        state =
          Map.merge(opt, new_state)
          |> Map.put(:worker, opt.worker)

        {:ok, state}
      end

     def instance(opt) do
        default_options = unquote(options)        
        instance(&work/2, Map.merge(default_options, opt))
      end

      def start_link(opts) do
        GenServer.start_link(__MODULE__, {:start, opts}, [])
      end

      defp ago_timestamp(secs_ago) do
        :os.system_time(:millisecond) - secs_ago * 1_000
      end

      def on_rated(state, payload) do
        state
      end

      def handle_cast({:next, payload, parent}, state) do
        {result, new_state} = do_work(payload, parent, state, true)
        {:noreply, new_state}
      end

      def handle_cast(_r, state) do
        {:noreply, state}
      end

      def handle_call({:next, payload, parent}, _from, state) do
        {result, new_state} = do_work(payload, parent, state)
        {:reply, result, new_state}
      end

      def handle_call(_r, _from, state) do
        {:reply, :ok, state}
      end

      def handle_info(_r, state) do
        {:noreply, state}
      end

      defp do_work_sync(payload, parent, state) do
        do_work(payload, parent, state, false)
      end

      defp do_work(payload, parent, state, async \\ true) do
        rate_seconds = state.options.rate_seconds
        rate_limit = state.options.rate_limit
        api_calls = state.api_calls

        time_ago = ago_timestamp(rate_seconds)

        total_api_calls_past_time =
          api_calls
          |> Enum.filter(fn {ts, total} ->
            ts >= time_ago
          end)
          |> Enum.map(fn {_, count} ->
            count
          end)
          |> Enum.reduce(0, fn n, total ->
            total + n
          end)

        requests_left = rate_limit - total_api_calls_past_time
        IO.puts("#{total_api_calls_past_time} total API calls in the last #{rate_seconds}s")
        IO.puts("#{requests_left} API calls left for #{inspect(self())}")

        case total_api_calls_past_time < rate_limit do
          true ->
            case payload do
              {key, data} = next_handle ->
                start_time = :os.system_time(:millisecond)

                worker_fun = state.worker

                task = Task.async(fn -> worker_fun.(next_handle, state) end)
                work_result = Task.await(task, :infinity)

                case work_result do
                  {:ok,
                   %WorkerResult{
                     result: result,
                     api_calls: total_api_calls,
                     start_time: start_time,
                     end_time: end_time
                   } = r} ->
                    total_time = end_time - start_time
                    time = total_time
                    IO.puts("Request took #{time}ms and #{total_api_calls} API calls")

                    if async do
                      GenServer.cast(
                        parent,
                        {:done, self(),
                         %{
                           handle: {key, data, result},
                           time: total_time,
                           calls: total_api_calls,
                           data: []
                         }}
                      )
                    end

                    new_state =
                      Map.put(state, :api_calls, Map.put(api_calls, end_time, total_api_calls))

                    {result, new_state}

                  {:rated, _} ->
                    {key, _} = payload
                    new_state = on_rated(state, payload)

                    if async do
                      GenServer.cast(parent, {:rated, self(), %{handle: key}})
                    end

                    # notify parent of completion
                    {:rated, new_state}
                end

              other ->
                IO.puts("No handle found when request, will request later #{inspect(other)}")

                if async do
                  GenServer.cast(parent, {:no_handle, self(), %{handle: other}})
                end

                {:no_handle, state}
            end

          false ->
            {key, _} = payload
            new_state = on_rated(state, payload)

            if async do
              GenServer.cast(parent, {:rated, self(), %{handle: key}})
            end

            # notify parent of completion
            {:rated, new_state}
        end
      end
    end
  end
end
