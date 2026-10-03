let
    Source = Telemetry,

    // Use only the most recent Davicom report
    LatestReport = List.Max(Reports[report_time]),

    LatestDigital = Table.SelectRows(
        Source,
        each [report_time] = LatestReport
            and [kind] = "Digital"
    ),

    // Normalize extra spaces in Davicom labels
    AddCleanLabel = Table.AddColumn(
        LatestDigital,
        "clean_label",
        each Text.Combine(
            List.Select(
                Text.Split([label], " "),
                each _ <> ""
            ),
            " "
        ),
        type text
    ),

    // Keep the infrastructure points used on the dashboard
    KeepInfrastructure = Table.SelectRows(
        AddCleanLabel,
        each
            [clean_label] = "On Hydro"
            or [clean_label] = "Not On Generator"
            or [clean_label] = "PTP - GPS Sync Ok"
            or [clean_label] = "PTP Clock - Lock Ok"
            or [clean_label] = "Generator Auto"
            or [clean_label] = "Generator Battery OK"
    ),

    // Expected digital state for THIS site configuration
    AddExpectedState = Table.AddColumn(
        KeepInfrastructure,
        "expected_state",
        each
            if [clean_label] = "On Hydro" then "L"
            else if [clean_label] = "Not On Generator" then "H"
            else if [clean_label] = "PTP - GPS Sync Ok" then "L"
            else if [clean_label] = "PTP Clock - Lock Ok" then "L"
            else if [clean_label] = "Generator Auto" then "H"
            else if [clean_label] = "Generator Battery OK" then "H"
            else null,
        type text
    ),

    // Compare actual Davicom state with expected facility state
    AddHealth = Table.AddColumn(
        AddExpectedState,
        "health",
        each
            if [digital_state] = [expected_state]
            then "Healthy"
            else "Attention",
        type text
    ),

    KeepColumns = Table.SelectColumns(
        AddHealth,
        {
            "clean_label",
            "status",
            "digital_state",
            "expected_state",
            "health",
            "report_time"
        }
    ),

    RenameLabel = Table.RenameColumns(
        KeepColumns,
        {{"clean_label", "label"}}
    )
in
    RenameLabel
