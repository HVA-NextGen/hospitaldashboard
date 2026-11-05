namespace HospitalDashboard.Core;

/// <summary>Urgency class assigned by the emergency response centre; A is the most urgent.</summary>
public enum Priority
{
    A,
    B,
    C,
    D
}

/// <summary>A point on the schematic map, in the map's own coordinate space.</summary>
public sealed record MapPoint(double X, double Y);

/// <summary>A settlement with the number of ambulance missions started there today.</summary>
public sealed record Place(string Id, string Name, MapPoint Position, int MissionsToday);

/// <summary>An ambulance station; Available counts units that are free to take a mission.</summary>
public sealed record Station(string Id, string Name, MapPoint Position, int Units, int Available);

/// <summary>The road from a settlement to the hospital, listed from the settlement towards the hospital.</summary>
public sealed record Road(string PlaceId, IReadOnlyList<MapPoint> Points);

/// <summary>
/// An ambulance on its way to the hospital. Progress is the fraction of the road already travelled.
/// No patient details are held: only the urgency class and a general reason for the mission.
/// </summary>
public sealed record IncomingUnit(string Id, Priority Priority, string Complaint, string FromPlaceId, int EtaMinutes, double Progress);

/// <summary>Fixed example data for the fictional Kaitajärven hyvinvointialue at one moment in time.</summary>
public static class ArrivalsData
{
    /// <summary>Local date and time the snapshot describes.</summary>
    public static DateTime Snapshot { get; } = new(2026, 11, 5, 20, 15, 0);

    /// <summary>Position of Kaitajärven keskussairaala, where all ambulances are heading.</summary>
    public static MapPoint Hospital { get; } = new(520, 410);

    /// <summary>Outline of lake Kaitajärvi as an SVG path.</summary>
    public const string LakePath = "M 380 200 C 400 130, 520 110, 600 150 C 680 190, 700 280, 640 330 C 580 380, 470 370, 410 320 C 360 280, 350 240, 380 200 Z";

    /// <summary>Settlements; the missions add up to the total of <see cref="MissionsToday"/>.</summary>
    public static IReadOnlyList<Place> Places { get; } =
    [
        new("kaitajarvi", "Kaitajärvi", new(520, 410), 41),
        new("koivulahti", "Koivulahti", new(200, 300), 17),
        new("salmisto", "Salmisto", new(820, 280), 14),
        new("pohjanniemi", "Pohjanniemi", new(520, 70), 9),
        new("rantala", "Rantala", new(760, 500), 11),
        new("kuusikyla", "Kuusikylä", new(250, 520), 8)
    ];

    /// <summary>Missions outside the named settlements, for example in sparsely populated areas.</summary>
    public const int OtherMissionsToday = 8;

    /// <summary>Roads from each settlement (except the hospital's own) to the hospital.</summary>
    public static IReadOnlyList<Road> Roads { get; } =
    [
        new("koivulahti", [new(200, 300), new(290, 350), new(400, 395), new(520, 410)]),
        new("salmisto", [new(820, 280), new(740, 350), new(640, 400), new(520, 410)]),
        new("pohjanniemi", [new(520, 70), new(330, 110), new(300, 240), new(360, 340), new(430, 395), new(520, 410)]),
        new("rantala", [new(760, 500), new(650, 470), new(580, 430), new(520, 410)]),
        new("kuusikyla", [new(250, 520), new(360, 470), new(450, 430), new(520, 410)])
    ];

    /// <summary>Ambulance stations and the units free right now.</summary>
    public static IReadOnlyList<Station> Stations { get; } =
    [
        new("kaitajarvi", "Kaitajärven asema", new(552, 386), 6, 3),
        new("koivulahti", "Koivulahden asema", new(226, 318), 2, 1),
        new("salmisto", "Salmiston asema", new(806, 300), 2, 1),
        new("pohjanniemi", "Pohjanniemen asema", new(546, 86), 2, 1),
        new("rantala", "Rantalan asema", new(742, 520), 2, 2)
    ];

    /// <summary>Ambulances heading to the hospital, soonest arrival first.</summary>
    public static IReadOnlyList<IncomingUnit> Incoming { get; } =
    [
        new("KO-12", Priority.A, "Rintakipu", "koivulahti", 7, 0.62),
        new("SA-3", Priority.B, "Tapaturma, putoaminen", "salmisto", 14, 0.45),
        new("RA-7", Priority.C, "Vatsakipu", "rantala", 19, 0.30),
        new("PO-2", Priority.B, "Hengitysvaikeus", "pohjanniemi", 22, 0.25),
        new("KU-4", Priority.D, "Siirtokuljetus", "kuusikyla", 31, 0.10)
    ];

    /// <summary>Missions started in each completed hour of today (00-19).</summary>
    public static IReadOnlyList<int> HourlyToday { get; } = [2, 1, 1, 1, 2, 2, 3, 5, 6, 7, 8, 7, 8, 6, 7, 8, 9, 10, 8, 7];

    /// <summary>Missions started in each hour on a typical Thursday (00-23).</summary>
    public static IReadOnlyList<int> HourlyTypical { get; } = [2, 1, 1, 1, 1, 2, 2, 4, 5, 7, 8, 8, 7, 7, 7, 8, 8, 9, 8, 7, 6, 5, 3, 2];

    /// <summary>Total missions started today up to the snapshot.</summary>
    public static int MissionsToday => Places.Sum(p => p.MissionsToday) + OtherMissionsToday;

    /// <summary>Missions a typical Thursday has had by the same hour.</summary>
    public static int TypicalSoFar => HourlyTypical.Take(HourlyToday.Count).Sum();
}
