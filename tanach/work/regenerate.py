import sqlite3
from build import generate,ROOT
c=sqlite3.connect(ROOT/'work/tanach.sqlite');c.row_factory=sqlite3.Row
ed={r['id']:dict(r) for r in c.execute('SELECT * FROM editions')}
generate(c,ed)
