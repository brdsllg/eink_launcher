"""Derive the fixed Torah parsha/aliyah table from Hebcal's published leyning data.

The 54 parshiyot and their seven aliyah boundaries are halachically fixed, so the
EPUB build must not depend on the network. This script reads that data once from
the public Hebcal leyning API and rewrites the generated PARSHIYOT block inside
build.py, which keeps the build itself offline and deterministic.

Aliyot are taken from weeks where a parsha is read on its own, because a
combined reading (for example Vayakhel-Pekudei) redistributes the boundaries.

Run from this folder:  python -X utf8 derive_parshiyot.py
"""

import argparse, collections, json, re, sqlite3, sys, time, urllib.request

from sync import ROOT

START_MARK = '# ─── Parasha / aliyah data (generated) ─────────────────────────────────────'
BEGIN = '# >>> PARSHIYOT_DATA'
END = '# <<< PARSHIYOT_DATA'
API = 'https://www.hebcal.com/leyning?cfg=json&i=on&start={start}&end={end}'
FIRST_YEAR = 2018
LAST_YEAR = 2032
CACHE = ROOT / 'work/cache/leyning'

# Hebcal writes a few names without the apostrophe.
NAME_OVERRIDES = {'Vaera': "Va'era"}
# Vezot Habracha is read on Simchat Torah, never on an ordinary Shabbat.
VEZOT_NAME = 'Vezot Habracha'
VEZOT_HE = 'וְזֹאת הַבְּרָכָה'

BOOK_NAMES = ('Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy')
BOOK_COUNTS = {
    'Genesis': 12,
    'Exodus': 11,
    'Leviticus': 10,
    'Numbers': 10,
    'Deuteronomy': 11,
}
ALIYOT = tuple('1234567')


def fetch(start, end):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f'{start}_{end}.json'
    if path.exists():
        return json.loads(path.read_text(encoding='utf-8'))
    request = urllib.request.Request(
        API.format(start=start, end=end),
        headers={'User-Agent': 'eink-launcher-tanach/1.0'},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.loads(response.read().decode('utf-8'))
    path.write_text(json.dumps(payload), encoding='utf-8')
    return payload


def windows():
    for year in range(FIRST_YEAR, LAST_YEAR + 1):
        for month in (1, 7):
            last = f'{year}-06-30' if month == 1 else f'{year}-12-31'
            yield f'{year}-{month:02d}-01', last


def strip_trop(text):
    return re.sub(r'[\u0591-\u05af]', '', text)


def _reading(kriyah, book):
    """Return (aliyot, end) when the seven aliyot are one clean, in-book reading."""
    if any(key not in kriyah for key in ALIYOT):
        return None
    if any(kriyah[key].get('k') != book for key in ALIYOT):
        return None  # A holiday or Rosh Chodesh reading displaced an aliyah.
    aliyot = []
    for key in ALIYOT:
        chapter, verse = (int(x) for x in kriyah[key]['b'].split(':'))
        aliyot.append((chapter, verse))
    if aliyot != sorted(aliyot) or len(set(aliyot)) != len(aliyot):
        return None
    if not kriyah['7'].get('e'):
        return None
    end = tuple(int(x) for x in kriyah['7']['e'].split(':'))
    if end < aliyot[-1]:
        return None
    return aliyot, end


def collect():
    """Return ({parsha name: reading}, conflicts, hebrew names)."""
    readings = {}
    conflicts = []
    hebrew_names = {}

    def add(name, he, record):
        hebrew_names[name] = he
        previous = readings.get(name)
        if previous is not None and previous != record:
            conflicts.append((name, previous, record))
        else:
            readings[name] = record

    for start, end in windows():
        payload = fetch(start, end)
        time.sleep(0.05)
        for item in payload.get('items', []):
            name = (item.get('name') or {}).get('en')
            he = strip_trop((item.get('name') or {}).get('he') or '')
            if not name:
                continue
            if isinstance(item.get('parshaNum'), list):
                continue  # A combined reading redistributes the aliyot.
            kriyah = item.get('fullkriyah')
            if not isinstance(kriyah, dict) or not kriyah:
                if name == VEZOT_NAME:
                    hebrew_names.setdefault(name, he)
                continue
            if item.get('type') == 'shabbat':
                book = (kriyah.get('1') or {}).get('k')
                if book not in BOOK_NAMES:
                    continue
            elif name.startswith('Simchat Torah'):
                # Vezot Habracha is read on Simchat Torah. A weekday reading
                # merges aliyot 6 and 7, so only the Shabbat reading carries
                # the standard seven; aliyah 8 (Bereishit) is dropped here.
                name = VEZOT_NAME
                he = hebrew_names.setdefault(name, VEZOT_HE)
                book = 'Deuteronomy'
                kriyah = {key: kriyah[key] for key in ALIYOT
                          if kriyah.get(key, {}).get('k') == book}
            else:
                continue
            reading = _reading(kriyah, book)
            if reading is None:
                continue
            aliyot, parsha_end = reading
            add(name, he, dict(
                he=he,
                start=aliyot[0],
                end=parsha_end,
                aliyot=aliyot,
                book=book,
            ))
    return readings, conflicts, hebrew_names


def _verse_index(connection):
    """Map (book, chapter, verse) to its position within its book."""
    rows = connection.execute('SELECT book, chapter, verse FROM verses').fetchall()
    order = {}
    for book in BOOK_NAMES:
        verses = sorted((row[1], row[2]) for row in rows if row[0] == book)
        for position, (chapter, verse) in enumerate(verses):
            order[(book, chapter, verse)] = position
    return order


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Report without editing build.py.')
    args = parser.parse_args()

    readings, conflicts, _ = collect()
    if conflicts:
        for name, before, after in conflicts:
            print('Conflicting readings for', name, file=sys.stderr)
            print('  ', before, file=sys.stderr)
            print('  ', after, file=sys.stderr)
        raise SystemExit('Hebcal data disagrees with itself; not writing build.py')

    by_book = collections.OrderedDict((name, []) for name in BOOK_NAMES)
    for name, record in readings.items():
        by_book[record['book']].append(name)

    connection = sqlite3.connect(ROOT / 'work/tanach.sqlite')
    verses = {
        (book, chapter, verse)
        for book, chapter, verse in connection.execute(
            'SELECT book, chapter, verse FROM verses'
        )
    }
    index = _verse_index(connection)

    problems = []
    blocks = []
    for book, names in by_book.items():
        if len(names) != BOOK_COUNTS[book]:
            problems.append(f'{book}: {len(names)} parshiyot, expected {BOOK_COUNTS[book]}')
        records = sorted((readings[name] for name in names), key=lambda r: r['start'])
        # The parshiyot of a book must tile it: from 1:1 to its last verse,
        # each parsha ending exactly where the next one begins.
        if records:
            if records[0]['start'] != (1, 1):
                problems.append(f'{book}: first parsha starts at {records[0]["start"]}')
            last = index.get((book, *records[-1]['end']))
            if last is None or last != sum(1 for v in verses if v[0] == book) - 1:
                problems.append(f'{book}: last parsha ends at {records[-1]["end"]}')
        for before, after in zip(records, records[1:]):
            stop = index.get((book, *before['end']))
            start = index.get((book, *after['start']))
            if stop is None or start is None or stop + 1 != start:
                problems.append(f'{book}: gap or overlap after {before["start"]}')
        entries = []
        for name in names:
            record = readings[name]
            label = NAME_OVERRIDES.get(name, name).replace('-', ' ')
            boundaries = record['aliyot']
            for chapter, verse in boundaries:
                if (book, chapter, verse) not in verses:
                    problems.append(f'{label}: {book} {chapter}:{verse} is not a verse start')
            if boundaries[0] != record['start']:
                problems.append(f'{label}: first aliyah is not the parsha start')
            if boundaries != sorted(boundaries):
                problems.append(f'{label}: aliyot are out of order')
            entries.append(
                "    {'name_he': %r, 'name_en': %r, 'start': %r, 'end': %r,\n"
                "     'aliyot': [%s]},"
                % (
                    record['he'], label, record['start'], record['end'],
                    ', '.join(repr(value) for value in boundaries),
                )
            )
        blocks.append("  '%s': [\n%s\n  ]," % (book, '\n'.join(entries)))
    connection.close()

    if problems:
        for problem in problems:
            print('PROBLEM:', problem, file=sys.stderr)
        raise SystemExit('Refusing to write a table that fails its checks')

    body = '\n'.join(
        [
            START_MARK,
            '# Generated by derive_parshiyot.py from Hebcal leyning data; do not edit by hand.',
            '# Each entry: name_he (with nikud), name_en, start=(chapter,verse),',
            '# end=(chapter,verse), aliyot=the seven reading starts.',
            "TORAH_BOOKS = {'Genesis','Exodus','Leviticus','Numbers','Deuteronomy'}",
            '',
            "ALIYAH_NAMES_HE = {1:'ראשון',2:'שני',3:'שלישי',4:'רביעי',5:'חמישי',6:'שישי',7:'שביעי'}",
            "ALIYAH_NAMES_EN = {1:'First Portion',2:'Second Portion',3:'Third Portion',"
            "4:'Fourth Portion',5:'Fifth Portion',6:'Sixth Portion',7:'Seventh Portion'}",
            '',
            '# Aliyah verse boundaries are the standard annual divisions published by',
            '# Hebcal, taken from the weeks where each parsha is read on its own.',
            BEGIN,
            'PARSHIYOT = {',
            '\n'.join(blocks),
            '}',
            END,
        ]
    )

    total = sum(len(names) for names in by_book.values())
    print(f'{total} parshiyot, {total * 7} aliyot')
    for book, names in by_book.items():
        print(f'  {book}: {len(names)}')
    if args.check:
        return

    path = ROOT / 'work/build.py'
    source = path.read_text(encoding='utf-8')
    if START_MARK not in source or BEGIN not in source or END not in source:
        raise SystemExit('build.py is missing the generated data markers')
    head = source[: source.index(START_MARK)]
    tail = source[source.index(END) + len(END):]
    path.write_text(head + body + tail, encoding='utf-8', newline='')
    print('Updated', path)


if __name__ == '__main__':
    main()
