defmodule ByeByeByeTest do
  use ExUnit.Case, async: true
  alias TransitRealtime.FeedHeader
  alias TransitRealtime.FeedMessage
  alias TransitRealtime.FeedEntity
  alias TransitRealtime.TripUpdate
  alias TransitRealtime.TripDescriptor
  alias TransitRealtime.TripUpdate.StopTimeUpdate

  describe "get_cancellations/1" do
    test "filters alerts with cancellation effects" do
      alerts = [
        %{"attributes" => %{"effect" => "CANCELLATION"}},
        %{"attributes" => %{"effect" => "NO_SERVICE"}}
      ]

      result = ByeByeBye.get_cancellations(alerts)
      assert length(result) == 2
    end

    test "filters out alerts with non-cancellation effects" do
      alerts = [
        %{"attributes" => %{"effect" => "DELAY"}},
        %{"attributes" => %{"effect" => "OTHER"}}
      ]

      result = ByeByeBye.get_cancellations(alerts)
      assert result == []
    end

    test "handles mixed alerts" do
      alerts = [
        %{"attributes" => %{"effect" => "CANCELLATION"}},
        %{"attributes" => %{"effect" => "DELAY"}},
        %{"attributes" => %{"effect" => "NO_SERVICE"}},
        %{"attributes" => %{"effect" => "OTHER"}}
      ]

      result = ByeByeBye.get_cancellations(alerts)
      assert length(result) == 2

      effects = Enum.map(result, & &1["attributes"]["effect"])
      assert "CANCELLATION" in effects
      assert "NO_SERVICE" in effects
    end

    test "handles empty list" do
      result = ByeByeBye.get_cancellations([])
      assert result == []
    end
  end

  describe "encode_feeds/1" do
    test "encodes feeds" do
      entities = %FeedEntity{
        id: "123",
        trip_update: %TripUpdate{
          timestamp: 1_706_000_000,
          trip: %TripDescriptor{
            trip_id: "123",
            route_id: "Red",
            schedule_relationship: :CANCELED,
            start_date: "20240123"
          },
          stop_time_update: [
            %StopTimeUpdate{
              stop_id: "place-abc",
              stop_sequence: 1,
              schedule_relationship: :SKIPPED
            },
            %StopTimeUpdate{
              stop_id: "place-def",
              stop_sequence: 2,
              schedule_relationship: :SKIPPED
            }
          ]
        }
      }

      message = %FeedMessage{
        header: %FeedHeader{
          gtfs_realtime_version: "2.0",
          timestamp: 1_793_886_005
        },
        entity: [entities]
      }

      {json, pb} = ByeByeBye.encode_feeds(message)

      assert json =~ "\"timestamp\":1793886005"
      assert json =~ "\"trip_update\":"
      assert json =~ "\"schedule_relationship\":\"CANCELED\""
      assert json =~ "\"schedule_relationship\":\"SKIPPED\""

      assert pb =~ "20240123"
      assert pb =~ "Red"
      assert pb =~ "place-abc"
    end
  end
end
