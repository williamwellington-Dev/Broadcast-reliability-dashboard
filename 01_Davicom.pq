// I USED CLAUDE AI TO CREATE MY PARSER - William Wellington 
// From here i am able to use the information given to me from Davicom and make it readable by power BI
// ============================================================================
//  DAVICOM MAC  —  Alarm & Telemetry Report Parser  (Power Query / M)
// ----------------------------------------------------------------------------
//  Turns the HTML reports a Davicom MAC unit exports into two tidy tables:
//    • Alarms    — timestamped fault/clear events (for dead-air, MTTR, counts)
//    • Telemetry — analog readings + digital state points (power, RF, environ.)
//  One query reads an ENTIRE FOLDER of reports, so the dataset grows on refresh
//  as new files arrive. The same query works for every Davicom site unchanged.
//
//  HOW TO USE  (Power BI Desktop)
//  1. Home ▸ Transform data  (opens Power Query Editor)
//  2. Home ▸ New Source ▸ Blank Query
//  3. View ▸ Advanced Editor  — delete everything, paste this whole file
//  4. Set the SOURCE in step 3 below (SharePoint folder = production,
//     single local file = testing). Instructions are inline.
//  5. Done. This query ("Davicom") returns a record with [Alarms] & [Telemetry].
//  6. Create two more Blank Queries and load ONLY these:
//        Alarms     →   = Davicom[Alarms]
//        Telemetry  →   = Davicom[Telemetry]
//     (Right-click the "Davicom" query ▸ Enable load = OFF; keep the two above.)
// ============================================================================
let
    //------------------------------------------------------------------------
    // 1. HELPER — strip HTML tags from a single string
    //------------------------------------------------------------------------
    StripTags = (s as text) as text =>
        let
            parts   = Text.Split(s, "<"),
            cleaned = List.Transform(parts, (frag) =>
                        let gt = Text.PositionOf(frag, ">")
                        in  if gt = -1 then frag else Text.Range(frag, gt + 1)),
            joined  = Text.Combine(cleaned, "")
        in
            Text.Trim(joined),

    //------------------------------------------------------------------------
    // 2. HELPER — a chunk of HTML → list of rows, each row a list of cell texts
    //------------------------------------------------------------------------
    RowsFromHtml = (html as text) as list =>
        let
            noBr     = Text.Replace(Text.Replace(html, "<br/>", " "), "<br>", " "),
            trChunks = List.Skip(Text.Split(noBr, "<tr")),      // drop pre-<tr> text
            rows     = List.Transform(trChunks, (tr) =>
                let
                    tdChunks = List.Skip(Text.Split(tr, "<td")),// drop pre-<td> text
                    cells    = List.Transform(tdChunks, (td) =>
                        let
                            afterGt = Text.Range(td, Text.PositionOf(td, ">") + 1),
                            endPos  = Text.PositionOf(afterGt, "</td>"),
                            raw     = if endPos = -1 then afterGt else Text.Start(afterGt, endPos)
                        in
                            StripTags(raw))
                in
                    cells),
            nonEmpty = List.Select(rows, (r) => List.Count(List.Select(r, (c) => c <> "")) > 0)
        in
            nonEmpty,

    //------------------------------------------------------------------------
    // 3. SOURCE  — choose ONE of the two options
    //------------------------------------------------------------------------

    // ---- OPTION A · LOCAL FOLDER (testing / sample data) ------------------
    //   Point this at the folder of reports made by sample-data/generate_reports.py
    LocalFolder = "C:\path\to\davicom-reliability-dashboard\sample-data\reports",
    AllLocalFiles = Folder.Files(LocalFolder),
    Files = Table.SelectRows(
        AllLocalFiles,
        each Text.EndsWith([Name], ".html") and Text.StartsWith([Name], "almMAC")
    ),

    // ---- OPTION B · PRODUCTION · SharePoint document library ---------------
    //   In production, Davicom reports land in a SharePoint folder and this
    //   option is used instead. Comment out Option A and uncomment below.
    //   Set SiteUrl to your SharePoint SITE (not the library) URL.
    // SiteUrl = "https://YOURTENANT.sharepoint.com/sites/YOURSITE",
    // TargetFolder = SiteUrl & "/Shared Documents/Davicom Reports/",
    // AllSharePointFiles = SharePoint.Files(SiteUrl, [ApiVersion = 15]),
    // Files =
    //     Table.SelectRows(
    //         AllSharePointFiles,
    //         each
    //             [Folder Path] = TargetFolder
    //             and Text.EndsWith([Name], ".html")
    //             and Text.StartsWith([Name], "almMAC")
    //     ),

    //------------------------------------------------------------------------
    // 4. PARSE ONE FILE  →  record [Alarms = table, Telemetry = table]
    //------------------------------------------------------------------------
    ParseOne = (content as binary, fileName as text) as record =>
        let
            txt      = Text.FromBinary(content, TextEncoding.Utf8),

            // -- metadata (header table) --
            siteName = Text.Trim(Text.BetweenDelimiters(txt, "Site Name:", "<")),
            siteId   = Text.Trim(Text.BetweenDelimiters(txt, "Site ID:",  "<")),
            repDate  = Text.Trim(Text.BetweenDelimiters(txt, "Date:",     "<")),
            repTime  = Text.Trim(Text.BetweenDelimiters(txt, "Time:",     "<")),
            reportTS = try DateTime.FromText(repDate & " " & repTime,
                           [Format = "yyyy-MM-dd HH:mm:ss", Culture = "en-US"]) otherwise null,

            // -- ALARMS: everything between the "ALARMS:" and next "<h4>" heading --
            alarmHtml  = Text.BetweenDelimiters(txt, "ALARMS: </h4>", "<h4>"),
            alarmRows  = RowsFromHtml(alarmHtml),
            alarmClean = List.Select(alarmRows, (r) =>
                            List.Count(r) >= 5 and Text.StartsWith(r{0}, "20")),  // date-led rows only
            alarmTbl   = Table.FromRows(
                            List.Transform(alarmClean, (r) => {
                                try DateTime.FromText(r{0},
                                    [Format = "yyyy-MM-dd HH:mm:ss", Culture = "en-US"]) otherwise null,
                                r{1}, r{2}, r{3}, r{4} }),
                            {"timestamp", "channel", "description", "severity", "state"}),

            // -- TELEMETRY: SYSTEM + MODBUS reading tables --
            sysHtml = Text.BetweenDelimiters(txt, "CURRENT SYSTEM READING: </h4>", "<h4>"),
            modHtml = Text.AfterDelimiter(txt, "CURRENT MODBUS READING: </h4>"),

            //  each reading <tr> = 3 side-by-side blocks:
            //    analog  = cells 0..5  (ch, label, threshold, status, _, live-value)
            //    digital = cells 6..10 (ch, label, status, _, H/L state)
            //    relay   = cells 11..13 (ignored here; add later if wanted)
            TeleFrom = (html as text, src as text) as list =>
                let
                    rws = RowsFromHtml(html),
                    ana = List.Transform(rws, (r) =>
                            if List.Count(r) >= 6 and r{0} <> "" and r{1} <> "" and r{3} <> "NO CONFIG"
                            then { src, "Analog",  r{0}, r{1}, r{5}, r{3} } else null),
                    dig = List.Transform(rws, (r) =>
                            if List.Count(r) >= 11 and r{6} <> "" and r{7} <> ""
                            then { src, "Digital", r{6}, r{7}, r{10}, r{8} } else null),
                    keep = List.Select(ana & dig, (x) => x <> null)
                in
                    keep,
            teleRows = TeleFrom(sysHtml, "System") & TeleFrom(modHtml, "Modbus"),
            teleTbl  = Table.FromRows(teleRows,
                          {"source", "kind", "channel", "label", "value", "status"}),

            // -- stamp both tables with file-level metadata --
            addMeta = (t as table) as table =>
                let
                    a = Table.AddColumn(t, "site",        each siteName, type text),
                    b = Table.AddColumn(a, "site_id",     each siteId,   type text),
                    c = Table.AddColumn(b, "report_time", each reportTS, type datetime),
                    d = Table.AddColumn(c, "source_file", each fileName, type text)
                in d
        in
            [ Alarms = addMeta(alarmTbl), Telemetry = addMeta(teleTbl) ],

    //------------------------------------------------------------------------
    // 5. APPLY to every file, then combine
    //------------------------------------------------------------------------
    Parsed       = Table.AddColumn(Files, "R", each ParseOne([Content], [Name])),
    AlarmsAll    = Table.Combine(List.Transform(Parsed[R], each _[Alarms])),
    TelemetryAll = Table.Combine(List.Transform(Parsed[R], each _[Telemetry])),

    // light typing on the combined outputs
    AlarmsTyped = Table.TransformColumnTypes(AlarmsAll, {
                    {"timestamp", type datetime}, {"channel", type text},
                    {"description", type text}, {"severity", type text}, {"state", type text}}),
    TeleTyped   = Table.TransformColumnTypes(TelemetryAll, {
                    {"source", type text}, {"kind", type text}, {"channel", type text},
                    {"label", type text}, {"value", type text}, {"status", type text}})
in
    [ Alarms = AlarmsTyped, Telemetry = TeleTyped ]
