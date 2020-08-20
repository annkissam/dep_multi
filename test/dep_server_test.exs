defmodule DepServerTest do
  use ExUnit.Case
  doctest DepServer

  test "greets the world" do
    assert DepServer.hello() == :world
  end
end
