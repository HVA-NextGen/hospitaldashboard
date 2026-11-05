using HospitalDashboard.Core;

namespace HospitalDashboard.Tests;

public class SimulationTests
{
    private static readonly DateTimeOffset Start = new(2026, 11, 5, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void SameSeedProducesSameHistory()
    {
        var first = new HospitalSimulation(42, Start);
        var second = new HospitalSimulation(42, Start);
        Assert.Equal(first.State.Wards, second.State.Wards);
        Assert.Equal(first.State.History.Select(h => h.Queue), second.State.History.Select(h => h.Queue));
        Assert.Equal(Start, first.State.UpdatedAt);
        Assert.Equal(HospitalSimulation.HistoryLimit, first.State.History.Count);
        Assert.Equal(first.State.Wards, first.State.History[^1].Wards);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(42)]
    [InlineData(12345)]
    public void SustainedUpdatesKeepCountsCoherentAndHistoryBounded(int seed)
    {
        var simulation = new HospitalSimulation(seed, Start);
        var initial = simulation.State;
        for (var i = 1; i <= 1500; i++)
        {
            var state = simulation.Advance(Start.AddSeconds(5 * i));
            Assert.All(state.Wards, ward =>
            {
                Assert.InRange(ward.Occupied, 0, ward.Capacity);
                Assert.Equal(ward.Capacity, ward.Occupied + ward.Available);
                Assert.InRange(ward.Staff, 0, ward.RequiredStaff + 2);
            });
            Assert.All(state.Equipment, item =>
            {
                Assert.InRange(item.Available, 0, item.Total);
                Assert.Equal(item.Total, item.Available + item.InUse + item.Maintenance);
            });
            Assert.Equal(4, state.Theatres.Count);
            Assert.All(state.Theatres, t => Assert.Contains(t.Status, new[] { "Vapaa", "Käytössä", "Valmistelu" }));
            Assert.InRange(state.Queue, 0, 45);
            Assert.InRange(state.WaitMinutes, 0, 100);
            Assert.InRange(state.History.Count, 1, HospitalSimulation.HistoryLimit);
            Assert.Equal(state.UpdatedAt, state.History[^1].Timestamp);
            Assert.Equal(state.Wards, state.History[^1].Wards);
        }
        Assert.NotEqual(initial.UpdatedAt, simulation.State.UpdatedAt);
        Assert.Equal(Start, initial.UpdatedAt);
    }

    [Fact]
    public void BackgroundGapDoesNotReplayOrRetainStaleHistory()
    {
        var simulation = new HospitalSimulation(42, Start);
        simulation.Advance(Start.AddHours(2));
        Assert.Single(simulation.State.History);
        Assert.Equal(Start.AddHours(2), simulation.State.History[0].Timestamp);
    }

    [Fact]
    public void NonIncreasingClockIsRejected()
    {
        var simulation = new HospitalSimulation(42, Start);
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Advance(Start));
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Advance(Start.AddSeconds(-1)));
    }

    [Fact]
    public void FilteringSelectsOnlyTheRequestedWard()
    {
        var state = new HospitalSimulation(42, Start).State;
        Assert.Equal(5, HospitalState.SelectWards(state.Wards, null).Count);
        var selected = HospitalState.SelectWards(state.Wards, "icu");
        Assert.Equal("Tehohoito", Assert.Single(selected).Name);
        Assert.Equal(selected[0].Occupancy, state.History[^1].Occupancy("icu"));
        Assert.Throws<ArgumentException>(() => HospitalState.SelectWards(state.Wards, "unknown"));
    }

    [Theory]
    [InlineData(84, 10, AlertLevel.Normal, false)]
    [InlineData(85, 10, AlertLevel.Attention, true)]
    [InlineData(95, 10, AlertLevel.Critical, true)]
    [InlineData(80, 9, AlertLevel.Attention, false)]
    public void WardStatusAndAlertsUseTheSameThresholds(int occupied, int staff, AlertLevel level, bool bedAlert)
    {
        var state = new HospitalSimulation(42, Start).State with
        {
            Wards = [new("test", "Testiosasto", "Esittely", 100, occupied, staff, 10)],
            WaitMinutes = 0,
            Equipment = []
        };
        Assert.Equal(level, state.Wards[0].Level);
        var alerts = state.Alerts(null);
        Assert.Equal(bedAlert, alerts.Any(a => a.Id == "beds-test"));
        Assert.Equal(staff < 10, alerts.Any(a => a.Id == "staff-test"));
        if (bedAlert)
        {
            Assert.Equal(level, alerts.Single(a => a.Id == "beds-test").Level);
        }
    }

    [Theory]
    [InlineData(44, 0)]
    [InlineData(45, 1)]
    [InlineData(60, 2)]
    public void HospitalWaitAlertHasExplicitBoundaries(int wait, int severity)
    {
        var state = new HospitalSimulation(42, Start).State with { WaitMinutes = wait };
        var alert = state.Alerts("children").SingleOrDefault(a => a.Id == "ed-wait");
        if (severity == 0)
        {
            Assert.Null(alert);
        }
        else
        {
            Assert.NotNull(alert);
            Assert.Null(alert.WardId);
            Assert.Equal((AlertLevel)severity, alert.Level);
        }
    }

    [Fact]
    public void WardFilterKeepsHospitalAlertsAndExcludesOtherWards()
    {
        var state = new HospitalSimulation(42, Start).State with
        {
            Wards = [
                new("icu", "Tehohoito", "", 10, 10, 10, 10),
                new("children", "Lastentaudit", "", 10, 5, 10, 10)
            ],
            WaitMinutes = 60,
            Equipment = [new("Testilaite", 2, 1, 1)]
        };
        var alerts = state.Alerts("children");
        Assert.DoesNotContain(alerts, a => a.WardId == "icu");
        Assert.Contains(alerts, a => a.Id == "ed-wait");
        Assert.Contains(alerts, a => a.Id == "equipment-Testilaite");
        Assert.Contains(state.Alerts(null), a => a.WardId == "icu");
    }
}
