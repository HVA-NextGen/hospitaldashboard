namespace HospitalDashboard.Core;

public sealed class HospitalSimulation
{
    public const int HistoryLimit = 720;
    private readonly Random random;

    public HospitalState State { get; private set; }

    /// <summary>Creates synthetic history and a current state; a seed makes tests reproducible.</summary>
    public HospitalSimulation(int seed, DateTimeOffset now)
    {
        random = new Random(seed);
        Ward[] wards =
        [
            new("emergency", "Päivystys", "Akuuttihoito", 32, 27, 14, 14),
            new("medicine", "Sisätaudit", "Osasto A", 48, 41, 15, 16),
            new("surgery", "Kirurgia", "Osasto B", 40, 31, 13, 13),
            new("icu", "Tehohoito", "Valvonta ja teho", 12, 11, 12, 12),
            new("children", "Lastentaudit", "Osasto C", 24, 16, 10, 10)
        ];
        State = new(now.AddSeconds(-5 * HistoryLimit), wards, 18, 38,
            [
                new("Sali 1", "Yleiskirurgia", "Käytössä"),
                new("Sali 2", "Ortopedia", "Käytössä"),
                new("Sali 3", "Päivystyskirurgia", "Vapaa"),
                new("Sali 4", "Pientoimenpiteet", "Valmistelu")
            ],
            [
                new("Hengityskoneet", 18, 11, 1),
                new("Potilasmonitorit", 64, 46, 3),
                new("Infuusiopumput", 90, 62, 4)
            ], []);
        var history = new List<TrendSample>(HistoryLimit);
        for (var i = 0; i < HistoryLimit; i++)
        {
            var nextTime = State.UpdatedAt.AddSeconds(5);
            State = Next(nextTime);
            history.Add(new(State.UpdatedAt, State.Wards, State.Queue, State.WaitMinutes));
        }
        State = State with { History = history.ToArray() };
    }

    /// <summary>Advances once to the supplied time without replaying background-tab ticks.</summary>
    public HospitalState Advance(DateTimeOffset now)
    {
        if (now <= State.UpdatedAt)
        {
            throw new ArgumentOutOfRangeException(nameof(now), "Simulation time must increase.");
        }
        var next = Next(now);
        var oldest = now.AddHours(-1);
        var history = State.History.Where(h => h.Timestamp > oldest)
            .TakeLast(HistoryLimit - 1)
            .Append(new(now, next.Wards, next.Queue, next.WaitMinutes))
            .ToArray();
        State = next with { History = history };
        return State;
    }

    private HospitalState Next(DateTimeOffset now)
    {
        var wards = State.Wards.Select(w => w with
        {
            Occupied = Drift(w.Occupied, (int)Math.Round(w.Capacity * TargetOccupancy(w.Id)), 0, w.Capacity),
            Staff = random.Next(12) == 0 ? Drift(w.Staff, w.RequiredStaff, w.RequiredStaff - 3, w.RequiredStaff + 2) : w.Staff
        }).ToArray();
        var queue = Drift(State.Queue, 18, 0, 45);
        var wait = Math.Clamp(queue * 2 + random.Next(-4, 5), 0, 100);
        var theatres = State.Theatres.Select(t => random.Next(40) == 0
            ? t with { Status = new[] { "Vapaa", "Käytössä", "Valmistelu" }[random.Next(3)] }
            : t).ToArray();
        var equipment = State.Equipment.Select(e => e with
        {
            InUse = Drift(e.InUse, (int)(e.Total * .72), 0, e.Total - e.Maintenance)
        }).ToArray();
        return State with { UpdatedAt = now, Wards = wards, Queue = queue, WaitMinutes = wait, Theatres = theatres, Equipment = equipment };
    }

    private int Drift(int value, int target, int min, int max)
    {
        var movement = random.Next(-1, 2);
        if (random.Next(3) == 0)
        {
            movement = Math.Sign(target - value);
        }
        return Math.Clamp(value + movement, min, max);
    }

    private static double TargetOccupancy(string wardId) => wardId switch
    {
        "emergency" => .88,
        "medicine" => .87,
        "icu" => .93,
        "children" => .68,
        _ => .78
    };
}
