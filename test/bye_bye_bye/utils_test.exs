defmodule ByeByeBye.UtilsTest do
  use ExUnit.Case, async: true
  alias ByeByeBye.Utils
  alias TransitRealtime.FeedEntity
  alias TransitRealtime.TripUpdate
  alias TransitRealtime.TripDescriptor
  alias TransitRealtime.TripUpdate.StopTimeUpdate

  doctest ByeByeBye.Utils

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

  describe "period_intersection/2" do
    test "returns intersection when DateTime periods overlap" do
      period1 = {~U[2024-01-01T10:00:00Z], ~U[2024-01-01T14:00:00Z]}
      period2 = {~U[2024-01-01T12:00:00Z], ~U[2024-01-01T16:00:00Z]}

      expected = {~U[2024-01-01T12:00:00Z], ~U[2024-01-01T14:00:00Z]}
      assert Utils.period_intersection(period1, period2) == expected
    end

    test "returns nil when DateTime periods do not overlap" do
      period1 = {~U[2024-01-01T10:00:00Z], ~U[2024-01-01T12:00:00Z]}
      period2 = {~U[2024-01-01T13:00:00Z], ~U[2024-01-01T15:00:00Z]}

      assert Utils.period_intersection(period1, period2) == nil
    end

    test "handles adjacent DateTime periods with exact boundary" do
      period1 = {~U[2024-01-01T10:00:00Z], ~U[2024-01-01T12:00:00Z]}
      period2 = {~U[2024-01-01T12:00:00Z], ~U[2024-01-01T14:00:00Z]}

      expected = {~U[2024-01-01T12:00:00Z], ~U[2024-01-01T12:00:00Z]}
      assert Utils.period_intersection(period1, period2) == expected
    end

    test "handles one DateTime period fully contained in another" do
      period1 = {~U[2024-01-01T10:00:00Z], ~U[2024-01-01T16:00:00Z]}
      period2 = {~U[2024-01-01T12:00:00Z], ~U[2024-01-01T14:00:00Z]}

      assert Utils.period_intersection(period1, period2) == period2
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
      now = ~U[2024-01-23 08:53:20Z]
      start_date = "20240123"

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
                   schedule_relationship: "CANCELED",
                   start_date: ^start_date
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

    test "start_date accounts for time zone, midnight-3 am as previous day's schedule" do
      trip_id = "123"
      # 2:53 AM in America/New_York
      now = ~U[2024-01-24 07:53:20Z]

      schedule = []

      result = Utils.build_cancellation_entity({trip_id, schedule}, now)

      assert %FeedEntity{
               trip_update: %TripUpdate{
                 trip: %TripDescriptor{
                   start_date: "20240123"
                 }
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

    test "processes alert with no end time in active period" do
      now = DateTime.new!(~D[2024-01-20], ~T[12:00:00], "America/New_York")

      alert = %{
        "attributes" => %{
          "active_period" => [
            %{
              "start" => "2024-01-20T13:00:00-05:00"
              # No end time specified
            }
          ],
          "informed_entity" => [
            %{"trip" => "123", "stop" => nil}
          ]
        }
      }

      Req.Test.stub(:mbta_api, fn conn ->
        assert conn.request_path == "/schedules"
        assert conn.params["trip"] == "123"
        assert conn.params["min_time"] == "13:00:00"
        # Should use end of service day (02:59:59 next day) as the max time
        assert conn.params["max_time"] == "26:59:59"

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
  end

  describe "protox_struct_to_map/1" do
    test "converts a simple Protox struct to a map" do
      struct = %FeedEntity{
        id: "test_id",
        is_deleted: false
      }

      result = Utils.protox_struct_to_map(struct)

      refute is_struct(result)

      assert %{id: "test_id", is_deleted: false} = result

      refute Map.has_key?(result, :__uf__)
    end

    test "recursively converts nested Protox structs" do
      struct = %FeedEntity{
        id: "test_id",
        trip_update: %TripUpdate{
          trip: %TripDescriptor{
            trip_id: "trip_123",
            route_id: "route_456",
            schedule_relationship: "CANCELED"
          },
          stop_time_update: [
            %StopTimeUpdate{
              stop_id: "stop_1",
              stop_sequence: 1,
              schedule_relationship: "SKIPPED"
            }
          ]
        }
      }

      result = Utils.protox_struct_to_map(struct)

      refute is_struct(result)
      refute is_struct(result.trip_update)
      refute is_struct(result.trip_update.trip)
      refute is_struct(hd(result.trip_update.stop_time_update))

      assert is_list(result.trip_update.stop_time_update)
      assert length(result.trip_update.stop_time_update) == 1
      assert is_map(hd(result.trip_update.stop_time_update))
      assert result.id == "test_id"
      assert result.trip_update.trip.trip_id == "trip_123"
      assert result.trip_update.trip.route_id == "route_456"
      assert hd(result.trip_update.stop_time_update).stop_id == "stop_1"

      assert %{
               id: "test_id",
               trip_update: %{
                 trip: %{trip_id: "trip_123"},
                 stop_time_update: [%{stop_id: "stop_1"}]
               }
             } = result
    end

    test "returns non-struct values unchanged" do
      assert Utils.protox_struct_to_map("string") == "string"
      assert Utils.protox_struct_to_map(123) == 123
      assert Utils.protox_struct_to_map([1, 2, 3]) == [1, 2, 3]
      assert Utils.protox_struct_to_map(%{a: 1, b: 2}) == %{a: 1, b: 2}
      assert Utils.protox_struct_to_map(nil) == nil
    end

    test "converts lists of Protox structs" do
      structs = [
        %StopTimeUpdate{
          stop_id: "stop_1",
          stop_sequence: 1,
          schedule_relationship: "SKIPPED"
        },
        %StopTimeUpdate{
          stop_id: "stop_2",
          stop_sequence: 2,
          schedule_relationship: "SKIPPED"
        }
      ]

      result = Utils.protox_struct_to_map(structs)

      Enum.each(result, fn item ->
        refute is_struct(item)
        refute Map.has_key?(item, :__uf__)
      end)

      assert [%{stop_id: "stop_1", stop_sequence: 1}, %{stop_id: "stop_2", stop_sequence: 2}] =
               result
    end
  end
end
