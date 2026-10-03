"""
Generate fictional Davicom MAC alarm reports for testing the dashboard.

Produces HTML files in the same structure a Davicom MAC unit exports
(header, ALARMS, DISABLED INPUTS, CURRENT SYSTEM READING, CURRENT MODBUS
READING), so the Power Query parser runs on them unchanged.

All site names, call signs, and readings are made up.

Usage:
    python generate_reports.py                    # 14 days, writes to ./reports
    python generate_reports.py --days 30 --out my_reports
    python generate_reports.py --max-events 2     # allow 2 silence events per report
"""

import argparse
import random
from datetime import datetime, timedelta
from pathlib import Path

SITE_NAME = "Demo Radio Site"
SITE_ID = "1"
STATIONS = ["CXRA", "CXRB", "CXRC", "CXRD"]  # fictional call signs

# Air Feed alarm channel for each station
AIR_FEED_CHANNEL = {"CXRA": "1D1", "CXRB": "1D9", "CXRC": "1MD1", "CXRD": "1MD9"}

STYLE = (
    "table.tabheader { width: 100%; border-style: none; } "
    "td { font-size: 9pt; font-family: Arial, Helvetica, sans-serif; color: #333333 } "
    "table.tabheader td { font-weight: bold; } "
    "h1 { font-size: 13pt; font-weight: bold; color: #4465A2; text-align: center } "
    "table.tabvis { width: 80%; border: 1px #6699CC solid; border-collapse: collapse; } "
    "table.tabvis th { background-color: #4465A2; color: white; } "
    "h4 { font-size: 9pt; font-weight: bold; color: #333333; } "
)

READING_HEADER = (
    "<tr><th>#</th><th>METERING INPUTS DESCRIPTION</th><th>NORMAL VALUE</th>"
    "<th>CURRENT STATE</th><th>QLF</th><th>CURRENT VALUE</th><th>#</th>"
    "<th>STATUS INPUTS DESCRIPTION</th><th>CURRENT STATE</th><th>QLF</th>"
    "<th>CURRENT VALUE</th><th>#</th><th>PHYSICAL RELAYS DESCRIPTION</th>"
    "<th>CURRENT STATE</th></tr>"
)

GREY = '<td style="background-color: rgb(240, 240, 240);"><br/></td>'


def td(text):
    return f"<td>{text}<br/></td>"


def td_plain(text):
    return f"<td>{text}</td>"


def analog_cells(ch, label, normal, state, value):
    return td(ch) + td(label) + td_plain(normal) + td(state) + td("") + td_plain(value)


def digital_cells(ch, label, state, hl):
    return td(ch) + td(label) + td(state) + td("") + td(hl)


def relay_cells(ch, label, state):
    return td(ch) + td(label) + td_plain(state)


def station_digitals(station, prefix, start):
    """Seven status points per station, in the order the unit reports them."""
    points = [
        ("Air Feed OK", "H"), ("Pgm Ok", "H"), ("MTS OK", "H"),
        ("Pgm A on Air", "L"), ("MTS not on Air", "H"),
        ("CD not on Air", "H"), ("EAS not on Air", "H"),
    ]
    return [(f"{prefix}{start + i}", f"{station} {name}", "NORMAL", hl)
            for i, (name, hl) in enumerate(points)]


def reading_table(analog, digital, relays):
    rows = []
    for i, dig in enumerate(digital):
        a = analog[i] if i < len(analog) else None
        r = relays[i] if i < len(relays) else None
        rows.append(
            "<tr>"
            + (analog_cells(*a) if a else GREY * 6)
            + digital_cells(*dig)
            + (relay_cells(*r) if r else GREY * 3)
            + "</tr>"
        )
    return ('<table class="tabvis" style="text-align: left; width: 100%;"><tbody>'
            + READING_HEADER + "".join(rows) + "</tbody></table>")


def build_report(report_time, alarms, on_generator):
    rnd = random.Random(report_time.timestamp())

    # ---------- analog readings ----------
    sys_analog = [
        ("1A1", "STL 1 Fwd Pwr", "1W", "NORMAL", f"{rnd.uniform(76.5, 79.5):.4f}W"),
        ("1A2", "STL 2 Fwd Pwr", "0W", "DISABLE", "0W"),
        ("1A3", "450M STL Fwd Pwr", "0W", "NORMAL", f"{rnd.uniform(16.5, 17.8):.4f}W"),
        ("1A4", "450M STL Rfld Pwr", "0", "NORMAL", f"{rnd.uniform(0.8, 1.6):.4f}"),
        ("1A5", " ", "0F", "DISABLE", "0F"),
        ("1A6", "Equipment Room Humidity", "0%", "DISABLE", "0%"),
        ("1A7", "TSR Temp OK", "0F", "NORMAL", f"{rnd.uniform(80.5, 86.0):.4f}F"),
        ("1A8", "TSR Humidity OK", "0%", "NORMAL", f"{rnd.uniform(24.0, 38.0):.4f}%"),
    ]
    mod_analog = [
        ("1MA1", "AC Phase 1", "208Vac", "NORMAL", f"{rnd.uniform(206.5, 211.5):.3f}Vac"),
        ("1MA2", "AC Phase 2", "208Vac", "NORMAL", f"{rnd.uniform(206.5, 211.5):.3f}Vac"),
        ("1MA3", "AC Phase 3", "208Vac", "NORMAL", f"{rnd.uniform(206.5, 211.5):.3f}Vac"),
    ] + [(f"1MA{i}", " ", "0", "NO CONFIG", "0") for i in range(4, 25)]

    # ---------- digital (status) points ----------
    sys_digital = (
        station_digitals("CXRA", "1D", 1)
        + [("1D8", "On Hydro", "NORMAL", "H" if on_generator else "L")]
        + station_digitals("CXRB", "1D", 9)
        + [("1D16", "Not On Generator", "ACT", "L" if on_generator else "H")]
    )
    mod_digital = (
        station_digitals("CXRC", "1MD", 1)
        + [("1MD8", "CXRC Comrex Connected", "NORMAL", "L")]
        + station_digitals("CXRD", "1MD", 9)
        + [("1MD16", "CXRD Comrex Connected", "NORMAL", "L"),
           ("1MD17", "PTP - GPS Sync Ok", "NORMAL", "L"),
           ("1MD18", "PTP  Clock -  Lock Ok", "NORMAL", "L"),
           ("1MD19", "PTP  Clock -  AC PS Ok", "NORMAL", "L"),
           ("1MD20", "PTP  Clock -  DC PS Fail", "ACT", "H"),
           ("1MD21", "Generator Idle", "NORMAL", "L" if on_generator else "H"),
           ("1MD22", "Generator OK", "NORMAL", "H"),
           ("1MD23", "Generator Auto", "NORMAL", "H"),
           ("1MD24", "Generator Battery OK", "NORMAL", "H")]
    )

    # ---------- relays ----------
    sys_relays = [
        ("1R1", "~Sel CXRA Pgm A-Air", "Not Controlled"),
        ("1R2", "~Sel CXRA MTS-Air", "Not Controlled"),
        ("1R3", "~Sel CXRA CD-Air", "Not Controlled"),
        ("1R4", "~i-CXRA Audio OK", "Controlled"),
        ("1R5", " ", "Not Controlled"),
        ("1R6", "~BDT Start", "Pulse"),
        ("1R7", "~BDT Stop", "Pulse"),
        ("1R8", "~BDT Failsafe", "Not Controlled"),
    ]
    mod_relays = [(f"1MR{i}", " ", "Not Controlled") for i in range(1, 24)] + [
        ("1MR24", "~Generator Run", "Controlled")]

    alarm_rows = "".join(
        "<tr>" + td(ts.strftime("%Y-%m-%d %H:%M:%S")) + td(ch) + td(desc) + td(sev) + td(hl) + "</tr>"
        for ts, ch, desc, sev, hl in alarms
    )
    disabled = "".join(
        "<tr>" + td(ch) + td(label) + "</tr>"
        for ch, label in [("1A2", "STL 2 Fwd Pwr"), ("1A5", " "), ("1A6", "Equipment Room Humidity"),
                          ("1N1", "ping ok"), ("1SG43", "OS HDD Capacity"), ("1SG44", "OS HDD Used")]
    )
    small_table = ('<table cellpadding="4" cellspacing="2" border="0" '
                   'style="text-align: left; width: 60%;"><tbody>')

    return f"""<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<title>DAVICOM System</title>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<style type="text/css">{STYLE}</style>
</head>
<body>
<table class="tabheader"><tbody>
<tr><td align="left">Site Name: {SITE_NAME}<br/></td><td align="right">Time: {report_time:%H:%M:%S}<br/></td></tr>
<tr><td align="left">Site ID: {SITE_ID}<br/></td><td align="right">Date: {report_time:%Y-%m-%d}<br/></td></tr>
</tbody></table>
<table class="tabheader"><tbody><tr><td align="center">SAMPLE DATA - FICTIONAL SITE</td></tr></tbody></table>
<h1>ALARM REPORT</h1>
<h4>ALARMS: </h4>
{small_table}{alarm_rows}</tbody></table>
<h4>ALARMS STATUS: </h4>
<h4>DISABLED INPUTS: </h4>
{small_table}{disabled}</tbody></table>
<h4>CURRENT SYSTEM READING: </h4>
{reading_table(sys_analog, sys_digital, sys_relays)}
<h4>CURRENT MODBUS READING: </h4>
{reading_table(mod_analog, mod_digital, mod_relays)}
</body>
</html>
"""


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--days", type=int, default=14)
    p.add_argument("--start", default="2026-01-05")
    p.add_argument("--out", default="reports")
    p.add_argument("--max-events", type=int, default=1,
                   help="max silence events per report (default 1)")
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    random.seed(args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    start = datetime.strptime(args.start, "%Y-%m-%d")
    generator_test_day = args.days // 2  # one simulated generator test mid-period

    count = 0
    for day in range(args.days):
        for hour in (8, 20):  # twice-daily scheduled reports
            report_time = start + timedelta(days=day, hours=hour, minutes=1, seconds=57)
            alarms = []
            if random.random() < 0.45:  # some reports contain silence events
                for _ in range(random.randint(1, args.max_events)):
                    station = random.choice(STATIONS)
                    ch = AIR_FEED_CHANNEL[station]
                    began = report_time - timedelta(minutes=random.randint(2, 50),
                                                    seconds=random.randint(0, 59))
                    cleared = began + timedelta(seconds=random.randint(3, 45))
                    alarms += [
                        (began, ch, f"{station} Air Feed Silence", "MINOR2", "L"),
                        (cleared, ch, f"{station} Air Feed OK", "NORMAL", "H"),
                    ]
                alarms.sort()
            on_generator = (day == generator_test_day and hour == 8)
            html = build_report(report_time, alarms, on_generator)
            name = f"almMAC_{report_time:%Y-%m-%d_%H-%M-%S}.html"
            (out / name).write_text(html, encoding="utf-8")
            count += 1
    print(f"Wrote {count} reports to {out.resolve()}")


if __name__ == "__main__":
    main()
