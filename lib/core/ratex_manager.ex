defmodule Ratex.RateManager do
  defmacro __using__([pool_name: name, worker_module: worker_module] = kw) do
    quote do
      use GenServer

      @item_state_pending 0
      @item_state_in_progress 3
      @item_state_completed 5

      defp listen() do
        receive do
          _any ->
            listen()
        after
          5000 ->
            send(unquote(name), :run_next)
            listen()
        end
      end

      def instance() do
        case GenServer.start_link(
               __MODULE__,
               {:start, %{initial_workers: Keyword.get(unquote(kw), :initial_workers, 0)}},
               name: unquote(name)
             ) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
      end

      unquote do
        if kw[:worker_options] do
          quote do
            def add_worker() do
            end
          end
        end
      end

      @doc """
      Start a new worker with options
      """
      def add_worker(options) do
        GenServer.call(unquote(name), {:add_worker, options})
      end

      @doc """
      Add a new item to queue.
      """
      def add_item(key, data) do
        GenServer.call(unquote(name), {:add_item, {key, data}})
      end

      # def test() do
      #   1..5
      #   |> Enum.each(fn _ ->
      #     add_worker(%{})
      #   end)

      #   1..1000
      #   |> Enum.each(fn n ->
      #     add_item("handle_#{n}", n)
      #   end)
      # end

      def init({:start, options}) do
        initial_workers = Keyword.get(unquote(kw), :initial_workers, 0)

        workers =
          if initial_workers >= 1 do
            1..initial_workers
            |> Enum.map(fn opt ->
              {:ok, pid} = add_worker(Keyword.get(unquote(kw), :worker_options))
              ref = Process.monitor(pid)
              {pid, %{ref: ref, ready: true, state: :free, priority: 1}}
            end)
            |> Map.new()
          else
            %{}
          end

        spawn(fn ->
          listen()
        end)

        {:ok,
         %{
           pending: %{},
           completed: %{},
           in_progress: %{},
           free_workers: workers,
           busy_workers: %{},
           down_workers: %{}
         }}
      end

      def work() do
        run_next()
      end

      defp ensure_started() do
        # GenServer.start_link(__MODULE__, [], [name: name])
        instance()
      end

      defp run_next() do
        # pid = instance()
        # Process.send_after(pid, :run_next, 5000)
      end

      def handle_next_item({key, %{data: data}} = item, {pid, _} = worker) do
        parent = unquote(name)
        GenServer.call(pid, {:next, {key, data}, parent})
      end

      def handle_next_item_async({key, %{data: data}} = item, {pid, _} = worker) do
        parent = unquote(name)
        GenServer.cast(pid, {:next, {key, data}, parent})
      end

      def checkout_worker(pool_name) do
        GenServer.call(pool_name, :checkout_worker)
      end

      def checkout_worker() do
        # GenServer.call(unquote(name), :checkout_worker)
        checkout_worker(unquote(name))
      end

      def checkout_item(pool_name) do
        GenServer.call(pool_name, :checkout_item)
      end

      def checkout_item() do
        # GenServer.call(unquote(name), :checkout_item)
        checkout_item(unquote(name))
      end

      def get_next_worker(state) do
        state.free_workers
        |> Enum.take(1)
        |> List.first()
      end

      def get_next_item(state) do
        state.pending
        |> Enum.take(1)
        |> List.first()
      end

      def get_state(pool_name) do
        GenServer.call(pool_name, :_get_state)
      end

      def get_state() do
        get_state(unquote(name))
      end

      def get_worker_state(worker_pid)do
        GenServer.call(worker_pid, :get_state)
      end

      def pending_items()do
        get_items(:pending)
      end

      def in_progress_items()do
        get_items(:in_progress)
      end

      def completed_items()do
        get_items(:completed)
      end


      defp get_items(status)do        
        GenServer.call(unquote(name), {:get_items, status})        
      end

      def handle_call({:get_items, status}, _from, state)do
        result = case status do
          :completed -> {:ok, state.completed}
          :in_progress -> {:ok, state.in_progress}
          :pending -> {:ok, state.pending}
          _ -> {:error, :invalid_status}
        end
        {:reply, result, state}
      end

      def handle_call({:add_worker, options}, _from, state) do
        {:ok, pid} = unquote(worker_module).instance(options)
        ref = Process.monitor(pid)
        worker_state = %{ref: ref, ready: true, state: :free, priority: 1}

        free_workers =
          state.free_workers
          |> Map.put(pid, worker_state)

        new_state =
          state
          |> Map.put(:free_workers, free_workers)

        run_next()
        {:reply, {:ok, pid}, new_state}
      end

      def handle_call(:_get_state, _from, %{} = state) do
        {:reply, state, state}
      end

      def handle_call({:add_item, {key, data}}, _from, %{} = state) do
        exists =
          Map.get(state.pending, key) || Map.get(state.in_progress, key) ||
            Map.get(state.completed, key)

        IO.inspect(exists)

        {reply, new_state} =
          case exists do
            nil ->
              item_state = Map.put(%{data: data}, :state, @item_state_pending)
              {{:ok, key}, Map.put(state, :pending, Map.put(state.pending, key, item_state))}

            any ->
              {{:error, :exists, key}, state}
          end

        run_next()
        {:reply, reply, new_state}
      end

      def handle_call(:checkout_worker, _from, state) do
        case state.free_workers
             |> Enum.take(1)
             |> List.first() do
          {pid, worker_state} = worker ->
            free_workers = Map.delete(pid, state.free_workers)
            busy_workers = Map.put(state.busy_workers, pid, worker_state)

            new_state =
              state
              |> Map.put(:free_workers, free_workers)
              |> Map.put(:busy_workers, busy_workers)

            {:reply, worker, new_state}

          _ ->
            {:reply, nil, state}
        end
      end

      def handle_call(:checkout_item, _from, state) do
        case state.pending
             |> Enum.take(1)
             |> List.first() do
          {key, item_state} = item ->
            pending = Map.delete(state.pending, key)
            in_progress = Map.put(state.in_progress, key, item_state)

            new_state =
              state
              |> Map.put(:pending, pending)
              |> Map.put(:in_progress, in_progress)

            {:reply, item, new_state}

          _ ->
            {:reply, nil, state}
        end
      end

      def handle_info(:run_next, %{} = state) do
        next_item = get_next_item(state)

        case next_item do
          {key, %{data: _data} = item_state} ->
            next_worker = get_next_worker(state)

            case next_worker do
              nil ->
                #IO.puts("No available worker. Try again")
                # put back the handle
                new_state =
                  state
                  |> Map.put(:pending, Map.put(state.pending, key, item_state))
                  |> Map.put(:in_progress, Map.delete(state.in_progress, key))

                {:noreply, new_state}

              {pid, %{} = worker_state} ->
                free_workers = Map.delete(state.free_workers, pid)
                busy_workers = Map.put(state.busy_workers, pid, worker_state)

                pending = Map.delete(state.pending, key)
                in_progress = Map.put(state.in_progress, key, item_state)

                new_state =
                  state
                  |> Map.put(:free_workers, free_workers)
                  |> Map.put(:busy_workers, busy_workers)
                  |> Map.put(:pending, pending)
                  |> Map.put(:in_progress, in_progress)

                handle_next_item_async(next_item, next_worker)
                {:noreply, new_state}
            end

          _ ->
            #IO.puts("No next handle available")
            {:noreply, state}
        end
      end

      def handle_info({:DOWN, ref, :process, pid, :normal}, %{} = state) do
        Process.demonitor(ref)

        {new_busy_workers, worker_state} =
          case Map.get(state.busy_workers, pid) do
            nil ->
              {state.busy_workers, nil}

            %{} = m ->
              {Map.delete(state.busy_workers, pid), m}
          end

        down_workers =
          case Map.get(state, :down_workers) do
            nil ->
              if worker_state do
                Map.put(%{}, pid, worker_state)
              else
                %{}
              end

            %{} = map ->
              if worker_state do
                Map.put(map, pid, worker_state)
              else
                map
              end
          end

        new_state =
          state
          |> Map.put(:busy_workers, new_busy_workers)
          |> Map.put(:down_workers, down_workers)

        {:noreply, new_state}
      end

      def handle_cast(
            {:done, worker_pid, %{handle: {key, _data, result}, calls: calls} = payload},
            %{} = state
          ) do
        {in_progress, completed} =
          case Map.get(state.in_progress, key) do
            %{} = m ->
              new_m =
                m
                |> Map.put(:result, result)
                |> Map.put(:calls, calls)

              {
                Map.delete(state.in_progress, key),
                Map.put(state.completed, key, new_m)
              }

            _ ->
              {state.in_progress, state.completed}
          end

        {busy_workers, free_workers} =
          case Map.get(state.busy_workers, worker_pid) do
            nil ->
              {state.busy_workers, state.free_workers}

            %{} = m ->
              new_m =
                m
                |> Map.update(:api_calls, calls, fn c -> c + calls end)
                |> Map.update(:requests, 1, fn c -> c + 1 end)

              {
                Map.delete(state.busy_workers, worker_pid),
                Map.put(state.free_workers, worker_pid, new_m)
              }
          end

        new_state =
          state
          |> Map.put(:free_workers, free_workers)
          |> Map.put(:busy_workers, busy_workers)
          |> Map.put(:in_progress, in_progress)
          |> Map.put(:completed, completed)

        run_next()
        {:noreply, new_state}
      end

      def handle_cast({:rated, worker_pid, %{handle: key} = payload}, %{} = state) do
        {pending, in_progress} =
          case Map.get(state.in_progress, key) do
            %{} = m ->
              new_m =
                m
                |> Map.put(:state, @item_state_pending)

              {
                Map.put(state.pending, key, new_m),
                Map.delete(state.in_progress, key)
              }

            _ ->
              {state.pending, state.in_progress}
          end

        {busy_workers, free_workers} =
          case Map.get(state.busy_workers, worker_pid) do
            nil ->
              state.busy_workers

            %{} = m ->
              new_m =
                m
                |> Map.put(:state, :free)
                |> Map.update(:priority, 1, fn c -> c + 1 end)

              {state.busy_workers
               |> Map.delete(worker_pid),
               state.free_workers
               |> Map.put(worker_pid, new_m)}
          end

        new_state =
          state
          |> Map.put(:pendin, pending)
          |> Map.put(:in_progress, in_progress)
          |> Map.put(:free_workers, free_workers)
          |> Map.put(:busy_workers, busy_workers)

        run_next()
        {:noreply, new_state}
      end
    end
  end
end
