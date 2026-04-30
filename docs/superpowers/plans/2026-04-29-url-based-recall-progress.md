# URL-Based Recall Progress Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track which words have already been answered in today's session via URL query param `recalled_ids`, skip those words in the recall queue, and show a congratulations message when all due words are exhausted.

**Architecture:** The URL carries a `recalled_ids` comma-separated list of word IDs that have already been answered this session. `RememberWordsController#index` reads this param to filter the due-word list before picking the next word. `WordQuestionRecordsController#create` appends the just-answered word's ID to `recalled_ids` on the redirect. When all due words are in `recalled_ids`, the page shows a congratulations message and the redirect omits `recalled_ids` (clearing state). No cookies, no session, no database changes needed.

**Tech Stack:** Ruby on Rails 8, Minitest (integration tests), ERB views

---

## File Structure

- Modify: `app/controllers/remember_words_controller.rb` — read `recalled_ids` param, filter due words, expose `@all_done` flag
- Modify: `app/controllers/word_question_records_controller.rb` — merge answered word ID into `recalled_ids`, redirect to root with updated param
- Modify: `app/views/remember_words/index.html.erb` — pass `recalled_ids` as hidden field in form; show congratulations when `@all_done`
- Modify: `test/controllers/remember_words_controller_test.rb` — test filtering and all-done state
- Modify: `test/controllers/word_question_records_controller_test.rb` — test redirect carries updated `recalled_ids`

---

### Task 1: Pass `recalled_ids` Through the Form and Back in the Redirect

**Files:**
- Modify: `app/views/remember_words/index.html.erb`
- Modify: `app/controllers/word_question_records_controller.rb`
- Modify: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Write failing tests for redirect carrying `recalled_ids`**

Open `test/controllers/word_question_records_controller_test.rb` and add two tests. The first checks that a fresh submit (no prior `recalled_ids`) redirects with the answered word's ID. The second checks that a submit with existing `recalled_ids` appends the new ID.

```ruby
test "redirects to root with recalled_ids containing the answered word" do
  post word_question_records_url, params: {
    word_question_record: {
      word_question_id: @question.id,
      picked_word_id: @word.id,
      recalled_ids: ""
    }
  }

  assert_redirected_to root_url(recalled_ids: @word.id.to_s)
end

test "appends answered word id to existing recalled_ids on redirect" do
  other_word = @question.similar_words.first.word

  post word_question_records_url, params: {
    word_question_record: {
      word_question_id: @question.id,
      picked_word_id: @word.id,
      recalled_ids: other_word.id.to_s
    }
  }

  expected_ids = [other_word.id, @word.id].map(&:to_s).join(",")
  assert_redirected_to root_url(recalled_ids: expected_ids)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: FAIL — redirects to `root_url` without `recalled_ids`.

- [ ] **Step 3: Update `WordQuestionRecordsController#create` to pass `recalled_ids`**

Replace the full file content of `app/controllers/word_question_records_controller.rb`:

```ruby
class WordQuestionRecordsController < ApplicationController
  def create
    question = WordQuestion.find(record_params[:word_question_id])
    picked_word = Word.find(record_params[:picked_word_id])

    WordQuestionRecord.create!(
      word_question: question,
      picked_word: picked_word,
      is_correct: picked_word.id == question.word_id
    )

    redirect_to root_path(recalled_ids: next_recalled_ids(question.word_id)),
                notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Could not save answer."
  end

  private

  def record_params
    params.require(:word_question_record).permit(:word_question_id, :picked_word_id, :recalled_ids)
  end

  def next_recalled_ids(word_id)
    prior = params.dig(:word_question_record, :recalled_ids).to_s
    ids = prior.split(",").map(&:strip).reject(&:empty?)
    (ids + [ word_id.to_s ]).join(",")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: PASS (4 tests).

- [ ] **Step 5: Add `recalled_ids` hidden field to the form view**

Replace `app/views/remember_words/index.html.erb` with:

```erb
<% content_for :title, "Remember words" %>

<h1>Remember words</h1>

<p class="toolbar">
  <%= link_to "Add new word", new_word_path, class: "button button-primary" %>
</p>

<% if @all_done %>
  <section class="recall-complete">
    <p>Congratulations! You have remembered all the words for today.</p>
  </section>
<% elsif @question.present? %>
  <section class="recall-card">
    <h2><%= @question.word.chinese_meaning %></h2>
    <p>Choose the correct English word.</p>

    <%= form_with model: @word_question_record, url: word_question_records_path do |form| %>
      <%= form.hidden_field :word_question_id, value: @question.id %>
      <%= form.hidden_field :recalled_ids, value: params[:recalled_ids].to_s %>

      <% @question.choices.shuffle.each do |choice| %>
        <label>
          <%= radio_button_tag "word_question_record[picked_word_id]", choice.id, false, required: true %>
          <%= choice.word %>
        </label><br>
      <% end %>

      <%= form.submit "Submit answer", class: "button button-primary" %>
    <% end %>
  </section>
<% else %>
  <p>No words due today. Nice work!</p>
<% end %>
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/word_question_records_controller.rb \
        app/views/remember_words/index.html.erb \
        test/controllers/word_question_records_controller_test.rb
git commit -m "feat: pass recalled_ids through form and append on redirect"
```

---

### Task 2: Filter Out Already-Recalled Words in the Controller

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Modify: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write failing tests for recall filtering**

Open `test/controllers/remember_words_controller_test.rb`. Add tests for:
- a due word being skipped when its ID is in `recalled_ids`
- a second due word being shown instead

First, look at the existing test helper to understand how words are created (line 20-26 of the current test file). The pattern is: `Word.create!` + `word.word_recall_state.update!(due_day: Date.current)`.

Replace the full file `test/controllers/remember_words_controller_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"

class RememberWordsControllerTest < ActionDispatch::IntegrationTest
  test "root renders remember words index" do
    get root_url
    assert_response :success
    assert_select "h1", "Remember words"
  end

  test "shows add new word button" do
    get root_url
    assert_response :success
    assert_select "a", "Add new word"
  end

  test "renders question form when question is available" do
    word = make_due_word("テスト", "test word", "test_#{Time.now.to_i}")
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word.word_recall_state.update!(due_day: Date.current)

    get root_url

    assert_response :success
    assert_match "テスト", @response.body
    assert_select "form"
    assert_select "input[type='radio'][name='word_question_record[picked_word_id]']"
  end

  test "skips a word whose id is in recalled_ids and shows the next due word" do
    word1 = make_due_word("第一", "first", "first_#{Time.now.to_i}")
    word2 = make_due_word("第二", "second", "second_#{Time.now.to_i}")
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word1.word_recall_state.update!(due_day: Date.current)
    word2.word_recall_state.update!(due_day: Date.current)

    get root_url(recalled_ids: word1.id.to_s)

    assert_response :success
    assert_match "第二", @response.body
    assert_no_match "第一", @response.body
  end

  test "shows congratulations when all due words are recalled" do
    word = make_due_word("完成", "done", "done_#{Time.now.to_i}")
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word.word_recall_state.update!(due_day: Date.current)

    get root_url(recalled_ids: word.id.to_s)

    assert_response :success
    assert_match "Congratulations", @response.body
    assert_select "form", count: 0
  end

  test "shows no-words message when no words are due today" do
    WordRecallState.update_all(due_day: Date.current + 100.days)

    get root_url

    assert_response :success
    assert_match "No words due today", @response.body
  end

  private

  def make_due_word(chinese, english, word_text)
    word = Word.create!(
      word: word_text,
      english_meaning: english,
      chinese_meaning: chinese
    )
    word
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: FAIL — "skips a word" and "shows congratulations" tests will fail because the controller ignores `recalled_ids`.

- [ ] **Step 3: Update `RememberWordsController#index` to filter recalled words**

Replace `app/controllers/remember_words_controller.rb` with:

```ruby
class RememberWordsController < ApplicationController
  def index
    due_words = WordsDueForRecall.call(day: Date.current)
    recalled = recalled_ids_from_params

    remaining = due_words.reject { |w| recalled.include?(w.id) }

    if due_words.any? && remaining.empty?
      @all_done = true
    else
      @question = build_question(remaining.first)
      @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
    end
  end

  private

  def recalled_ids_from_params
    params[:recalled_ids].to_s.split(",").map(&:strip).filter_map { |id| Integer(id, 10) rescue nil }
  end

  def build_question(word)
    return nil unless word

    FindOrCreateWordQuestion.new.call(word: word)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/remember_words_controller.rb \
        test/controllers/remember_words_controller_test.rb
git commit -m "feat: filter recalled words from queue using recalled_ids param"
```

---

### Task 3: Clear `recalled_ids` When All Words Are Done

**Files:**
- Modify: `app/controllers/word_question_records_controller.rb`
- Modify: `test/controllers/word_question_records_controller_test.rb`

The logic: after saving the record, if `next_recalled_ids` covers all of today's due words, redirect to `root_path` **without** `recalled_ids` (the congratulations branch). This means the "all done" state is detected on the **next** GET, not on the POST itself — which is what we already have from Task 2. So the only thing the controller must do is always append and redirect; the view handles the `@all_done` rendering.

However, we do want to clear `recalled_ids` from the URL when there are no more words. That way, a page refresh after congratulations doesn't leave a stale param in the URL. We add this cleanup in the controller.

- [ ] **Step 1: Write failing test for `recalled_ids` cleared on all-done redirect**

Add to `test/controllers/word_question_records_controller_test.rb`:

```ruby
test "clears recalled_ids on redirect when all due words have been answered" do
  # Set word's recall state to today so WordsDueForRecall.call returns it
  @word.word_recall_state.update!(due_day: Date.current)
  # All other words in DB are not due (push them far into the future)
  WordRecallState.where.not(word: @word).update_all(due_day: Date.current + 100.days)

  post word_question_records_url, params: {
    word_question_record: {
      word_question_id: @question.id,
      picked_word_id: @word.id,
      recalled_ids: ""
    }
  }

  # After answering the only due word, recalled_ids should be cleared
  assert_redirected_to root_url
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: FAIL — redirects to `root_url(recalled_ids: @word.id.to_s)` instead of bare `root_url`.

- [ ] **Step 3: Update controller to clear `recalled_ids` when all words are answered**

Replace `app/controllers/word_question_records_controller.rb` with:

```ruby
class WordQuestionRecordsController < ApplicationController
  def create
    question = WordQuestion.find(record_params[:word_question_id])
    picked_word = Word.find(record_params[:picked_word_id])

    WordQuestionRecord.create!(
      word_question: question,
      picked_word: picked_word,
      is_correct: picked_word.id == question.word_id
    )

    ids = next_recalled_ids(question.word_id)
    if all_done?(ids)
      redirect_to root_path, notice: "Answer saved."
    else
      redirect_to root_path(recalled_ids: ids), notice: "Answer saved."
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Could not save answer."
  end

  private

  def record_params
    params.require(:word_question_record).permit(:word_question_id, :picked_word_id, :recalled_ids)
  end

  def next_recalled_ids(word_id)
    prior = params.dig(:word_question_record, :recalled_ids).to_s
    ids = prior.split(",").map(&:strip).reject(&:empty?)
    (ids + [ word_id.to_s ]).join(",")
  end

  def all_done?(recalled_ids_str)
    due_word_ids = WordsDueForRecall.call(day: Date.current).map { |w| w.id.to_s }
    return false if due_word_ids.empty?

    recalled = recalled_ids_str.split(",").map(&:strip)
    (due_word_ids - recalled).empty?
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/word_question_records_controller.rb \
        test/controllers/word_question_records_controller_test.rb
git commit -m "feat: clear recalled_ids on redirect when all due words answered"
```

---

### Task 4: Full Verification Pass

**Files:**
- Test: all controller tests + service tests

- [ ] **Step 1: Run all controller tests**

Run: `bin/rails test test/controllers/`
Expected: PASS (all tests).

- [ ] **Step 2: Run all tests**

Run: `bin/rails test --exclude test/lib/`
Expected: PASS.

> Note: `test/lib/tasks/words_batch_import_test.rb` has a pre-existing `Minitest::Mock` error unrelated to this feature. Exclude it with `--exclude test/lib/` or run individual paths.

- [ ] **Step 3: Commit (if any fixups were needed)**

```bash
git add .
git commit -m "test: full verification pass for recalled_ids session tracking"
```

---

## Self-Review

**1. Spec coverage check:**
- ✅ Track recalled words in URL — `recalled_ids` param threaded through form → POST → redirect
- ✅ Filter due words by `recalled_ids` in controller
- ✅ Show congratulations when all due words exhausted
- ✅ Clear `recalled_ids` from URL when done (so page refresh shows clean congratulations, not stale param)
- ✅ Redirect after each answer carries new recalled word's ID appended

**2. Placeholder scan:** No TODOs, TBDs, or vague instructions. All code blocks are complete.

**3. Type consistency:**
- `recalled_ids` is always a comma-separated string in URL params and form hidden fields
- `recalled_ids_from_params` returns `Array<Integer>` (controller)
- `next_recalled_ids` returns a comma-separated `String` (controller helper)
- `all_done?` takes a comma-separated `String` and returns `Boolean`
- These are consistent across Task 1, 2, and 3.
