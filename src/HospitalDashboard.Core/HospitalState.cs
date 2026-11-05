namespace HospitalDashboard.Core;

public enum AlertLevel { Normal, Attention, Critical }

public sealed record Ward(string Id, string Name, string Specialty, int Capacity, int Occupied, int Staff, int RequiredStaff)
{
    public int Available => Capacity - Occupied;
    public double Occupancy => (double)Occupied / Capacity;
    public AlertLevel Level => Occupancy >= .95 ? AlertLevel.Critical
        : Occupancy >= .85 || Staff < RequiredStaff ? AlertLevel.Attention : AlertLevel.Normal;
}

public sealed record Equipment(string Name, int Total, int InUse, int Maintenance)
{
    public int Available => Total - InUse - Maintenance;
}

public sealed record Theatre(string Name, string Specialty, string Status);

public sealed record OperationalAlert(string Id, string? WardId, AlertLevel Level, string Title, string Detail);

public sealed record TrendSample(DateTimeOffset Timestamp, IReadOnlyList<Ward> Wards, int Queue, int WaitMinutes)
{
    /// <summary>Returns the occupancy of the selected ward or the whole hospital.</summary>
    public double Occupancy(string? wardId)
    {
        var wards = HospitalState.SelectWards(Wards, wardId);
        return (double)wards.Sum(w => w.Occupied) / wards.Sum(w => w.Capacity);
    }
}

public sealed record HospitalState(
    DateTimeOffset UpdatedAt,
    IReadOnlyList<Ward> Wards,
    int Queue,
    int WaitMinutes,
    IReadOnlyList<Theatre> Theatres,
    IReadOnlyList<Equipment> Equipment,
    IReadOnlyList<TrendSample> History)
{
    /// <summary>Returns only alerts relevant to the selection, retaining hospital-wide alerts.</summary>
    public IReadOnlyList<OperationalAlert> Alerts(string? wardId)
    {
        var alerts = new List<OperationalAlert>();
        foreach (var ward in SelectWards(Wards, wardId))
        {
            if (ward.Occupancy >= .85)
            {
                alerts.Add(new($"beds-{ward.Id}", ward.Id,
                    ward.Occupancy >= .95 ? AlertLevel.Critical : AlertLevel.Attention,
                    $"{ward.Name}: korkea käyttöaste", $"{ward.Available} vapaata paikkaa / {ward.Capacity} paikkaa."));
            }
            if (ward.Staff < ward.RequiredStaff)
            {
                alerts.Add(new($"staff-{ward.Id}", ward.Id, AlertLevel.Attention,
                    $"{ward.Name}: henkilöstövaje", $"Vuorossa {ward.Staff}, tavoite {ward.RequiredStaff}."));
            }
        }
        if (WaitMinutes >= 45)
        {
            alerts.Add(new("ed-wait", null, WaitMinutes >= 60 ? AlertLevel.Critical : AlertLevel.Attention,
                "Päivystyksen odotusaika koholla", $"Koko sairaala: arvioitu odotusaika {WaitMinutes} min."));
        }
        foreach (var equipment in Equipment.Where(e => e.Available == 0))
        {
            alerts.Add(new($"equipment-{equipment.Name}", null, AlertLevel.Attention,
                $"{equipment.Name}: ei vapaita laitteita", "Koko sairaala: kaikki laitteet käytössä tai huollossa."));
        }
        return alerts.OrderByDescending(a => a.Level).ThenBy(a => a.Id, StringComparer.Ordinal).ToArray();
    }

    /// <summary>Selects a known ward or all wards; invalid identifiers are rejected.</summary>
    public static IReadOnlyList<Ward> SelectWards(IReadOnlyList<Ward> wards, string? wardId)
    {
        if (wardId is null)
        {
            return wards;
        }
        var ward = wards.SingleOrDefault(w => w.Id == wardId)
            ?? throw new ArgumentException("Unknown ward identifier.", nameof(wardId));
        return [ward];
    }
}
