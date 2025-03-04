defmodule ByeByeBye.MbtaClientTest do
  use ExUnit.Case, async: true
  alias ByeByeBye.MbtaClient

  setup do
    # Configure test API settings
    Application.put_env(:bye_bye_bye, :mbta_api_url, "http://api-mock-url")
    Application.put_env(:bye_bye_bye, :mbta_api_key, "test_api_key")
    :ok
  end

  describe "get_alerts/0" do
    test "successfully fetches alerts" do
      Req.Test.stub(:mbta_api, fn conn ->
        assert conn.request_path == "/alerts"

        assert Enum.find(conn.req_headers, &(elem(&1, 0) == "x-api-key")) ==
                 {"x-api-key", "test_api_key"}

        Req.Test.json(conn, %{
          "data" => [
            %{"id" => "1", "attributes" => %{"effect" => "CANCELLATION"}},
            %{"id" => "2", "attributes" => %{"effect" => "DELAY"}}
          ]
        })
      end)

      assert {:ok, alerts} = MbtaClient.get_alerts()
      assert [%{"id" => "1"}, %{"id" => "2"}] = alerts
    end

    test "handles error response" do
      Req.Test.stub(:mbta_api, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, _} = MbtaClient.get_alerts()
    end
  end

  describe "get_schedules/1" do
    test "successfully fetches schedules by trip" do
      Req.Test.stub(:mbta_api, fn conn ->
        assert conn.request_path == "/schedules"
        assert conn.params["trip"] == "123,456"
        assert conn.params["fields"]["schedule"] == "stop_sequence"

        Req.Test.json(conn, %{
          "data" => [
            %{
              "attributes" => %{"stop_sequence" => 1},
              "relationships" => %{"trip" => %{"data" => %{"id" => "123"}}}
            },
            %{
              "attributes" => %{"stop_sequence" => 2},
              "relationships" => %{"trip" => %{"data" => %{"id" => "123"}}}
            }
          ]
        })
      end)

      assert {:ok, schedules} = MbtaClient.get_schedules(trips: ["123", "456"])
      assert map_size(schedules) == 1
      assert Map.keys(schedules) == ["123"]
    end

    test "successfully fetches schedules by route with time window" do
      Req.Test.stub(:mbta_api, fn conn ->
        assert conn.request_path == "/schedules"
        assert conn.params["route"] == "Red,Blue"
        assert conn.params["min_time"] == "10:00"
        assert conn.params["max_time"] == "11:00"

        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, _schedules} =
               MbtaClient.get_schedules(%{
                 routes: ["Red", "Blue"],
                 min_time: "10:00",
                 max_time: "11:00"
               })
    end

    test "validates schedule params" do
      assert {:error, "Cannot specify both trips and routes"} =
               MbtaClient.get_schedules(trips: ["123"], routes: ["Red"])

      assert {:error, "Must specify either trips or routes"} =
               MbtaClient.get_schedules([])
    end

    test "handles error response" do
      Req.Test.stub(:mbta_api, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, _} = MbtaClient.get_schedules(trips: ["123"])
    end
  end
end
