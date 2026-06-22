import {AmenDailyHolidayContext} from "./amenDailyTypes";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

export function resolveChristianCalendar(dateKey: string): AmenDailyHolidayContext | undefined {
  const date = parseDateKey(dateKey);
  const easter = calculateEasterSunday(date.getUTCFullYear());
  const diff = Math.round((date.getTime() - easter.getTime()) / MS_PER_DAY);
  const month = date.getUTCMonth() + 1;
  const day = date.getUTCDate();

  if (diff === 0) {
    return christian("Easter", "He is risen", "Today is a day of resurrection, renewal, and hope.", "Luke 24:6", "Luke 24", dateKey);
  }
  if (diff === -2) {
    return christian("Good Friday", "At the cross", "Today invites quiet reflection on the love and sacrifice of Christ.", "Isaiah 53:5", "John 19", dateKey);
  }
  if (diff === -7) {
    return christian("Palm Sunday", "Hosanna", "Holy Week begins with the King who comes in humility and peace.", "Matthew 21:9", "Matthew 21", dateKey);
  }
  if (diff >= -6 && diff <= -1) {
    return christian("Holy Week", "Holy Week", "Move through this week with attention to Christ's humility, suffering, and love.", "Philippians 2:8", "John 13", dateKey);
  }
  if (diff >= -46 && diff <= -8) {
    return christian("Lent", "Lent", "This season invites repentance, simplicity, and renewed attention to Christ.", "Joel 2:13", "Matthew 6", dateKey, "season");
  }
  if (diff === 49) {
    return christian("Pentecost", "Come, Holy Spirit", "Today remembers the Spirit's power and the church sent into the world.", "Acts 2:4", "Acts 2", dateKey);
  }
  if (month === 12 && day >= 1 && day <= 24) {
    return christian("Advent", "Advent", "This season turns our attention toward hope, waiting, and the coming of Christ.", "Isaiah 9:6", "Luke 1", dateKey, "season");
  }
  if (month === 12 && day === 25) {
    return christian("Christmas", "Merry Christmas", "Today's focus: presence, peace, and the gift of Christ.", "Luke 2:11", "Luke 2", dateKey);
  }
  if ((month === 12 && day >= 26) || (month === 1 && day <= 5)) {
    return christian("Christmas", "Christmas", "Continue in the wonder of Christ with us, full of grace and truth.", "John 1:14", "John 1", dateKey, "season");
  }
  return undefined;
}

export function calculateEasterSunday(year: number): Date {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(Date.UTC(year, month - 1, day));
}

function christian(
  name: string,
  title: string,
  message: string,
  verse: string,
  passageReference: string,
  dateKey: string,
  type: "christian" | "season" = "christian",
): AmenDailyHolidayContext {
  return {name, type, message, suggestedVerseReference: verse, dateKey, title, passageReference};
}

function parseDateKey(dateKey: string): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}
