defmodule TestWorker do
    use Ratex.RateWorker,
    options: %{}

    def work(p, state)do
        {:ok, %Ratex.WorkerResult{result: :ok, api_calls: 1, end_time: 1, start_time: 0}}
    end
end

defmodule TestManager do
    use Ratex.RateManager,
    pool_name: :test_manager,
    worker_module: TestWorker

end