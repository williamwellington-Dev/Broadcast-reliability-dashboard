let
    // Start from the parsed alarm table
    Source = Alarms,

    // Remove any duplicate alarm rows just in case the same event appears twice
    CleanAlarms = Table.Distinct(
        Source,
        {"timestamp", "channel", "description", "severity", "state"}
    ),

    // Keep only Air Feed Silence fault events
    SilenceFaults = Table.SelectRows(
        CleanAlarms,
        each Text.Contains(
            [description],
            "Air Feed Silence",
            Comparer.OrdinalIgnoreCase
        )
    ),

    // Derive station name from the beginning of the description
    AddStation = Table.AddColumn(
        SilenceFaults,
        "station",
        each try Text.BeforeDelimiter([description], " ") otherwise null,
        type text
    ),

    // For every silence event, find the NEXT Air Feed OK event
    // on the same Davicom channel
    AddClearTime = Table.AddColumn(
        AddStation,
        "clear_time",
        (fault as record) =>
            let
                PossibleClears = Table.SelectRows(
                    CleanAlarms,
                    (r as record) =>
                        r[channel] = fault[channel]
                        and r[timestamp] > fault[timestamp]
                        and Text.Contains(
                            r[description],
                            "Air Feed OK",
                            Comparer.OrdinalIgnoreCase
                        )
                ),

                SortedClears = Table.Sort(
                    PossibleClears,
                    {{"timestamp", Order.Ascending}}
                ),

                NextClear =
                    if Table.RowCount(SortedClears) > 0
                    then SortedClears{0}[timestamp]
                    else null
            in
                NextClear,
        type nullable datetime
    ),

    // Calculate duration in seconds
    AddDuration = Table.AddColumn(
        AddClearTime,
        "duration_seconds",
        each
            if [clear_time] = null
            then null
            else Duration.TotalSeconds([clear_time] - [timestamp]),
        type number
    ),

    // Rename the original timestamp to make its meaning clearer
    RenameStart = Table.RenameColumns(
        AddDuration,
        {{"timestamp", "start_time"}}
    ),

    // Keep only the fields useful to the dashboard
    KeepColumns = Table.SelectColumns(
        RenameStart,
        {
            "station",
            "start_time",
            "clear_time",
            "duration_seconds",
            "channel",
            "severity",
            "state",
            "site",
            "site_id",
            "report_time",
            "source_file"
        }
    ),

    Sorted = Table.Sort(
        KeepColumns,
        {{"start_time", Order.Ascending}}
    )
in
    Sorted
