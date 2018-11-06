defmodule RatexTest do
  use ExUnit.Case
  doctest Ratex

  setup do
    TestManager.instance()
    %{manager: TestManager}
    
  end
  
  test "successfully added item to queue", %{manager: manager} do
    assert {:ok, "key"}  = manager.add_item("key", "data")
  end

  test "adding existing item to queue is rejected", %{manager: manager} do
    assert {:ok, "key"}  = manager.add_item("key", "data")
    assert {:error, :exists, "key"}  = manager.add_item("key", "data")
  end

  test "adding worker to manager", %{manager: manager} do
    assert {:ok, "key"}  = manager.add_item("key", "data")
    assert {:error, :exists, "key"}  = manager.add_item("key", "data")
    assert {:ok, pid} = manager.add_worker(%{token: "token"})      
    assert %{options: %{token: "token"}} = manager.get_worker_state(pid)
    assert %{:free_workers=> %{^pid => %{}}} = manager.get_state()

  end

  test "worker work on item", %{manager: manager} do
    assert {:ok, "key"}  = manager.add_item("key", "data")
    assert {:ok, pid} = manager.add_worker(%{token: "token"})  

    assert {:ok, %{"key"=> %{data: "data"}}} = manager.pending_items()

    IO.inspect(manager.get_state())   
    Process.sleep(5000) 
    assert {:ok, %{"key"=> %{data: "data"}}} = manager.completed_items()

    IO.inspect(manager.get_state()) 
  end

end
