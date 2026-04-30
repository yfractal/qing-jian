# Remember Word Page State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep per-pass recalled word IDs in the remember page URL so answered words are hidden for the current pass, then clear the URL state and continue until no words are due today.

**Architecture:** Extend `WordsDueForRecall` with an optional exclusion list so the recall page can ask for due words minus the IDs already answered in the current URL state. `RememberWordsController#index` owns URL-state parsing and clears stale or exhausted pass state by redirecting to the clean root path; `WordQuestionRecordsController#create` appends the submitted question word ID to that URL state on every answer redirect. The remember page shows a congratulations message only when the unfiltered due-word query has no remaining words.

**Tech Stack:** Ruby on Rails 8, Minitest integration/service tests, ERB views, existing `WordsDueForRecall`, `FindOrCreateWordQuestion`, and `WordQuestionRecord` callback flow.

---

## File Structure

- Modify: `app/services/words_due_for_recall.rb` — add optional `excluding_word_ids:` query filter and ID normalization.
- Modify: `test/services/words_due_for_recall_test.rb` — verify excluded IDs are omitted while non-excluded due words remain.
- Modify: `app/controllers/remember_words_controller.rb` — parse `recalled_word_ids`, load filtered due words, clear exhausted URL state, and keep congratulations tied to truly empty due words.
- Modify: `test/controllers/remember_words_controller_test.rb` — verify URL-state filtering, state clearing, and congratulations behavior.
- Modify: `app/views/remember_words/index.html.erb` — preserve current URL-state IDs in the answer form and update the no-due copy.
- Modify: `app/controllers/word_question_records_controller.rb` — append the answered question word ID to `recalled_word_ids` on successful redirect and preserve existing state on validation failure.
- Modify: `test/controllers/word_question_records_controller_test.rb` — verify redirects include appended unique recalled IDs.

### Task 1: Filter Due Words by URL-State IDs

**Files:**
- Modify: `app/services/words_due_for_recall.rb`
- Test: `test/services/words_due_for_recall_test.rb`

- [ ] **Step 1: Write the failing service tests**

Add these tests above the existing `"correct recall increments remember times and sets next due day"` test in `test/services/words_due_for_recall_test.rb`:

```ruby
  test "excludes recalled words from due words" do
    another_word = create_word!("horse", created_on: @created_on)

    due_words = WordsDueForRecall.call(
      day: @created_on,
      excluding_word_ids: [ @word.id ]
    )

    assert_not_includes due_words, @word
    assert_includes due_words, another_word
  end

  test "ignores blank and invalid excluded word ids" do
    due_words = WordsDueForRecall.call(
      day: @created_on,
      excluding_word_ids: [ "", nil, "not-a-number" ]
    )

    assert_includes due_words, @word
  end
```

- [ ] **Step 2: Run the service test to verify it fails**

Run: `bin/rails test test/services/words_due_for_recall_test.rb`

Expected: FAIL with `unknown keyword: :excluding_word_ids`.

- [ ] **Step 3: Add the optional exclusion filter**

Replace `app/services/words_due_for_recall.rb` with:

```ruby
class WordsDueForRecall
  RECALL_RULES = [
    { remember_times: 0, interval_days: 0 },
    { remember_times: 1, interval_days: 2 },
    { remember_times: 2, interval_days: 3 },
    { remember_times: 3, interval_days: 5 },
    { remember_times: 4, interval_days: 7 },
    { remember_times: 5, interval_days: 15 }
  ].freeze

  class << self
    def call(day: Date.current, excluding_word_ids: [])
      due_words = Word.joins(:word_recall_state).where(word_recall_states: { due_day: ..day.to_date })
      excluded_ids = normalize_word_ids(excluding_word_ids)

      return due_words if excluded_ids.empty?

      due_words.where.not(id: excluded_ids)
    end

    def due?(word:, last_correct_record:, remember_times:, day:)
      due_day = next_due_day(
        word: word,
        last_correct_record: last_correct_record,
        remember_times: remember_times
      )

      due_day.present? && day.to_date >= due_day
    end

    def update_state_for(record)
      return unless record.correct?

      word = record.word_question.word
      state = WordRecallState.find_or_initialize_by(word: word)
      state.remember_times ||= 0
      state.due_day ||= word.created_at.to_date

      state.remember_times += 1
      state.due_day = next_due_day(
        word: word,
        last_correct_record: record,
        remember_times: state.remember_times
      )
      state.save!
    end

    private

    def normalize_word_ids(word_ids)
      Array(word_ids).filter_map { |word_id| Integer(word_id, exception: false) }.uniq
    end

    def next_due_day(word:, last_correct_record:, remember_times:)
      rule = RECALL_RULES.find { |recall_rule| recall_rule[:remember_times] == remember_times }
      return unless rule

      base_date = last_correct_record&.created_at&.to_date || word.created_at.to_date
      base_date + rule[:interval_days].days
    end
  end
end
```

- [ ] **Step 4: Run the service test to verify it passes**

Run: `bin/rails test test/services/words_due_for_recall_test.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/words_due_for_recall.rb test/services/words_due_for_recall_test.rb
git commit -m "feat: filter recalled words from due recall list"
```

### Task 2: Use URL State on the Remember Page

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Modify: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write failing controller tests for URL-state filtering and clearing**

Replace `test/controllers/remember_words_controller_test.rb` with:

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
    word = create_due_word!("test")
    create_question_for!(word)

    get root_url

    assert_response :success
    assert_match word.chinese_meaning, @response.body
    assert_select "form"
    assert_select "input[type='radio'][name='word_question_record[picked_word_id]']"
  end

  test "filters recalled word ids from the current pass" do
    first_word = create_due_word!("first")
    second_word = create_due_word!("second")
    create_question_for!(first_word)
    create_question_for!(second_word)

    get root_url(recalled_word_ids: first_word.id.to_s)

    assert_response :success
    assert_no_match first_word.chinese_meaning, @response.body
    assert_match second_word.chinese_meaning, @response.body
  end

  test "clears recalled word state when the filtered pass is exhausted but words are still due" do
    word = create_due_word!("retry")
    create_question_for!(word)

    get root_url(recalled_word_ids: word.id.to_s)

    assert_redirected_to root_url
    assert_equal "Starting another recall pass for words still due.", flash[:notice]
  end

  test "clears stale recalled word state when no words are due" do
    word = create_due_word!("finished")
    create_question_for!(word)
    word.word_recall_state.update!(due_day: Date.current + 100.days)

    get root_url(recalled_word_ids: word.id.to_s)

    assert_redirected_to root_url
    assert_equal "All words recalled for today.", flash[:notice]
  end

  test "shows congratulations when no words are due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)

    get root_url

    assert_response :success
    assert_match "Congratulations! You have recalled all words due today.", @response.body
  end

  private

  def create_due_word!(name)
    Word.create!(
      word: "#{name}_#{SecureRandom.hex(4)}",
      english_meaning: "#{name} english",
      chinese_meaning: "#{name} chinese"
    ).tap do |word|
      word.word_recall_state.update!(due_day: Date.current)
    end
  end

  def create_question_for!(word)
    question = WordQuestion.new(word: word)

    3.times do |index|
      similar_word = Word.create!(
        word: "#{word.word}_choice_#{index}_#{SecureRandom.hex(4)}",
        english_meaning: "choice #{index}",
        chinese_meaning: "choice #{index}"
      )
      question.similar_words.build(word: similar_word)
    end

    question.save!
    question
  end
end
```

- [ ] **Step 2: Run the controller test to verify it fails**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected: FAIL because `RememberWordsController#index` does not read or clear `recalled_word_ids`, and the page still uses the old no-due message.

- [ ] **Step 3: Implement URL-state parsing and pass clearing**

Replace `app/controllers/remember_words_controller.rb` with:

```ruby
class RememberWordsController < ApplicationController
  def index
    @recalled_word_ids = recalled_word_ids

    due_words = WordsDueForRecall.call(day: Date.current)
    filtered_due_words = WordsDueForRecall.call(
      day: Date.current,
      excluding_word_ids: @recalled_word_ids
    )

    if @recalled_word_ids.any? && filtered_due_words.none?
      redirect_to root_path, notice: pass_cleared_notice(due_words)
      return
    end

    @question = build_question(filtered_due_words.first)
    @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
  end

  private

  def recalled_word_ids
    params[:recalled_word_ids].to_s.split(",").filter_map do |word_id|
      Integer(word_id, exception: false)
    end.uniq
  end

  def pass_cleared_notice(due_words)
    if due_words.exists?
      "Starting another recall pass for words still due."
    else
      "All words recalled for today."
    end
  end

  def build_question(word)
    return nil unless word

    FindOrCreateWordQuestion.new.call(word: word)
  end
end
```

- [ ] **Step 4: Run the controller test to verify controller behavior passes**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected: FAIL only on the congratulations text until Task 3 updates the view. If additional failures appear, fix only controller-level issues in `app/controllers/remember_words_controller.rb`.

- [ ] **Step 5: Commit controller and test changes after Task 3 passes**

Do not commit yet if the view assertion is still failing. Commit after Task 3 with the view change.

### Task 3: Preserve URL State in the Answer Form and Update Congratulations Copy

**Files:**
- Modify: `app/views/remember_words/index.html.erb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Add a failing form-state assertion**

Add this test above `"shows congratulations when no words are due"` in `test/controllers/remember_words_controller_test.rb`:

```ruby
  test "includes current recalled word ids in the answer form" do
    first_word = create_due_word!("answered")
    second_word = create_due_word!("visible")
    create_question_for!(first_word)
    create_question_for!(second_word)

    get root_url(recalled_word_ids: first_word.id.to_s)

    assert_response :success
    assert_select "input[type='hidden'][name='recalled_word_ids'][value='#{first_word.id}']"
  end
```

- [ ] **Step 2: Run the controller test to verify it fails**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected: FAIL because the form does not include the `recalled_word_ids` hidden field and still renders the old no-due copy.

- [ ] **Step 3: Update the remember page view**

Replace `app/views/remember_words/index.html.erb` with:

```erb
<% content_for :title, "Remember words" %>

<h1>Remember words</h1>

<p class="toolbar">
  <%= link_to "Add new word", new_word_path, class: "button button-primary" %>
</p>

<% if @question.present? %>
  <section class="recall-card">
    <h2><%= @question.word.chinese_meaning %></h2>
    <p>Choose the correct English word.</p>

    <%= form_with model: @word_question_record, url: word_question_records_path do |form| %>
      <%= hidden_field_tag :recalled_word_ids, @recalled_word_ids.join(",") if @recalled_word_ids.present? %>
      <%= form.hidden_field :word_question_id, value: @question.id %>

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
  <p>Congratulations! You have recalled all words due today.</p>
<% end %>
```

- [ ] **Step 4: Run the remember controller test to verify it passes**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb test/controllers/remember_words_controller_test.rb
git commit -m "feat: track remember page pass state in url"
```

### Task 4: Append Recalled Word IDs on Answer Redirect

**Files:**
- Modify: `app/controllers/word_question_records_controller.rb`
- Test: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Write failing redirect tests**

Replace `test/controllers/word_question_records_controller_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"

class WordQuestionRecordsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @word = Word.create!(
      word: "test_word_#{SecureRandom.hex(4)}",
      english_meaning: "test",
      chinese_meaning: "测试"
    )
    @question = WordQuestion.new(word: @word)
    @question.similar_words.build(word: Word.create!(word: "similar_1_#{SecureRandom.hex(4)}", english_meaning: "s1", chinese_meaning: "s1"))
    @question.similar_words.build(word: Word.create!(word: "similar_2_#{SecureRandom.hex(4)}", english_meaning: "s2", chinese_meaning: "s2"))
    @question.similar_words.build(word: Word.create!(word: "similar_3_#{SecureRandom.hex(4)}", english_meaning: "s3", chinese_meaning: "s3"))
    @question.save!
  end

  test "creates a correct record and redirects to root with recalled word id" do
    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_word_id: @word.id
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal true, record.is_correct
    assert_redirected_to root_url(recalled_word_ids: @word.id.to_s)
  end

  test "creates an incorrect record and redirects to root with recalled word id" do
    wrong_word = @question.similar_words.first.word

    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_word_id: wrong_word.id
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal false, record.is_correct
    assert_redirected_to root_url(recalled_word_ids: @word.id.to_s)
  end

  test "appends recalled word id to existing url state" do
    previous_word = Word.create!(
      word: "previous_#{SecureRandom.hex(4)}",
      english_meaning: "previous",
      chinese_meaning: "previous"
    )

    post word_question_records_url, params: {
      recalled_word_ids: previous_word.id.to_s,
      word_question_record: {
        word_question_id: @question.id,
        picked_word_id: @word.id
      }
    }

    assert_redirected_to root_url(recalled_word_ids: "#{previous_word.id},#{@word.id}")
  end

  test "does not duplicate recalled word id on redirect" do
    post word_question_records_url, params: {
      recalled_word_ids: @word.id.to_s,
      word_question_record: {
        word_question_id: @question.id,
        picked_word_id: @word.id
      }
    }

    assert_redirected_to root_url(recalled_word_ids: @word.id.to_s)
  end

  test "preserves existing recalled word ids when record creation fails" do
    previous_word = Word.create!(
      word: "previous_failure_#{SecureRandom.hex(4)}",
      english_meaning: "previous failure",
      chinese_meaning: "previous failure"
    )

    assert_no_difference("WordQuestionRecord.count") do
      post word_question_records_url, params: {
        recalled_word_ids: previous_word.id.to_s,
        word_question_record: {
          word_question_id: "missing",
          picked_word_id: @word.id
        }
      }
    end

    assert_redirected_to root_url(recalled_word_ids: previous_word.id.to_s)
    assert_equal "Could not save answer.", flash[:alert]
  end
end
```

- [ ] **Step 2: Run the record controller test to verify it fails**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`

Expected: FAIL because successful redirects still go to the clean root path and failure redirects do not preserve URL state.

- [ ] **Step 3: Append the answered question word ID in redirects**

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

    redirect_to root_path_with_recalled_ids(recalled_word_ids + [ question.word_id ]), notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path_with_recalled_ids(recalled_word_ids), alert: "Could not save answer."
  end

  private

  def record_params
    params.require(:word_question_record).permit(:word_question_id, :picked_word_id)
  end

  def recalled_word_ids
    params[:recalled_word_ids].to_s.split(",").filter_map do |word_id|
      Integer(word_id, exception: false)
    end
  end

  def root_path_with_recalled_ids(word_ids)
    normalized_word_ids = word_ids.uniq
    return root_path if normalized_word_ids.empty?

    root_path(recalled_word_ids: normalized_word_ids.join(","))
  end
end
```

- [ ] **Step 4: Run the record controller test to verify it passes**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/word_question_records_controller.rb test/controllers/word_question_records_controller_test.rb
git commit -m "feat: append recalled word ids after answers"
```

### Task 5: Verify the Full Recall Loop

**Files:**
- Test: `test/services/words_due_for_recall_test.rb`
- Test: `test/controllers/remember_words_controller_test.rb`
- Test: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Run the focused test suite**

Run:

```bash
bin/rails test test/services/words_due_for_recall_test.rb test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
bin/rails test
```

Expected: PASS.

- [ ] **Step 3: Manually verify the URL loop in the browser**

Run:

```bash
bin/rails server
```

Expected: Rails server starts and prints a local URL such as `http://127.0.0.1:3000`.

Manual checks:

1. Visit `/`.
2. Answer a due word.
3. Confirm the redirect URL includes `?recalled_word_ids=<answered-word-id>`.
4. Continue answering until all visible due words in the current pass are exhausted.
5. Confirm the app redirects back to `/` without `recalled_word_ids`.
6. If an answered word was incorrect, confirm it can appear again in the next clean pass.
7. Once all due words are answered correctly and their recall states advance, confirm `/` shows `Congratulations! You have recalled all words due today.`

- [ ] **Step 4: Commit any verification fixes**

If verification required changes, commit them:

```bash
git add app/services/words_due_for_recall.rb app/controllers/remember_words_controller.rb app/controllers/word_question_records_controller.rb app/views/remember_words/index.html.erb test/services/words_due_for_recall_test.rb test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb
git commit -m "fix: complete remember page state loop"
```

If no fixes were required, do not create an empty commit.

## Self-Review

- Spec coverage: The plan stores recalled word IDs in the URL, filters them through `WordsDueForRecall`, appends the newly answered word ID on each redirect, clears the URL state when the filtered pass is exhausted, continues still-due words in a fresh pass, and shows congratulations only when no words are due today.
- Placeholder scan: No placeholder tasks or open-ended error-handling instructions remain; every code-changing step includes concrete code.
- Type consistency: The URL parameter is consistently named `recalled_word_ids`, parsed as comma-separated IDs, passed to `WordsDueForRecall.call(day:, excluding_word_ids:)`, and written back with `root_path(recalled_word_ids: ids.join(","))`.
