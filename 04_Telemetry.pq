let
    Source = TelemetryRaw,

    // Parse numeric values only for Analog telemetry
    AddNumericValue = Table.AddColumn(
        Source,
        "numeric_value",
        each
            if [kind] = "Analog" then
                try Number.FromText(
                    Text.Select(
                        [value],
                        {"0","1","2","3","4","5","6","7","8","9",".","-"}
                    ),
                    "en-US"
                )
                otherwise null
            else
                null,
        type nullable number
    ),

    // Extract engineering unit from Analog telemetry
    AddUnit = Table.AddColumn(
        AddNumericValue,
        "unit",
        each
            if [kind] = "Analog" then
                let
                    RawUnit = Text.Remove(
                        [value],
                        {"0","1","2","3","4","5","6","7","8","9",".","-"}
                    )
                in
                    Text.Trim(RawUnit)
            else
                null,
        type nullable text
    ),

    // Preserve H/L digital states in a clearly named column
    AddDigitalState = Table.AddColumn(
        AddUnit,
        "digital_state",
        each
            if [kind] = "Digital"
            then [value]
            else null,
        type nullable text
    ),

    // Sort chronologically for easier checking
    Sorted = Table.Sort(
        AddDigitalState,
        {{"report_time", Order.Ascending}, {"channel", Order.Ascending}}
    )
in
    Sorted
