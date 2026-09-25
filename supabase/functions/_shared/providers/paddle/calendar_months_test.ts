import { assertEquals, assertThrows } from "@std/assert";
import { addCalendarMonthsUtc } from "./calendar_months.ts";

const CASES: Array<[string, number, string]> = [
  ["2026-01-31T10:00:00.000Z", 1, "2026-02-28T10:00:00.000Z"],
  ["2028-01-31T10:00:00.000Z", 1, "2028-02-29T10:00:00.000Z"],
  ["2026-03-31T10:00:00.000Z", 1, "2026-04-30T10:00:00.000Z"],
  ["2026-08-31T10:00:00.000Z", 1, "2026-09-30T10:00:00.000Z"],
  ["2026-12-31T10:00:00.000Z", 1, "2027-01-31T10:00:00.000Z"],
  ["2026-01-31T10:00:00.000Z", 2, "2026-03-31T10:00:00.000Z"],
  ["2026-10-15T10:00:00.000Z", 3, "2027-01-15T10:00:00.000Z"],
];

for (const [input, months, expected] of CASES) {
  Deno.test(`addCalendarMonthsUtc ${input} +${months} => ${expected}`, () => {
    assertEquals(addCalendarMonthsUtc(input, months), expected);
    assertEquals(addCalendarMonthsUtc(new Date(input), months), expected);
  });
}

Deno.test("addCalendarMonthsUtc preserves UTC time-of-day and ms", () => {
  assertEquals(
    addCalendarMonthsUtc("2026-05-31T23:59:58.123Z", 1),
    "2026-06-30T23:59:58.123Z",
  );
});

Deno.test("addCalendarMonthsUtc normalizes offset input to UTC", () => {
  // 2026-01-31T23:30:00-02:00 == 2026-02-01T01:30:00Z
  assertEquals(
    addCalendarMonthsUtc("2026-01-31T23:30:00-02:00", 1),
    "2026-03-01T01:30:00.000Z",
  );
});

Deno.test("addCalendarMonthsUtc supports zero and negative months", () => {
  assertEquals(
    addCalendarMonthsUtc("2026-03-31T10:00:00.000Z", 0),
    "2026-03-31T10:00:00.000Z",
  );
  assertEquals(
    addCalendarMonthsUtc("2026-03-31T10:00:00.000Z", -1),
    "2026-02-28T10:00:00.000Z",
  );
});

Deno.test("addCalendarMonthsUtc rejects invalid input", () => {
  assertThrows(() => addCalendarMonthsUtc("not-a-date", 1), RangeError);
  assertThrows(
    () => addCalendarMonthsUtc("2026-01-31T10:00:00.000Z", 1.5),
    RangeError,
  );
});
