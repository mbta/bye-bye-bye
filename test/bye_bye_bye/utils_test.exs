defmodule ByeByeBye.UtilsTest do
  use ExUnit.Case, async: true
  alias ByeByeBye.Utils
  alias TransitRealtime.FeedEntity
  alias TransitRealtime.TripUpdate
  alias TransitRealtime.TripDescriptor
  alias TransitRealtime.TripUpdate.StopTimeUpdate

  setup do
    Application.put_env(:bye_bye_bye, :mbta_api_url, "http://api-mock-url")
    Application.put_env(:bye_bye_bye, :mbta_api_key, "test_api_key")
    :ok
  end

  describe "service_day/1" do
    test "returns same date for times after 3am" do
      datetime = DateTime.new!(~D[2024-01-20], ~T[12:00:00], "America/New_York")
      assert Utils.service_day(datetime) == ~D[2024-01-20]
    end

    test "returns previous date for times before 3am" do
      datetime = DateTime.new!(~D[2024-01-20], ~T[02:59:59], "America/New_York")
      assert Utils.service_day(datetime) == ~D[2024-01-19]
    end

    test "returns same date at exactly 3am" do
      datetime = DateTime.new!(~D[2024-01-20], ~T[03:00:00], "America/New_York")
      assert Utils.service_day(datetime) == ~D[2024-01-20]
    end
  end

  describe "current_service_day?/2" do
    test "returns true for times in same service day" do
      now = DateTime.new!(~D[2024-01-20], ~T[07:00:00], "America/New_York")
      check_time = DateTime.new!(~D[2024-01-20], ~T[10:00:00], "America/New_York")

      assert Utils.current_service_day?(check_time, now)
    end

    test "returns true for early morning times in same service day" do
      now = DateTime.new!(~D[2024-01-20], ~T[07:00:00], "America/New_York")
      check_time = DateTime.new!(~D[2024-01-21], ~T[02:00:00], "America/New_York")

      assert Utils.current_service_day?(check_time, now)
    end

    test "returns false for times in previous service day" do
      now = DateTime.new!(~D[2024-01-20], ~T[07:00:00], "America/New_York")
      check_time = DateTime.new!(~D[2024-01-19], ~T[15:00:00], "America/New_York")

      refute Utils.current_service_day?(check_time, now)
    end

    test "returns false for times in next service day" do
      now = DateTime.new!(~D[2024-01-20], ~T[07:00:00], "America/New_York")
      check_time = DateTime.new!(~D[2024-01-21], ~T[15:00:00], "America/New_York")

      refute Utils.current_service_day?(check_time, now)
    end

    test "handles service day cutoff" do
      now = DateTime.new!(~D[2024-01-20], ~T[02:00:00], "America/New_York")
      same_service_day = DateTime.new!(~D[2024-01-20], ~T[04:00:00], "America/New_York")

      refute Utils.current_service_day?(same_service_day, now)
    end
  end

  describe "build_cancellation_entity/2" do
    test "creates a feed entity with proper cancellation details" do
      trip_id = "123"
      now = 1_706_000_000

      schedule = [
        %{
          "attributes" => %{"stop_sequence" => 1},
          "relationships" => %{
            "route" => %{"data" => %{"id" => "Red"}},
            "stop" => %{"data" => %{"id" => "place-abc"}},
            "trip" => %{"data" => %{"id" => "123"}}
          }
        },
        %{
          "attributes" => %{"stop_sequence" => 2},
          "relationships" => %{
            "route" => %{"data" => %{"id" => "Red"}},
            "stop" => %{"data" => %{"id" => "place-def"}},
            "trip" => %{"data" => %{"id" => "123"}}
          }
        }
      ]

      result = Utils.build_cancellation_entity({trip_id, schedule}, now)

      assert %FeedEntity{
               id: "123",
               trip_update: %TripUpdate{
                 timestamp: 1_706_000_000,
                 trip: %TripDescriptor{
                   trip_id: "123",
                   route_id: "Red",
                   schedule_relationship: "CANCELED"
                 },
                 stop_time_update: [
                   %StopTimeUpdate{
                     stop_id: "place-abc",
                     stop_sequence: 1,
                     schedule_relationship: "SKIPPED"
                   },
                   %StopTimeUpdate{
                     stop_id: "place-def",
                     stop_sequence: 2,
                     schedule_relationship: "SKIPPED"
                   }
                 ]
               }
             } = result
    end
  end

  describe "get_affected_schedules/2" do
    test "processes alert with trip cancellations" do
      now = DateTime.new!(~D[2024-01-20], ~T[12:00:00], "America/New_York")

      alert = %{
        "attributes" => %{
          "active_period" => [
            %{
              "start" => "2024-01-20T13:00:00-05:00",
              "end" => "2024-01-20T14:00:00-05:00"
            }
          ],
          "informed_entity" => [
            %{"trip" => "123", "stop" => nil},
            %{"trip" => "456", "stop" => nil}
          ]
        }
      }

      Req.Test.stub(:mbta_api, fn conn ->
        assert conn.request_path == "/schedules"
        assert conn.params["trip"] == "123,456"
        assert conn.params["min_time"] == "13:00:00"
        assert conn.params["max_time"] == "14:00:00"

        Req.Test.json(conn, %{
          "data" => [
            %{
              "attributes" => %{"stop_sequence" => 1},
              "relationships" => %{
                "trip" => %{"data" => %{"id" => "123"}},
                "route" => %{"data" => %{"id" => "Red"}},
                "stop" => %{"data" => %{"id" => "stop-1"}}
              }
            }
          ]
        })
      end)

      result = Utils.get_affected_schedules(alert, now)
      assert map_size(result) == 1
      assert Map.has_key?(result, "123")
    end

    test "processes alert with route cancellations" do
      now = DateTime.new!(~D[2024-01-20], ~T[12:00:00], "America/New_York")

      alert = %{
        "attributes" => %{
          "active_period" => [
            %{
              "start" => "2024-01-20T13:00:00-05:00",
              "end" => "2024-01-20T14:00:00-05:00"
            }
          ],
          "informed_entity" => [
            %{"route" => "Red", "trip" => nil, "stop" => nil}
          ]
        }
      }

      Req.Test.stub(:mbta_api, fn conn ->
        assert conn.request_path == "/schedules"
        assert conn.params["route"] == "Red"
        assert conn.params["min_time"] == "13:00:00"
        assert conn.params["max_time"] == "14:00:00"

        Req.Test.json(conn, %{
          "data" => [
            %{
              "attributes" => %{"stop_sequence" => 1},
              "relationships" => %{
                "trip" => %{"data" => %{"id" => "123"}},
                "route" => %{"data" => %{"id" => "Red"}},
                "stop" => %{"data" => %{"id" => "stop-1"}}
              }
            }
          ]
        })
      end)

      result = Utils.get_affected_schedules(alert, now)
      assert map_size(result) == 1
      assert Map.has_key?(result, "123")
    end

    test "ignores alerts outside current service day" do
      now = DateTime.new!(~D[2024-01-20], ~T[12:00:00], "America/New_York")

      alert = %{
        "attributes" => %{
          "active_period" => [
            %{
              "start" => "2024-01-18T15:00:00-05:00",
              "end" => "2024-01-19T15:00:00-05:00"
            }
          ],
          "informed_entity" => [
            %{"trip" => "123", "stop" => nil}
          ]
        }
      }

      Req.Test.stub(:mbta_api, fn _conn ->
        assert false, "There should be no request made"
      end)

      result = Utils.get_affected_schedules(alert, now)
      assert result == %{}
    end
  end
end
