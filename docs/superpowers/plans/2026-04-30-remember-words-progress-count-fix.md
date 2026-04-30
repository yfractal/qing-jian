# Remember Words Progress Count Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make progress count based on today's active workload: words currently due plus words already remembered correctly today.

**Architecture:** Keep the existing Remember Words UI and progress card, but move progress counting logic to a query-backed calculation in `RememberWordsController`. Compute two sets from database state: (1) words currently due (`WordsDueForRecall.call(day: Date.current)`), and (2) words with at least one correct `WordQuestionRecord` created today. Build progress scope as the union of both sets so words answered correctly today remain in progress totals even after recall state advances `due_day`.

**Tech Stack:** Ruby on Rails (controllers, ActiveRecord, Minitest integration tests), ERB, CSS

---

## File Structure

- Modify: `app/controllers/remember_words_controller.rb`
  - Replace progress counting internals from pass-state-based counting to DB-backed day-based counting.
- Modify: `test/controllers/remember_words_controller_test.rb`
  - Add/replace tests to enforce “due today + remembered today” behavior and prevent regression.
- Keep: `app/views/remember_words/index.html.erb`
  - No structural change expected; it should continue to render controller-provided counts.
- Keep: `app/assets/stylesheets/application.css`
  - No styling change required for this logic-only fix.

### Task 1: Lock Correct Counting Behavior with Failing Tests

**Files:**
- Modify: `test/controllers/remember_words_controller_test.rb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write the failing test for “remembered today” (not pass state)**

```ruby
test "progress includes remembered-today words after due_day advances" do
  WordRecallState.update_all(due_day: Date.current + 100.days)

  remembered_word = create_due_word!("remembered_today")
  still_due_word = create_due_word!("still_due_today")
  remembered_question = create_question_for!(remembered_word)
  create_question_for!(still_due_word)

  WordQuestionRecord.create!(
    word_question: remembered_question,
    picked_choice_token: "word:#{remembered_word.id}",
    picked_choice_word: remembered_word.word,
    is_correct: true,
    created_at: Time.zone.now
  )

  get root_url

  assert_response :success
  assert_equal Date.current + 2.days, remembered_word.reload.word_recall_state.due_day
  assert_select ".remember-progress-main", text: /Remembered 1 \/ 2/
  assert_select ".remember-progress-meta", text: /Need to remember 1/
end
```

- [ ] **Step 2: Write the failing test proving old `recalled_word_ids` no longer drives remembered count**

```ruby
test "progress ignores recalled_word_ids when no correct record exists today" do
  WordRecallState.update_all(due_day: Date.current + 100.days)

  first_word = create_due_word!("pass_state_first")
  second_word = create_due_word!("pass_state_second")
  create_question_for!(first_word)
  create_question_for!(second_word)

  get root_url(recalled_word_ids: first_word.id.to_s)

  assert_response :success
  assert_select ".remember-progress-main", text: /Remembered 0 \/ 2/
  assert_select ".remember-progress-meta", text: /Need to remember 2/
end
```

- [ ] **Step 3: Run test file and verify failure**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected:
- FAIL on at least one new assertion (current implementation ties remembered count to `recalled_word_ids`)
- Existing unrelated tests may still pass

- [ ] **Step 4: Commit failing tests**

```bash
git add test/controllers/remember_words_controller_test.rb
git commit -m "test: define due-today progress counting behavior"
```

### Task 2: Implement Database-Backed Progress Counting

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write minimal implementation in `load_progress_counts!`**

```ruby
def load_progress_counts!
  current_due_word_ids = WordsDueForRecall.call(day: Date.current).pluck(:id)

  remembered_today_word_ids = WordQuestionRecord
    .joins(:word_question)
    .where(is_correct: true, created_at: Time.zone.today.all_day)
    .distinct
    .pluck("word_questions.word_id")

  progress_word_ids = current_due_word_ids | remembered_today_word_ids

  @remember_total_count = progress_word_ids.size
  @remembered_count = remembered_today_word_ids.size
  @remaining_count = current_due_word_ids.size
  @progress_percent = if @remember_total_count.zero?
    0
  else
    ((@remembered_count.to_f / @remember_total_count) * 100).round
  end
end
```

- [ ] **Step 2: Keep remaining count derived from current due set**

No subtraction guard is needed because remaining is directly `current_due_word_ids.size`, which naturally tracks due words not yet answered correctly today.

- [ ] **Step 3: Run the focused controller tests**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected:
- PASS for new due-today tests
- PASS for existing Remember Words controller tests

- [ ] **Step 4: Run broader test smoke for confidence**

Run: `bin/rails test`

Expected:
- PASS with no regressions in unrelated areas

- [ ] **Step 5: Commit implementation**

```bash
git add app/controllers/remember_words_controller.rb test/controllers/remember_words_controller_test.rb
git commit -m "fix: count remember progress by due-today completion"
```

### Task 3: Verification and Cleanup

**Files:**
- Modify: none (unless issues found)
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Manual behavior check in browser**

Run server: `bin/rails server`

Check:
- With due words and no correct record today: `Remembered 0 / N`
- After one correct answer today: `Remembered 1 / N`
- `recalled_word_ids` changes navigation flow but does not directly change remembered progress

- [ ] **Step 2: Confirm no lint issues on touched files**

Run project lint command (if configured) or use editor diagnostics.

Expected:
- No new lint offenses in `remember_words_controller.rb` and the updated test file

- [ ] **Step 3: Final commit if verification tweaks were required**

```bash
git add <touched-files>
git commit -m "chore: finalize remember progress count verification"
```

## Self-Review

### 1. Spec coverage
- Requirement: Remembered should count words that should be remembered today and have been remembered.
  - Covered by Task 1 tests + Task 2 DB-backed counting implementation.
- Requirement: Remaining should represent due-today minus remembered.
  - Covered by Task 2 arithmetic and safety guard.

### 2. Placeholder scan
- No `TODO`/`TBD` placeholders.
- All code-changing steps include concrete code snippets.
- All validation steps include concrete commands and expected outcomes.

### 3. Type/signature consistency
- Controller method remains `load_progress_counts!`.
- Uses existing associations: `WordQuestionRecord -> WordQuestion -> Word`.
- Reuses existing view instance variables (`@remember_total_count`, `@remembered_count`, `@remaining_count`, `@progress_percent`), so no template contract change.
