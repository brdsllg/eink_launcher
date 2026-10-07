/// The standard 30-day Tehillim (Psalms) division.
///
/// Mirrors `TEHILLIM_DAILY` in `tanach/work/build.py`. Days 25/26 split
/// Psalm 119 at verse 97; every other day covers whole chapters.
class TehillimDaily {
  /// Day number (1-based) → first chapter.
  static const List<List<int>> dayChapters = [
    [1, 2, 3, 4, 5, 6, 7, 8, 9], // Day 1: 1-9
    [10, 11, 12, 13, 14, 15, 16, 17], // Day 2: 10-17
    [18, 19, 20, 21, 22], // Day 3: 18-22
    [23, 24, 25, 26, 27, 28], // Day 4: 23-28
    [29, 30, 31, 32, 33, 34], // Day 5: 29-34
    [35, 36, 37, 38], // Day 6: 35-38
    [39, 40, 41, 42, 43], // Day 7: 39-43
    [44, 45, 46, 47, 48], // Day 8: 44-48
    [49, 50, 51, 52, 53, 54], // Day 9: 49-54
    [55, 56, 57, 58, 59], // Day 10: 55-59
    [60, 61, 62, 63, 64, 65], // Day 11: 60-65
    [66, 67, 68], // Day 12: 66-68
    [69, 70, 71], // Day 13: 69-71
    [72, 73, 74, 75, 76], // Day 14: 72-76
    [77, 78], // Day 15: 77-78
    [79, 80, 81, 82], // Day 16: 79-82
    [83, 84, 85, 86, 87], // Day 17: 83-87
    [88, 89], // Day 18: 88-89
    [90, 91, 92, 93, 94, 95, 96], // Day 19: 90-96
    [97, 98, 99, 100, 101, 102, 103], // Day 20: 97-103
    [104, 105], // Day 21: 104-105
    [106, 107], // Day 22: 106-107
    [108, 109, 110, 111, 112], // Day 23: 108-112
    [113, 114, 115, 116, 117, 118], // Day 24: 113-118
    [119], // Day 25: 119:1-96
    [119], // Day 26: 119:97-176
    [120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134], // Day 27: 120-134
    [135, 136, 137, 138, 139], // Day 28: 135-139
    [140, 141, 142, 143, 144], // Day 29: 140-144
    [145, 146, 147, 148, 149, 150], // Day 30: 145-150
  ];

  /// First verse of each day as (chapter, verse). Index 0 == Day 1.
  static const List<List<int>> dayStarts = [
    [1, 1],
    [10, 1],
    [18, 1],
    [23, 1],
    [29, 1],
    [35, 1],
    [39, 1],
    [44, 1],
    [49, 1],
    [55, 1],
    [60, 1],
    [66, 1],
    [69, 1],
    [72, 1],
    [77, 1],
    [79, 1],
    [83, 1],
    [88, 1],
    [90, 1],
    [97, 1],
    [104, 1],
    [106, 1],
    [108, 1],
    [113, 1],
    [119, 1],
    [119, 97],
    [120, 1],
    [135, 1],
    [140, 1],
    [145, 1],
  ];

  /// English parent labels: "Day 1" … "Day 30".
  static List<String> get dayNamesEn =>
      List<String>.generate(30, (i) => 'Day ${i + 1}');

  /// Hebrew parent labels: "יום א׳" … "יום ל׳".
  static const List<String> dayNamesHe = [
    'יום א׳',
    'יום ב׳',
    'יום ג׳',
    'יום ד׳',
    'יום ה׳',
    'יום ו׳',
    'יום ז׳',
    'יום ח׳',
    'יום ט׳',
    'יום י׳',
    'יום י״א',
    'יום י״ב',
    'יום י״ג',
    'יום י״ד',
    'יום ט״ו',
    'יום ט״ז',
    'יום י״ז',
    'יום י״ח',
    'יום י״ט',
    'יום כ׳',
    'יום כ״א',
    'יום כ״ב',
    'יום כ״ג',
    'יום כ״ד',
    'יום כ״ה',
    'יום כ״ו',
    'יום כ״ז',
    'יום כ״ח',
    'יום כ״ט',
    'יום ל׳',
  ];

  /// Transliterated "Yom X" names for documentation / builder parity:
  /// Yom Aleph … Yom Shloshim.
  static const List<String> dayNamesTransliterated = [
    'Yom Aleph',
    'Yom Bet',
    'Yom Gimel',
    'Yom Dalet',
    'Yom He',
    'Yom Vav',
    'Yom Zayin',
    'Yom Chet',
    'Yom Tet',
    'Yom Yud',
    'Yom Yud-Aleph',
    'Yom Yud-Bet',
    'Yom Yud-Gimel',
    'Yom Yud-Dalet',
    'Yom Tet-Vav',
    'Yom Tet-Zayin',
    'Yom Yud-Zayin',
    'Yom Yud-Chet',
    'Yom Yud-Tet',
    'Yom Kaf',
    'Yom Kaf-Aleph',
    'Yom Kaf-Bet',
    'Yom Kaf-Gimel',
    'Yom Kaf-Dalet',
    'Yom Kaf-He',
    'Yom Kaf-Vav',
    'Yom Kaf-Zayin',
    'Yom Kaf-Chet',
    'Yom Kaf-Tet',
    'Yom Shloshim',
  ];
}
