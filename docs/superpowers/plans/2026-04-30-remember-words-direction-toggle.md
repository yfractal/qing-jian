# Remember Words Direction Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users choose recall direction on the Remember words page (`english_to_chinese` or `chinese_to_english`), with `english_to_chinese` as the default.

**Architecture:** Keep direction state in URL params (`direction`) beside existing pass-state (`recalled_word_ids`) so refresh/redirect stays consistent. `RememberWordsController#index` validates and exposes the current direction; the view renders a direction selector and question/choice labels based on that direction. `WordQuestionRecordsController#create` preserves both `direction` and `recalled_word_ids` on success/failure redirects.

**Tech Stack:** Ruby on Rails 8, Minitest integration tests, ERB views, existing `WordsDueForRecall`, `FindOrCreateWordQuestion`, and `WordQuestionRecord` flow.

---

## File Structure

- Modify: `app/controllers/remember_words_controller.rb` — parse/validate direction with default and expose helpers used by view.
- Modify: `app/views/remember_words/index.html.erb` — add direction toggle form controls and direction-aware prompt/labels.
- Modify: `app/controllers/word_question_records_controller.rb` — preserve `direction` in redirects with existing recalled IDs.
- Modify: `test/controllers/remember_words_controller_test.rb` — cover default direction, explicit direction rendering, and hidden-field carry-through.
- Modify: `test/controllers/word_question_records_controller_test.rb` — cover redirect URLs preserving `direction`.

### Task 1: Add Direction Param Contract With Default

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write failing controller tests for default and explicit direction**

Add these tests in `test/controllers/remember_words_controller_test.rb`:

```ruby
  test "defaults to english_to_chinese direction" do
    word = create_due_word!("default_direction")
    create_question_for!(word)

    get root_url

    assert_response :success
    assert_select "input[type='radio'][name='direction'][value='english_to_chinese'][checked='checked']"
    assert_select "p", "Choose the correct Chinese meaning."
    assert_select "h2", word.word
  end

  test "supports chinese_to_english direction from params" do
    word = create_due_word!("explicit_direction")
    create_question_for!(word)

    get root_url(direction: "chinese_to_english")

    assert_response :success
    assert_select "input[type='radio'][name='direction'][value='chinese_to_english'][checked='checked']"
    assert_select "p", "Choose the correct English word."
    assert_select "h2", word.chinese_meaning
  end

  test "falls back to english_to_chinese for invalid direction" do
    word = create_due_word!("invalid_direction")
    create_question_for!(word)

    get root_url(direction: "invalid")

    assert_response :success
    assert_select "input[type='radio'][name='direction'][value='english_to_chinese'][checked='checked']"
    assert_select "h2", word.word
  end
```

- [ ] **Step 2: Run controller tests to verify failure**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: FAIL because current page always renders Chinese prompt + English choices and has no direction controls.

- [ ] **Step 3: Implement validated direction with default in controller**

Update `app/controllers/remember_words_controller.rb`:

```ruby
class RememberWordsController < ApplicationController
  DIRECTIONS = %w[english_to_chinese chinese_to_english].freeze

  def index
    @direction = normalized_direction
    @recalled_word_ids = recalled_word_ids
    due_words = WordsDueForRecall.call(day: Date.current)
    filtered_due_words = WordsDueForRecall.call(day: Date.current, excluding_word_ids: @recalled_word_ids)

    if @recalled_word_ids.any? && filtered_due_words.none?
      redirect_to root_path(direction: @direction), notice: pass_cleared_notice(due_words)
      return
    end

    @question = build_question(filtered_due_words.first)
    @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
  end

  private

  def normalized_direction
    return params[:direction] if DIRECTIONS.include?(params[:direction])

    "english_to_chinese"
  end

  # existing recalled_word_ids/pass_cleared_notice/build_question methods remain
end
```

- [ ] **Step 4: Re-run controller tests**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: still FAIL on view assertions until Task 2 updates the template.

- [ ] **Step 5: Commit after Task 2 passes**

Do not commit yet; bundle controller + view + tests in one direction-toggle commit.

### Task 2: Render Direction Toggle and Direction-Aware Question/Choices

**Files:**
- Modify: `app/views/remember_words/index.html.erb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Add failing assertion for hidden direction in answer form**

Add this test in `test/controllers/remember_words_controller_test.rb`:

```ruby
  test "includes current direction in answer form submission" do
    word = create_due_word!("carry_direction")
    create_question_for!(word)

    get root_url(direction: "chinese_to_english")

    assert_response :success
    assert_select "input[type='hidden'][name='direction'][value='chinese_to_english']"
  end
```

- [ ] **Step 2: Run controller tests to verify failure**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: FAIL because direction controls/hidden field are not in the view.

- [ ] **Step 3: Update remember page template for both directions**

Replace `app/views/remember_words/index.html.erb` with:

```erb
<% content_for :title, "Remember words" %>

<h1>Remember words</h1>

<p class="toolbar">
  <%= link_to "Add new word", new_word_path, class: "button button-primary" %>
</p>

<%= form_with url: root_path, method: :get, local: true, class: "direction-form" do %>
  <label>
    <%= radio_button_tag :direction, "english_to_chinese", @direction == "english_to_chinese", onchange: "this.form.submit()" %>
    English to Chinese
  </label>
  <label>
    <%= radio_button_tag :direction, "chinese_to_english", @direction == "chinese_to_english", onchange: "this.form.submit()" %>
    Chinese to English
  </label>
<% end %>

<% if @question.present? %>
  <section class="recall-card">
    <h2><%= @direction == "english_to_chinese" ? @question.word.word : @question.word.chinese_meaning %></h2>
    <p><%= @direction == "english_to_chinese" ? "Choose the correct Chinese meaning." : "Choose the correct English word." %></p>

    <%= form_with model: @word_question_record, url: word_question_records_path do |form| %>
      <%= hidden_field_tag :direction, @direction %>
      <%= hidden_field_tag :recalled_word_ids, @recalled_word_ids.join(",") if @recalled_word_ids.present? %>
      <%= form.hidden_field :word_question_id, value: @question.id %>

      <% @question.choices.shuffle.each do |choice| %>
        <label>
          <%= radio_button_tag "word_question_record[picked_word_id]", choice.id, false, required: true %>
          <%= @direction == "english_to_chinese" ? choice.chinese_meaning : choice.word %>
        </label><br>
      <% end %>

      <%= form.submit "Submit answer", class: "button button-primary" %>
    <% end %>
  </section>
<% else %>
  <p>Congratulations! You have recalled all words due today.</p>
<% end %>
```

- [ ] **Step 4: Run remember page controller tests**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb test/controllers/remember_words_controller_test.rb
git commit -m "feat: add remember direction toggle with english-to-chinese default"
```

### Task 3: Preserve Direction Through Answer Redirects

**Files:**
- Modify: `app/controllers/word_question_records_controller.rb`
- Test: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Write failing redirect tests for direction preservation**

Add these tests in `test/controllers/word_question_records_controller_test.rb`:

```ruby
  test "preserves english_to_chinese direction on successful redirect" do
    post word_question_records_url, params: {
      direction: "english_to_chinese",
      word_question_record: {
        word_question_id: @question.id,
        picked_word_id: @word.id
      }
    }

    assert_redirected_to root_url(direction: "english_to_chinese", recalled_word_ids: @word.id.to_s)
  end

  test "preserves chinese_to_english direction on failure redirect" do
    post word_question_records_url, params: {
      direction: "chinese_to_english",
      word_question_record: {
        word_question_id: "missing",
        picked_word_id: @word.id
      }
    }

    assert_redirected_to root_url(direction: "chinese_to_english")
    assert_equal "Could not save answer.", flash[:alert]
  end
```

- [ ] **Step 2: Run record controller tests to verify failure**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: FAIL because redirect helper currently drops `direction`.

- [ ] **Step 3: Update redirect helper to include validated direction**

Update `app/controllers/word_question_records_controller.rb`:

```ruby
class WordQuestionRecordsController < ApplicationController
  DIRECTIONS = %w[english_to_chinese chinese_to_english].freeze

  def create
    question = WordQuestion.find(record_params[:word_question_id])
    picked_word = Word.find(record_params[:picked_word_id])

    WordQuestionRecord.create!(
      word_question: question,
      picked_word: picked_word,
      is_correct: picked_word.id == question.word_id
    )

    redirect_to root_path_with_state(recalled_word_ids + [question.word_id]), notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path_with_state(recalled_word_ids), alert: "Could not save answer."
  end

  private

  def normalized_direction
    return params[:direction] if DIRECTIONS.include?(params[:direction])

    "english_to_chinese"
  end

  def root_path_with_state(word_ids)
    state_params = { direction: normalized_direction }
    normalized_word_ids = word_ids.uniq
    state_params[:recalled_word_ids] = normalized_word_ids.join(",") if normalized_word_ids.any?
    root_path(state_params)
  end

  # existing record_params and recalled_word_ids methods remain
end
```

- [ ] **Step 4: Re-run record controller tests**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/word_question_records_controller.rb test/controllers/word_question_records_controller_test.rb
git commit -m "feat: preserve remember direction through answer redirects"
```

### Task 4: End-to-End Verification

**Files:**
- Test: `test/controllers/remember_words_controller_test.rb`
- Test: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Run focused controller suite**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
bin/rails test
```

Expected: PASS.

- [ ] **Step 3: Manual browser verification**

Run:

```bash
bin/rails server
```

Expected: server starts and prints local URL (for example `http://127.0.0.1:3000`).

Manual checks:
1. Open `/` with no params; confirm `English to Chinese` is selected.
2. Confirm question title is the English word text and options show Chinese meanings.
3. Switch to `Chinese to English`; confirm question title becomes Chinese meaning and options show English words.
4. Submit an answer in both directions; confirm redirected URL preserves `direction=...`.
5. Confirm redirected URL also preserves/appends `recalled_word_ids` as before.

- [ ] **Step 4: Commit verification-only fixes (if any)**

```bash
git add app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb app/controllers/word_question_records_controller.rb test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb
git commit -m "fix: complete remember direction toggle verification fixes"
```

If no fixes are needed, do not create an empty commit.

## Self-Review

- Spec coverage: Plan adds two-direction selection, keeps `english_to_chinese` default, renders direction-specific prompt/content, and preserves direction across answer redirects.
- Placeholder scan: No TODO/TBD placeholders; each implementation step includes concrete code and commands.
- Type consistency: Uses one shared param contract (`direction` values `english_to_chinese` / `chinese_to_english`) across remember page render, form submit, and redirect URL builders.

Plan complete and saved to `docs/superpowers/plans/2026-04-30-remember-words-direction-toggle.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
