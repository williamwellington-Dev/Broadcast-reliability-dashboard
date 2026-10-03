let
    Source = Alarms,

    RemoveDuplicates = Table.Distinct(
        Source,
        {"timestamp", "channel", "description", "severity", "state"}
    ),

    Sorted = Table.Sort(
        RemoveDuplicates,
        {{"timestamp", Order.Descending}}
    )
in
    Sorted
