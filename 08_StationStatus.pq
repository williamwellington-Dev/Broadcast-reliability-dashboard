let
    Source = Telemetry,

    // Latest Davicom report only
    LatestReport = List.Max(Reports[report_time]),

    LatestRows = Table.SelectRows(
        Source,
        each [report_time] = LatestReport
            and [kind] = "Digital"
    ),

    // Keep only the four monitored stations
    AddStation = Table.AddColumn(
        LatestRows,
        "station",
        each
            if Text.StartsWith([label], "CXRA") then "CXRA"
            else if Text.StartsWith([label], "CXRB") then "CXRB"
            else if Text.StartsWith([label], "CXRC") then "CXRC"
            else if Text.StartsWith([label], "CXRD") then "CXRD"
            else null,
        type text
    ),

    StationRows = Table.SelectRows(
        AddStation,
        each [station] <> null
    ),

    // Identify the three core health checks
    AddMetric = Table.AddColumn(
        StationRows,
        "metric",
        each
            if Text.Contains([label], "Air Feed", Comparer.OrdinalIgnoreCase)
                then "Air Feed"
            else if Text.Contains([label], "Pgm", Comparer.OrdinalIgnoreCase)
                and Text.Contains([label], "Ok", Comparer.OrdinalIgnoreCase)
                then "Program"
            else if Text.Contains([label], "MTS", Comparer.OrdinalIgnoreCase)
                and Text.Contains([label], "Ok", Comparer.OrdinalIgnoreCase)
                then "MTS"
            else null,
        type text
    ),

    CoreMetrics = Table.SelectRows(
        AddMetric,
        each [metric] <> null
    ),

    // Keep the raw Davicom state as well as its status
    KeepColumns = Table.SelectColumns(
        CoreMetrics,
        {
            "station",
            "metric",
            "label",
            "status",
            "digital_state",
            "report_time"
        }
    ),

    Sorted = Table.Sort(
        KeepColumns,
        {
            {"station", Order.Ascending},
            {"metric", Order.Ascending}
        }
    )
in
    Sorted
