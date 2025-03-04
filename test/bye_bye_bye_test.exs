defmodule ByeByeByeTest do
  use ExUnit.Case, async: true

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
end
