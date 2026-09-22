import re
import sqlite3

from build import ROOT, strip_trop


connection = sqlite3.connect(ROOT / "work/tanach.sqlite")
rows = connection.execute(
    "SELECT book, chapter, verse, original FROM verses "
    "WHERE original LIKE '%[%' ORDER BY book, chapter, verse"
).fetchall()
pattern = (
    r"(?<![\u05b0-\u05bd\u05bf\u05c1\u05c2\u05c7\u05d0-\u05ea])"
    r"([\u05d0-\u05ea]+(?: [\u05d0-\u05ea]+)*)\s+\[([^\[\]]+)\]"
)
residual = []
matches = 0
for book, chapter, verse, original in rows:
    replaced, count = re.subn(pattern, "§Q§", strip_trop(original))
    matches += count
    if "[" in replaced:
        residual.append((book, chapter, verse, original, count))

print("bracket verses", len(rows))
print("pair matches", matches)
print("residual verses", len(residual))
for book, chapter, verse, original, count in residual:
    print(f"{book} {chapter}:{verse} | matches={count} | {original}")
