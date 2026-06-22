import {AmenDailyHolidayContext} from "./amenDailyTypes";

export function resolveGeneralHoliday(dateKey: string): AmenDailyHolidayContext | undefined {
  const [year, month, day] = dateKey.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  const weekday = date.getUTCDay();

  if (month === 1 && day === 1) return general("New Year's Day", "New mercies", "Begin the year with gratitude and steady hope.", "Lamentations 3:22-23", "Lamentations 3", dateKey);
  if (month === 1 && weekday === 1 && day >= 15 && day <= 21) return general("Martin Luther King Jr. Day", "Walk in love", "Consider one act of justice, mercy, or reconciliation today.", "Micah 6:8", "Micah 6", dateKey);
  if (month === 2 && day === 14) return general("Valentine's Day", "Love one another", "Let love today be patient, truthful, and practical.", "1 Corinthians 13:4", "1 Corinthians 13", dateKey);
  if (month === 5 && weekday === 0 && day >= 8 && day <= 14) return general("Mother's Day", "Happy Mother's Day", "Take a moment to honor, remember, or pray for mothers and mother figures.", "Proverbs 31:28", "Proverbs 31", dateKey);
  if (month === 5 && weekday === 1 && day >= 25) return general("Memorial Day", "Remember with honor", "Pause with gratitude for sacrifice and pray for those who grieve.", "John 15:13", "John 15", dateKey);
  if (month === 6 && weekday === 0 && day >= 15 && day <= 21) return general("Father's Day", "Happy Father's Day", "Pray for fathers, father figures, and those carrying complicated stories today.", "Psalm 103:13", "Psalm 103", dateKey);
  if (month === 7 && day === 4) return general("Independence Day", "Freedom with wisdom", "Give thanks for freedom and seek peace with your neighbors.", "Galatians 5:13", "Galatians 5", dateKey);
  if (month === 9 && weekday === 1 && day <= 7) return general("Labor Day", "Work with peace", "Let today hold rest, gratitude, and humane rhythms around work.", "Colossians 3:23", "Colossians 3", dateKey);
  if (month === 11 && day === 11) return general("Veterans Day", "Honor and peace", "Give thanks for service and pray for healing, peace, and protection.", "Psalm 46:1", "Psalm 46", dateKey);
  if (month === 11 && weekday === 4 && day >= 22 && day <= 28) return general("Thanksgiving", "Give thanks", "Name one mercy before the day gets full.", "Psalm 107:1", "Psalm 107", dateKey);
  if (month === 12 && day === 24) return general("Christmas Eve", "Christ is near", "Make room for quiet anticipation and peace tonight.", "Luke 2:10", "Luke 2", dateKey);
  if (month === 12 && day === 25) return general("Christmas Day", "Merry Christmas", "Today's focus: presence, peace, and the gift of Christ.", "Luke 2:11", "Luke 2", dateKey);
  if (month === 12 && day === 31) return general("New Year's Eve", "Look back with grace", "Close the year with gratitude, confession, and hope.", "Psalm 90:12", "Psalm 90", dateKey);

  return undefined;
}

function general(
  name: string,
  title: string,
  message: string,
  verse: string,
  passageReference: string,
  dateKey: string,
): AmenDailyHolidayContext {
  return {name, type: "general", message, suggestedVerseReference: verse, dateKey, title, passageReference};
}
