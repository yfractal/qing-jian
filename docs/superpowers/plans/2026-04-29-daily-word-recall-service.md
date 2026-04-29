# Daily Word Recall Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Rails service that returns `Word` records due for recall on a given calendar day.

**Architecture:** Add a plain service object, `WordsDueForRecall`, under `app/services`. The service preloads each word's questions and recall records, counts only correct records, and uses a pure `due?` helper to decide whether each word should appear.

**Tech Stack:** Rails 8.1.3, ActiveRecord, PostgreSQL, Minitest

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/services/words_due_for_recall.rb` | Create | Service object and pure due-date helper |
| `test/services/words_due_for_recall_test.rb` | Create | Unit and integration coverage for recall schedule behavior |

---

## Task 1: Service Test Coverage

**Files:**
- Create: `test/services/words_due_for_recall_test.rb`

- [ ] **Step 1: Create the service test directory**

Run:

```bash
mkdir -p test/services
```

Expected: command exits with status `0`.

- [ ] **Step 2: Write the failing service tests**

Create `test/services/words_due_for_recall_test.rb`:

```ruby
require "test_helper"

class WordsDueForRecallTest < ActiveSupport::TestCase
  def setup
    WordQuestionRecord.delete_all

    @word = words(:cat)
    @question = word_questions(:cat_question)
    @created_on = Date.new(2026, 4, 1)

    set_word_created_on(@word, @created_on)
  end

  test "newly created word is due on its created date" do
    due_words = WordsDueForRecall.call(day: @created_on)

    assert_includes due_words, @word
  end

  test "new word is not due before its created date" do
    due_words = WordsDueForRecall.call(day: @created_on - 1.day)

    assert_not_includes due_words, @word
  end

  test "word with one correct recall is due after two calendar days" do
    create_record!(created_on: @created_on, correct: true)

    due_words = WordsDueForRecall.call(day: @created_on + 2.days)

    assert_includes due_words, @word
  end

  test "word with one correct recall is not due before two calendar days" do
    create_record!(created_on: @created_on, correct: true)

    due_words = WordsDueForRecall.call(day: @created_on + 1.day)

    assert_not_includes due_words, @word
  end

  test "incorrect recalls do not advance or postpone the schedule" do
    create_record!(created_on: @created_on, correct: true)
    create_record!(created_on: @created_on + 2.days, correct: false)

    due_words = WordsDueForRecall.call(day: @created_on + 3.days)

    assert_includes due_words, @word
  end

  test "overdue word keeps appearing until a later correct recall exists" do
    create_record!(created_on: @created_on, correct: true)
    create_record!(created_on: @created_on + 2.days, correct: false)

    assert_includes WordsDueForRecall.call(day: @created_on + 4.days), @word

    create_record!(created_on: @created_on + 4.days, correct: true)

    assert_not_includes WordsDueForRecall.call(day: @created_on + 5.days), @word
    assert_includes WordsDueForRecall.call(day: @created_on + 7.days), @word
  end

  test "word stops appearing after sixth correct recall" do
    6.times do |index|
      create_record!(created_on: @created_on + index.days, correct: true)
    end

    due_words = WordsDueForRecall.call(day: @created_on + 100.days)

    assert_not_includes due_words, @word
  end

  test "due helper returns true when interval has elapsed" do
    last_correct_record = recall_record_on(@created_on)

    assert WordsDueForRecall.due?(
      word: @word,
      last_correct_record: last_correct_record,
      remember_times: 1,
      day: @created_on + 2.days
    )
  end

  test "due helper returns false when interval has not elapsed" do
    last_correct_record = recall_record_on(@created_on)

    assert_not WordsDueForRecall.due?(
      word: @word,
      last_correct_record: last_correct_record,
      remember_times: 1,
      day: @created_on + 1.day
    )
  end

  test "due helper returns false after schedule is complete" do
    last_correct_record = recall_record_on(@created_on)

    assert_not WordsDueForRecall.due?(
      word: @word,
      last_correct_record: last_correct_record,
      remember_times: 6,
      day: @created_on + 100.days
    )
  end

  private

  def set_word_created_on(word, date)
    word.update!(
      created_at: Time.zone.local(date.year, date.month, date.day, 9),
      updated_at: Time.zone.local(date.year, date.month, date.day, 9)
    )
  end

  def create_record!(created_on:, correct:)
    WordQuestionRecord.create!(
      word_question: @question,
      picked_word: correct ? @word : words(:dog),
      is_correct: correct,
      created_at: Time.zone.local(created_on.year, created_on.month, created_on.day, 10),
      updated_at: Time.zone.local(created_on.year, created_on.month, created_on.day, 10)
    )
  end

  def recall_record_on(date)
    WordQuestionRecord.new(
      word_question: @question,
      picked_word: @word,
      is_correct: true,
      created_at: Time.zone.local(date.year, date.month, date.day, 10)
    )
  end
end
```

- [ ] **Step 3: Run the service tests to confirm they fail**

Run:

```bash
bin/rails test test/services/words_due_for_recall_test.rb
```

Expected: test run fails with an error like:

```text
NameError: uninitialized constant WordsDueForRecallTest::WordsDueForRecall
```

- [ ] **Step 4: Commit the failing tests**

Run:

```bash
git add test/services/words_due_for_recall_test.rb
git commit -m "test: cover daily word recall scheduling"
```

Expected: commit succeeds.

---

## Task 2: Daily Recall Service

**Files:**
- Create: `app/services/words_due_for_recall.rb`
- Test: `test/services/words_due_for_recall_test.rb`

- [ ] **Step 1: Create the service directory**

Run:

```bash
mkdir -p app/services
```

Expected: command exits with status `0`.

- [ ] **Step 2: Implement the service**

Create `app/services/words_due_for_recall.rb`:

```ruby
class WordsDueForRecall
  SCHEDULE_INTERVALS = [0, 2, 3, 5, 7, 15].freeze

  def self.call(day: Date.current)
    new(day: day).call
  end

  def self.due?(word:, last_correct_record:, remember_times:, day:)
    return false if remember_times >= SCHEDULE_INTERVALS.length

    interval_days = SCHEDULE_INTERVALS.fetch(remember_times)
    base_date = (last_correct_record || word).created_at.to_date

    day.to_date >= base_date + interval_days
  end

  def initialize(day:)
    @day = day.to_date
  end

  def call
    Word.includes(word_questions: :word_question_records).select do |word|
      correct_records = correct_records_for(word)

      self.class.due?(
        word: word,
        last_correct_record: latest_record(correct_records),
        remember_times: correct_records.size,
        day: day
      )
    end
  end

  private

  attr_reader :day

  def correct_records_for(word)
    word.word_questions.flat_map(&:word_question_records).select(&:correct?)
  end

  def latest_record(records)
    records.max_by(&:created_at)
  end
end
```

- [ ] **Step 3: Run the service tests to confirm they pass**

Run:

```bash
bin/rails test test/services/words_due_for_recall_test.rb
```

Expected: all tests pass, with output similar to:

```text
10 runs, 20 assertions, 0 failures, 0 errors, 0 skips
```

- [ ] **Step 4: Run the full test suite**

Run:

```bash
bin/rails test
```

Expected: all tests pass with `0 failures, 0 errors`.

- [ ] **Step 5: Commit the service**

Run:

```bash
git add app/services/words_due_for_recall.rb test/services/words_due_for_recall_test.rb
git commit -m "feat: add daily word recall service"
```

Expected: commit succeeds.

---

## Task 3: Final Verification

**Files:**
- Verify: `app/services/words_due_for_recall.rb`
- Verify: `test/services/words_due_for_recall_test.rb`

- [ ] **Step 1: Run style checks**

Run:

```bash
bin/rubocop app/services/words_due_for_recall.rb test/services/words_due_for_recall_test.rb
```

Expected: RuboCop reports no offenses.

- [ ] **Step 2: Run the app CI script**

Run:

```bash
bin/ci
```

Expected: the CI script completes successfully.

- [ ] **Step 3: Check git status**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing files, if any, remain modified.
