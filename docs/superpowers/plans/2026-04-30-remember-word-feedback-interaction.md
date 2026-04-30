# Remember Word Feedback Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a polished answer-feedback step to the Remember Words page so learners see whether they were correct, can review the right answer when wrong, and then intentionally continue to the next due word.

**Architecture:** Keep the flow server-rendered and Rails-first. `WordQuestionRecordsController#create` saves the answer and redirects to `RememberWordsController#index` with `result_record_id`; `RememberWordsController#index` renders either normal question state, feedback state, or completion state. The view owns presentation, while controllers prepare simple state such as selected choice token, correct choice token, and `next_word_path`.

**Tech Stack:** Ruby on Rails 8.1, ERB views, app-wide CSS in `app/assets/stylesheets/application.css`, Minitest integration tests.

---

## File Structure

- Modify: `app/controllers/word_question_records_controller.rb` - redirect successful submissions to result mode instead of immediately appending the answered word to `recalled_word_ids`.
- Modify: `app/controllers/remember_words_controller.rb` - detect `result_record_id`, prepare feedback-state variables, and build the `Next word` URL.
- Modify: `app/views/remember_words/index.html.erb` - render polished question, feedback, and completion states.
- Modify: `app/assets/stylesheets/application.css` - add the centered flashcard layout, segmented direction control, choice cards, feedback states, and responsive buttons.
- Modify: `test/controllers/word_question_records_controller_test.rb` - update submission redirect expectations.
- Modify: `test/controllers/remember_words_controller_test.rb` - add feedback rendering, next-word URL, invalid result fallback, and completion card coverage.

## Task 1: Redirect Submissions To Result Mode

**Files:**
- Modify: `test/controllers/word_question_records_controller_test.rb`
- Modify: `app/controllers/word_question_records_controller.rb`

- [ ] **Step 1: Update the successful redirect tests before changing controller code**

In `test/controllers/word_question_records_controller_test.rb`, replace the first four success-path tests with these versions:

```ruby
  test "creates a correct record and redirects to result mode" do
    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_choice: "word:#{@word.id}"
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal true, record.is_correct
    assert_redirected_to root_url(direction: "english_to_chinese", result_record_id: record.id)
  end

  test "creates an incorrect record and redirects to result mode" do
    wrong_choice = @question.similar_words.first

    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_choice: "similar_word:#{wrong_choice.id}"
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal false, record.is_correct
    assert_redirected_to root_url(direction: "english_to_chinese", result_record_id: record.id)
  end

  test "preserves existing recalled word ids when redirecting to result mode" do
    previous_word = Word.create!(
      word: "previous_#{SecureRandom.hex(4)}",
      english_meaning: "previous",
      chinese_meaning: "previous"
    )

    post word_question_records_url, params: {
      recalled_word_ids: previous_word.id.to_s,
      word_question_record: {
        word_question_id: @question.id,
        picked_choice: "word:#{@word.id}"
      }
    }

    record = WordQuestionRecord.order(:created_at).last
    assert_redirected_to root_url(
      direction: "english_to_chinese",
      recalled_word_ids: previous_word.id.to_s,
      result_record_id: record.id
    )
  end

  test "does not append answered word id until next word is clicked" do
    post word_question_records_url, params: {
      recalled_word_ids: @word.id.to_s,
      word_question_record: {
        word_question_id: @question.id,
        picked_choice: "word:#{@word.id}"
      }
    }

    record = WordQuestionRecord.order(:created_at).last
    assert_redirected_to root_url(
      direction: "english_to_chinese",
      recalled_word_ids: @word.id.to_s,
      result_record_id: record.id
    )
  end
```

Also update the successful direction-preservation test to expect result mode:

```ruby
  test "preserves english_to_chinese direction on successful redirect" do
    post word_question_records_url, params: {
      direction: "english_to_chinese",
      word_question_record: {
        word_question_id: @question.id,
        picked_choice: "word:#{@word.id}"
      }
    }

    record = WordQuestionRecord.order(:created_at).last
    assert_redirected_to root_url(direction: "english_to_chinese", result_record_id: record.id)
  end
```

- [ ] **Step 2: Run the changed controller test and confirm it fails**

Run:

```bash
bin/rails test test/controllers/word_question_records_controller_test.rb
```

Expected: failures showing redirects still include the answered word id in `recalled_word_ids` and do not include `result_record_id`.

- [ ] **Step 3: Change successful submission redirect behavior**

In `app/controllers/word_question_records_controller.rb`, replace `create` with:

```ruby
  def create
    question = WordQuestion.find(record_params[:word_question_id])
    picked_choice = question.choice_for_token(record_params[:picked_choice])
    raise ActiveRecord::RecordNotFound if picked_choice.nil?

    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: picked_choice.token,
      picked_choice_word: picked_choice.word,
      is_correct: picked_choice.correct
    )

    redirect_to root_path_with_result(record), notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path_with_state(recalled_word_ids), alert: "Could not save answer."
  end
```

Add this private method above `root_path_with_state`:

```ruby
  def root_path_with_result(record)
    state_params = state_params_for(recalled_word_ids)
    state_params[:result_record_id] = record.id

    root_path(state_params)
  end
```

Then replace `root_path_with_state` with:

```ruby
  def root_path_with_state(word_ids)
    root_path(state_params_for(word_ids))
  end
```

Add this private helper below `root_path_with_state`:

```ruby
  def state_params_for(word_ids)
    state_params = { direction: normalized_direction }
    normalized_word_ids = word_ids.uniq
    state_params[:recalled_word_ids] = normalized_word_ids.join(",") if normalized_word_ids.any?

    state_params
  end
```

- [ ] **Step 4: Run the submission redirect tests**

Run:

```bash
bin/rails test test/controllers/word_question_records_controller_test.rb
```

Expected: all tests in `word_question_records_controller_test.rb` pass.

## Task 2: Add Feedback State To RememberWordsController

**Files:**
- Modify: `test/controllers/remember_words_controller_test.rb`
- Modify: `app/controllers/remember_words_controller.rb`

- [ ] **Step 1: Add tests for result rendering and next-word state**

In `test/controllers/remember_words_controller_test.rb`, add these tests after `"includes current direction in answer form submission"`:

```ruby
  test "renders correct feedback state for a saved correct answer" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("correct_feedback")
    question = create_question_for!(word)
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true
    )

    get root_url(result_record_id: record.id)

    assert_response :success
    assert_select ".feedback-panel.feedback-panel-correct", text: /Correct/
    assert_select ".choice-card.choice-correct", text: word.chinese_meaning
    assert_select "a", "Next word"
  end

  test "renders incorrect feedback state with the correct answer" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("incorrect_feedback")
    question = create_question_for!(word)
    wrong_choice = question.similar_words.first
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "similar_word:#{wrong_choice.id}",
      picked_choice_word: wrong_choice.word,
      is_correct: false
    )

    get root_url(result_record_id: record.id)

    assert_response :success
    assert_select ".feedback-panel.feedback-panel-incorrect", text: /Not quite/
    assert_select ".answer-reveal", text: /Correct answer: #{word.chinese_meaning}/
    assert_select ".choice-card.choice-selected-wrong", text: wrong_choice.chinese_meaning
    assert_select ".choice-card.choice-correct", text: word.chinese_meaning
  end

  test "result state preserves chinese_to_english answer display" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("chinese_feedback")
    question = create_question_for!(word)
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true
    )

    get root_url(direction: "chinese_to_english", result_record_id: record.id)

    assert_response :success
    assert_select "h2", word.chinese_meaning
    assert_select ".choice-card.choice-correct", text: word.word
  end

  test "next word link appends answered word id to recalled word ids" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    previous_word = create_due_word!("previous_recalled")
    word = create_due_word!("next_link")
    question = create_question_for!(word)
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true
    )

    get root_url(recalled_word_ids: previous_word.id.to_s, result_record_id: record.id)

    expected_path = root_path(
      direction: "english_to_chinese",
      recalled_word_ids: "#{previous_word.id},#{word.id}"
    )
    assert_select "a[href='#{expected_path}']", "Next word"
  end

  test "invalid result record id falls back to normal question state" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("invalid_result")
    create_question_for!(word)

    get root_url(result_record_id: "999999")

    assert_response :success
    assert_select "h2", word.word
    assert_select ".feedback-panel", count: 0
  end
```

Replace the completion-state test with:

```ruby
  test "shows completion card when no words are due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)

    get root_url

    assert_response :success
    assert_select ".completion-card"
    assert_match "All caught up", @response.body
    assert_match "You have recalled all words due today.", @response.body
  end
```

- [ ] **Step 2: Run the Remember Words controller test and confirm it fails**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb
```

Expected: failures because result-mode variables and new CSS classes do not exist yet.

- [ ] **Step 3: Implement result-mode preparation in the controller**

In `app/controllers/remember_words_controller.rb`, replace `index` with:

```ruby
  def index
    @direction = normalized_direction
    @recalled_word_ids = recalled_word_ids

    if load_result_state
      return
    end

    due_words = WordsDueForRecall.call(day: Date.current)
    filtered_due_words = WordsDueForRecall.call(day: Date.current, excluding_word_ids: @recalled_word_ids)

    if @recalled_word_ids.any? && filtered_due_words.none?
      redirect_to root_path(direction: @direction), notice: pass_cleared_notice(due_words)
      return
    end

    @question = build_question(filtered_due_words.first)
    @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
  end
```

Add these private methods below `recalled_word_ids`:

```ruby
  def load_result_state
    @result_record = WordQuestionRecord.includes(word_question: :similar_words).find_by(id: params[:result_record_id])
    return false unless @result_record

    @question = @result_record.word_question
    @word_question_record = @result_record
    @selected_choice_token = @result_record.picked_choice_token
    @correct_choice = @question.choices.find(&:correct)
    @next_word_path = root_path(
      direction: @direction,
      recalled_word_ids: (@recalled_word_ids + [ @question.word_id ]).uniq.join(",")
    )

    true
  end

  def result_state?
    @result_record.present?
  end
  helper_method :result_state?

  def choice_display_text(choice)
    english_to_chinese? ? choice.chinese_meaning : choice.word
  end
  helper_method :choice_display_text

  def english_to_chinese?
    @direction == "english_to_chinese"
  end
  helper_method :english_to_chinese?
```

- [ ] **Step 4: Run the Remember Words controller tests**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb
```

Expected: some tests may still fail because the view does not yet render the new classes and text. Controller errors should be gone.

## Task 3: Replace The Remember Words View With Question, Feedback, And Completion States

**Files:**
- Modify: `app/views/remember_words/index.html.erb`
- Modify: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Replace the Remember Words view**

Replace the full contents of `app/views/remember_words/index.html.erb` with:

```erb
<% content_for :title, "Remember Words" %>

<main class="remember-page">
  <header class="remember-header">
    <div>
      <p class="eyebrow">Daily Review</p>
      <h1>Remember Words</h1>
    </div>

    <%= link_to "Add new word", new_word_path, class: "button button-secondary" %>
  </header>

  <%= form_with url: root_path, method: :get, local: true, class: "direction-tabs" do %>
    <label class="direction-tab <%= "direction-tab-active" if @direction == "english_to_chinese" %>">
      <%= radio_button_tag :direction, "english_to_chinese", @direction == "english_to_chinese", onchange: "this.form.submit()" %>
      English -> Chinese
    </label>
    <label class="direction-tab <%= "direction-tab-active" if @direction == "chinese_to_english" %>">
      <%= radio_button_tag :direction, "chinese_to_english", @direction == "chinese_to_english", onchange: "this.form.submit()" %>
      Chinese -> English
    </label>
  <% end %>

  <% if @question.present? %>
    <% prompt_text = english_to_chinese? ? "Choose the correct Chinese meaning." : "Choose the correct English word." %>
    <% question_text = english_to_chinese? ? @question.word.word : @question.word.chinese_meaning %>

    <section class="recall-card">
      <div class="question-block">
        <p class="question-helper"><%= prompt_text %></p>
        <h2><%= question_text %></h2>
      </div>

      <% if result_state? %>
        <% correct = @word_question_record.correct? %>
        <div class="feedback-panel <%= correct ? "feedback-panel-correct" : "feedback-panel-incorrect" %>">
          <p class="feedback-label"><%= correct ? "Correct" : "Not quite" %></p>
          <p class="feedback-copy">
            <%= correct ? "Nice. You chose the right meaning." : "Review the right answer, then continue." %>
          </p>
          <% unless correct %>
            <p class="answer-reveal">Correct answer: <strong><%= choice_display_text(@correct_choice) %></strong></p>
          <% end %>
        </div>

        <div class="choices-list" aria-label="Answer choices">
          <% @question.choices.each do |choice| %>
            <% selected = choice.token == @selected_choice_token %>
            <% correct_choice = choice.correct %>
            <% choice_classes = ["choice-card"] %>
            <% choice_classes << "choice-correct" if correct_choice %>
            <% choice_classes << "choice-selected-wrong" if selected && !correct_choice %>
            <% choice_classes << "choice-selected" if selected && correct_choice %>

            <div class="<%= choice_classes.join(" ") %>">
              <span><%= choice_display_text(choice) %></span>
              <% if correct_choice %>
                <span class="choice-status">Correct answer</span>
              <% elsif selected %>
                <span class="choice-status">Your answer</span>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="actions">
          <%= link_to "Next word", @next_word_path, class: "button button-primary button-large" %>
        </div>
      <% else %>
        <%= form_with model: @word_question_record, url: word_question_records_path, class: "answer-form" do |form| %>
          <%= hidden_field_tag :direction, @direction %>
          <%= hidden_field_tag :recalled_word_ids, @recalled_word_ids.join(",") if @recalled_word_ids.present? %>
          <%= form.hidden_field :word_question_id, value: @question.id %>

          <div class="choices-list">
            <% @question.choices.shuffle.each do |choice| %>
              <label class="choice-card choice-card-input">
                <%= radio_button_tag "word_question_record[picked_choice]", choice.token, false, required: true %>
                <span><%= choice_display_text(choice) %></span>
              </label>
            <% end %>
          </div>

          <div class="actions">
            <%= form.submit "Check answer", class: "button button-primary button-large" %>
          </div>
        <% end %>
      <% end %>
    </section>
  <% else %>
    <section class="completion-card">
      <p class="eyebrow">Daily Review</p>
      <h2>All caught up</h2>
      <p>You have recalled all words due today.</p>
      <%= link_to "Add new word", new_word_path, class: "button button-primary" %>
    </section>
  <% end %>
</main>
```

- [ ] **Step 2: Run Remember Words controller tests**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb
```

Expected: view-related feedback tests pass or show small selector/text mismatches. Fix only mismatches caused by exact class names or capitalization, keeping the approved design intact.

- [ ] **Step 3: Update old selector expectations if needed**

If the existing `"root renders remember words index"` test still expects lowercase text, update it from:

```ruby
assert_select "h1", "Remember words"
```

to:

```ruby
assert_select "h1", "Remember Words"
```

If the existing question-form test expects the prompt in a plain `p`, update it to assert the helper class:

```ruby
assert_select ".question-helper", "Choose the correct Chinese meaning."
```

- [ ] **Step 4: Re-run Remember Words controller tests**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb
```

Expected: all tests in `remember_words_controller_test.rb` pass.

## Task 4: Add Polished Remember Page Styling

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add page, card, choice, and feedback CSS**

Append this CSS to `app/assets/stylesheets/application.css`:

```css
html {
  background: #f8fafc;
}

body {
  color: #0f172a;
  background:
    radial-gradient(circle at top left, rgba(191, 219, 254, 0.45), transparent 34rem),
    #f8fafc;
}

.remember-page {
  max-width: 720px;
  margin: 0 auto;
}

.remember-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1.25rem;
}

.eyebrow {
  margin: 0 0 0.25rem;
  color: #64748b;
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.button-secondary {
  background: #fff;
  border-color: #cbd5e1;
  color: #334155;
}

.direction-tabs {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.35rem;
  margin-bottom: 1rem;
  padding: 0.35rem;
  border: 1px solid #dbe3ef;
  border-radius: 999px;
  background: #eef4fb;
}

.direction-tab {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 0.4rem;
  padding: 0.55rem 0.75rem;
  border-radius: 999px;
  color: #475569;
  cursor: pointer;
  font-weight: 650;
}

.direction-tab input {
  position: absolute;
  opacity: 0;
  pointer-events: none;
}

.direction-tab-active {
  background: #fff;
  color: #0f172a;
  box-shadow: 0 8px 18px rgba(15, 23, 42, 0.08);
}

.recall-card,
.completion-card {
  padding: 2rem;
  border: 1px solid #e2e8f0;
  border-radius: 24px;
  background: #fff;
  box-shadow: 0 24px 70px rgba(15, 23, 42, 0.09);
}

.question-block {
  margin-bottom: 1.5rem;
}

.question-helper {
  margin: 0 0 0.5rem;
  color: #64748b;
  font-weight: 650;
}

.question-block h2 {
  margin: 0;
  color: #0f172a;
  font-size: clamp(2.25rem, 8vw, 4rem);
  line-height: 1.05;
}

.answer-form {
  margin: 0;
}

.choices-list {
  display: grid;
  gap: 0.75rem;
  margin-bottom: 1.25rem;
}

.choice-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  padding: 1rem;
  border: 1px solid #dbe3ef;
  border-radius: 16px;
  background: #fff;
  color: #0f172a;
  font-weight: 650;
}

.choice-card-input {
  cursor: pointer;
  transition: border-color 0.15s ease, background 0.15s ease, box-shadow 0.15s ease;
}

.choice-card-input:hover,
.choice-card-input:focus-within {
  border-color: #60a5fa;
  background: #eff6ff;
  box-shadow: 0 10px 24px rgba(37, 99, 235, 0.1);
}

.choice-card-input input {
  margin: 0;
  accent-color: #1f6feb;
}

.choice-card-input:has(input:checked) {
  border-color: #1f6feb;
  background: #eff6ff;
  box-shadow: 0 10px 24px rgba(37, 99, 235, 0.12);
}

.choice-correct {
  border-color: #16a34a;
  background: #ecfdf3;
  color: #14532d;
}

.choice-selected-wrong {
  border-color: #dc2626;
  background: #fef2f2;
  color: #7f1d1d;
}

.choice-selected {
  box-shadow: 0 10px 24px rgba(22, 163, 74, 0.12);
}

.choice-status {
  flex: 0 0 auto;
  color: inherit;
  font-size: 0.8rem;
  font-weight: 750;
}

.feedback-panel {
  margin-bottom: 1rem;
  padding: 1rem;
  border-radius: 18px;
}

.feedback-panel-correct {
  border: 1px solid #bbf7d0;
  background: #f0fdf4;
  color: #14532d;
}

.feedback-panel-incorrect {
  border: 1px solid #fecaca;
  background: #fff7ed;
  color: #7c2d12;
}

.feedback-label {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 800;
}

.feedback-copy,
.answer-reveal {
  margin: 0.25rem 0 0;
}

.button-large,
input[type="submit"].button-large {
  padding: 0.75rem 1.1rem;
  border-radius: 999px;
  font-weight: 750;
}

.completion-card {
  text-align: center;
}

.completion-card h2 {
  margin-top: 0;
  color: #0f172a;
  font-size: clamp(2rem, 7vw, 3.25rem);
}

@media (max-width: 640px) {
  body {
    margin-top: 1rem;
  }

  .remember-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .remember-header .button,
  .actions .button,
  .actions input[type="submit"].button {
    width: 100%;
    box-sizing: border-box;
    text-align: center;
  }

  .direction-tabs {
    border-radius: 18px;
  }

  .direction-tab {
    border-radius: 14px;
    font-size: 0.9rem;
  }

  .recall-card,
  .completion-card {
    padding: 1.25rem;
    border-radius: 20px;
  }
}
```

- [ ] **Step 2: Check CSS compatibility**

The `:has(input:checked)` selector is supported in current Safari, Chrome, and Firefox. If the project later needs older browser support, replace it with a small Stimulus controller or keep selected styling only after submission. Do not add JavaScript for this task unless a test or browser check proves the selector fails.

- [ ] **Step 3: Read linter diagnostics for changed files**

Use the IDE diagnostics on:

- `app/controllers/remember_words_controller.rb`
- `app/controllers/word_question_records_controller.rb`
- `app/views/remember_words/index.html.erb`
- `app/assets/stylesheets/application.css`

Expected: no new Ruby, ERB, or CSS diagnostics caused by these edits.

## Task 5: Regression Test The Full Flow

**Files:**
- Modify only if tests reveal issues in files already touched.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bin/rails test test/controllers/word_question_records_controller_test.rb test/controllers/remember_words_controller_test.rb
```

Expected: both controller test files pass.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 3: Manual browser check**

Start the Rails server if one is not already running:

```bash
bin/rails server
```

Open the app root and verify:

- The Remember Words page shows a centered card with the direction control and four choices.
- Submitting a correct answer shows `Correct` and a `Next word` action.
- Submitting an incorrect answer shows `Not quite`, marks the wrong answer, and reveals `Correct answer: ...`.
- Clicking `Next word` loads another due word or the completion card.
- On mobile width, answer cards and buttons are easy to tap.

- [ ] **Step 4: Optional commit checkpoint**

Only if the user explicitly asks for a commit, run:

```bash
git add app/controllers/word_question_records_controller.rb app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb app/assets/stylesheets/application.css test/controllers/word_question_records_controller_test.rb test/controllers/remember_words_controller_test.rb docs/superpowers/specs/2026-04-30-remember-word-feedback-interaction-design.md docs/superpowers/plans/2026-04-30-remember-word-feedback-interaction.md
git commit -m "$(cat <<'EOF'
Improve remember word answer feedback flow.

EOF
)"
```

Expected: commit succeeds and `git status` shows no remaining changes for this feature.

## Self-Review Notes

- Spec coverage: The plan covers immediate correctness feedback, revealing the right answer for incorrect responses, an intentional `Next word` action, mobile-first visual design, completion state, invalid result fallback, and focused tests.
- Placeholder scan: No implementation step depends on unspecified helper names; all new helper names are defined in Task 2 before view use in Task 3.
- Type consistency: `result_record_id`, `@selected_choice_token`, `@correct_choice`, `@next_word_path`, `choice_display_text`, and `result_state?` are used consistently between controller and view.
- Scope check: This plan does not change the recall scheduling algorithm or the pending word-question association rewrite. If that rewrite lands first, adapt `@question.word`, `@question.word_id`, `@question.similar_words`, and `@question.choices` to the new choice API while preserving the same interaction contract.
