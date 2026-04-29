# Daily Word Recall Service Design

## Goal

Build a Rails service that returns the `Word` records a learner needs to remember on a given calendar day.

The service uses existing recall records to decide whether a word is due. Only correct recalls advance the schedule. Incorrect recalls are kept for stats, but they do not delay, reset, or complete a word's recall schedule.

## Public API

Add a plain service object:

```ruby
WordsDueForRecall.call(day: Date.current)
```

The service returns words due on the given calendar day. The initial implementation can return an array of `Word` records because each word's due state depends on aggregate recall history.

Add a pure helper predicate on the service:

```ruby
WordsDueForRecall.due?(
  word:,
  last_correct_record:,
  remember_times:,
  day:
)
```

The helper accepts a word, the latest correct recall record for that word, the count of correct recalls, and the calendar day being checked. It returns `true` when the word should appear that day.

## Recall Schedule

Use calendar dates, not exact 24-hour intervals.

The schedule intervals are:

```ruby
[0, 2, 3, 5, 7, 15]
```

Rules:

- `0` correct recalls: due on or after the word's created date.
- `1` correct recall: due 2 days after the latest correct recall.
- `2` correct recalls: due 3 days after the latest correct recall.
- `3` correct recalls: due 5 days after the latest correct recall.
- `4` correct recalls: due 7 days after the latest correct recall.
- `5` correct recalls: due 15 days after the latest correct recall.
- `6+` correct recalls: the word is complete and no longer appears.

If a word is due and the learner answers incorrectly, the word remains due until a later correct recall record exists. The next interval is always counted from the latest correct recall date, not from incorrect attempts.

## Data Flow

For each word:

1. Find correct `WordQuestionRecord` rows through the word's `WordQuestion` records.
2. Count those correct records as `remember_times`.
3. Find the latest correct record as `last_correct_record`.
4. Ask the helper whether the word is due for the requested day.

When there are no correct recall records, the base date is `word.created_at.to_date`.

When there is at least one correct recall record, the base date is `last_correct_record.created_at.to_date`.

The word is due when:

```ruby
day >= base_date + interval.days
```

The word is not due when `remember_times` is greater than or equal to the schedule length.

## Error Handling

The service expects `day` to behave like a `Date`. Callers should pass `Date.current` or a concrete `Date` in tests. The service does not need special handling for words without questions; they can still be due based on `created_at` when they have no correct records.

## Testing

Add service tests for:

- A newly created word is due on its created date.
- A new word is not due before its created date.
- A word with one correct recall is due after 2 calendar days.
- A word with one correct recall is not due before 2 calendar days.
- Incorrect recalls do not advance or postpone the schedule.
- An overdue word keeps appearing until a later correct recall exists.
- After the sixth correct recall, the word stops appearing.
- The helper can be tested directly with a word, last correct record, remember count, and day.
