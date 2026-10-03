let
    Source = TelemetryRaw,

    KeepColumns = Table.SelectColumns(
        Source,
        {"site", "site_id", "report_time", "source_file"}
    ),

    RemoveDuplicates = Table.Distinct(KeepColumns),

    Sorted = Table.Sort(
        RemoveDuplicates,
        {{"report_time", Order.Ascending}}
    )
in
    Sorted
