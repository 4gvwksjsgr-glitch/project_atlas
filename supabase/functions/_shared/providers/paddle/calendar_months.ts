/**
 * Deterministic UTC calendar-month arithmetic for Paddle next_billed_at.
 *
 * Single-step from the original instant: the target month is computed once
 * and the day is clamped to the last day of that month. UTC time-of-day
 * (hours, minutes, seconds, milliseconds) is preserved.
 */

function lastDayOfMonthUtc(year: number, monthIndex: number): number {
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}

export function addCalendarMonthsUtc(
  isoOrDate: string | Date,
  months: number,
): string {
  if (!Number.isInteger(months)) {
    throw new RangeError("months must be an integer");
  }

  const source = isoOrDate instanceof Date
    ? new Date(isoOrDate.getTime())
    : new Date(isoOrDate);
  if (Number.isNaN(source.getTime())) {
    throw new RangeError("invalid date");
  }

  const totalMonths = source.getUTCFullYear() * 12 + source.getUTCMonth() +
    months;
  const targetYear = Math.floor(totalMonths / 12);
  const targetMonth = totalMonths - targetYear * 12;
  const day = Math.min(
    source.getUTCDate(),
    lastDayOfMonthUtc(targetYear, targetMonth),
  );

  const result = new Date(0);
  result.setUTCFullYear(targetYear, targetMonth, day);
  result.setUTCHours(
    source.getUTCHours(),
    source.getUTCMinutes(),
    source.getUTCSeconds(),
    source.getUTCMilliseconds(),
  );
  if (Number.isNaN(result.getTime())) {
    throw new RangeError("result out of range");
  }
  return result.toISOString();
}
