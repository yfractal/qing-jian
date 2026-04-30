# Today Words Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Today Words page that lists today’s review words with reviewed/not-reviewed status, and make the Remember Progress card on the index page navigate to this page.

**Architecture:** Keep `RememberWordsController#index` as the quiz entry page and add a second action (`today`) for list rendering. Build one query method in a service object to return the same “today workload” scope used by progress (due today words plus words answered correctly today), then annotate each row with reviewed status. Reuse existing visual language (cards, gradients, rounded controls, typography) by extending current stylesheet classes instead of introducing a separate design system.

**Tech Stack:** Ruby on Rails (controllers, routes, ActiveRecord, Minitest), ERB templates, CSS

---

## File Structure

- Modify: `config/routes.rb`
  - Add a route for the new today page under the existing remember words flow.
- Modify: `app/controllers/remember_words_controller.rb`
  - Add a `today` action and shared query helpers for progress/list consistency.
- Create: `app/services/today_words_progress.rb`
  - Centralize “today words” set and reviewed-status derivation.
- Create: `app/views/remember_words/today.html.erb`
  - Build list UI showing word, pronunciation, Chinese meaning, and reviewed badge.
- Modify: `app/views/remember_words/index.html.erb`
  - Turn the progress card into a link to the today page.
- Modify: `app/assets/stylesheets/application.css`
  - Add styles for linked progress card, list layout, reviewed status chips, and empty state.
- Modify: `test/controllers/remember_words_controller_test.rb`
  - Add request/UI tests for today page rendering and progress-card link behavior.
- Create: `test/services/today_words_progress_test.rb`
  - Add unit tests for reviewed/not-reviewed data computation.

### Task 1: Add Failing Service Tests for Today Workload and Status

**Files:**
- Create: `test/services/today_words_progress_test.rb`
- Test: `test/services/today_words_progress_test.rb`

- [ ] **Step 1: Write failing test for today workload union (due + remembered today)**

```ruby
require "test_helper"

class TodayWordsProgressTest < ActiveSupport::TestCase
  test "today words include due words and remembered-today words" do
    due_word = create_word!("due_word")
    remembered_word = create_word!("remembered_word")

    due_word.word_recall_state.update!(due_day: Date.current)
    remembered_word.word_recall_state.update!(due_day: Date.current + 5.days)

    question = create_question_for!(remembered_word)
    WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{remembered_word.id}",
      picked_choice_word: remembered_word.word,
      is_correct: true,
      created_at: Time.zone.now
    )

    result = TodayWordsProgress.call(day: Date.current)
    result_ids = result.map { |item| item[:word].id }

    assert_includes result_ids, due_word.id
    assert_includes result_ids, remembered_word.id
  end
end
```

- [ ] **Step 2: Write failing test for reviewed and not-reviewed flags**

```ruby
test "marks reviewed when word has a correct record today" do
  reviewed_word = create_word!("reviewed")
  pending_word = create_word!("pending")
  reviewed_word.word_recall_state.update!(due_day: Date.current)
  pending_word.word_recall_state.update!(due_day: Date.current)

  reviewed_question = create_question_for!(reviewed_word)
  WordQuestionRecord.create!(
    word_question: reviewed_question,
    picked_choice_token: "word:#{reviewed_word.id}",
    picked_choice_word: reviewed_word.word,
    is_correct: true,
    created_at: Time.zone.now
  )

  result = TodayWordsProgress.call(day: Date.current)
  reviewed_item = result.find { |item| item[:word].id == reviewed_word.id }
  pending_item = result.find { |item| item[:word].id == pending_word.id }

  assert_equal true, reviewed_item[:reviewed]
  assert_equal false, pending_item[:reviewed]
end
```

- [ ] **Step 3: Run service test file and confirm failure**

Run: `bin/rails test test/services/today_words_progress_test.rb`

Expected:
- FAIL with `uninitialized constant TodayWordsProgress` (or missing method errors)

- [ ] **Step 4: Commit failing tests**

```bash
git add test/services/today_words_progress_test.rb
git commit -m "test: define today words progress service behavior"
```

### Task 2: Implement TodayWordsProgress Service (Minimal Pass)

**Files:**
- Create: `app/services/today_words_progress.rb`
- Test: `test/services/today_words_progress_test.rb`

- [ ] **Step 1: Add service implementation**

```ruby
class TodayWordsProgress
  class << self
    def call(day: Date.current)
      day_range = day.in_time_zone.all_day
      due_words = WordsDueForRecall.call(day: day).includes(:word_recall_state)

      reviewed_word_ids = WordQuestionRecord
        .joins(:word_question)
        .where(is_correct: true, created_at: day_range)
        .distinct
        .pluck("word_questions.word_id")

      remembered_today_words = Word.where(id: reviewed_word_ids)
      words = (due_words.to_a + remembered_today_words.to_a).uniq(&:id)
      words.sort_by! { |word| word.word.downcase }

      words.map do |word|
        {
          word: word,
          reviewed: reviewed_word_ids.include?(word.id)
        }
      end
    end
  end
end
```

- [ ] **Step 2: Add private test helpers used by service tests**

```ruby
private

def create_word!(name)
  Word.create!(
    word: "#{name}_#{SecureRandom.hex(4)}",
    english_meaning: "#{name} english",
    chinese_meaning: "#{name} chinese",
    pronunciation: "/#{name}/"
  ).tap do |word|
    word.word_recall_state.update!(due_day: Date.current + 30.days)
  end
end

def create_question_for!(word)
  question = WordQuestion.new(word: word)
  3.times do |idx|
    question.similar_words.build(
      word: "#{word.word}_choice_#{idx}",
      english_meaning: "choice #{idx}",
      chinese_meaning: "choice #{idx}"
    )
  end
  question.save!
  question
end
```

- [ ] **Step 3: Run service tests and verify pass**

Run: `bin/rails test test/services/today_words_progress_test.rb`

Expected:
- PASS all tests in `TodayWordsProgressTest`

- [ ] **Step 4: Commit service implementation**

```bash
git add app/services/today_words_progress.rb test/services/today_words_progress_test.rb
git commit -m "feat: add today words progress query service"
```

### Task 3: Add Today Page Route and Controller Tests (Failing First)

**Files:**
- Modify: `config/routes.rb`
- Modify: `test/controllers/remember_words_controller_test.rb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write failing controller test for today page contents**

```ruby
test "today page lists word, pronunciation, chinese meaning, and review status" do
  WordRecallState.update_all(due_day: Date.current + 100.days)
  reviewed_word = create_due_word!("reviewed_item")
  pending_word = create_due_word!("pending_item")
  reviewed_word.update!(pronunciation: "/reviewed/")
  pending_word.update!(pronunciation: "/pending/")
  reviewed_question = create_question_for!(reviewed_word)

  WordQuestionRecord.create!(
    word_question: reviewed_question,
    picked_choice_token: "word:#{reviewed_word.id}",
    picked_choice_word: reviewed_word.word,
    is_correct: true,
    created_at: Time.zone.now
  )

  get today_words_url

  assert_response :success
  assert_select "h1", "Today Words"
  assert_select ".today-word-item", minimum: 2
  assert_select ".today-word-status-reviewed", text: /Reviewed/
  assert_select ".today-word-status-pending", text: /Not reviewed/
  assert_match reviewed_word.chinese_meaning, @response.body
  assert_match "/reviewed/", @response.body
end
```

- [ ] **Step 2: Write failing controller test for progress-card click-through link**

```ruby
test "remember progress card links to today words page" do
  get root_url

  assert_response :success
  assert_select "a.remember-progress-card[href='#{today_words_path}']"
  assert_select "a.remember-progress-card", text: /Remembered \d+ \/ \d+/
end
```

- [ ] **Step 3: Add route for today page**

```ruby
Rails.application.routes.draw do
  root "remember_words#index"
  get "today_words", to: "remember_words#today", as: :today_words
  # ... existing routes ...
end
```

- [ ] **Step 4: Run controller tests and verify expected failures**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected:
- Initial failures for missing `today` action/template and missing progress-card anchor

- [ ] **Step 5: Commit failing request tests + route scaffold**

```bash
git add config/routes.rb test/controllers/remember_words_controller_test.rb
git commit -m "test: define today words page routing and entry link"
```

### Task 4: Implement Today Action and Today Page UI

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Create: `app/views/remember_words/today.html.erb`
- Modify: `app/views/remember_words/index.html.erb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Add `today` action in controller**

```ruby
def today
  @today_words = TodayWordsProgress.call(day: Date.current)
  @reviewed_count = @today_words.count { |item| item[:reviewed] }
  @total_count = @today_words.size
  @pending_count = @total_count - @reviewed_count
end
```

- [ ] **Step 2: Convert progress card section into link on index page**

```erb
<%= link_to today_words_path, class: "remember-progress-card remember-progress-card-link", "aria-label": "Open today words progress list" do %>
  <p class="eyebrow">Remember Progress</p>
  <p class="remember-progress-main">Remembered <%= @remembered_count %> / <%= @remember_total_count %></p>
  <p class="remember-progress-meta">Need to remember <%= @remaining_count %></p>
  <div class="remember-progress-track" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="<%= @progress_percent %>">
    <div class="remember-progress-fill" style="width: <%= @progress_percent %>%"></div>
  </div>
<% end %>
```

- [ ] **Step 3: Create today page template with list rows and status chips**

```erb
<% content_for :title, "Today Words" %>

<main class="remember-page today-words-page">
  <header class="remember-header">
    <div>
      <p class="eyebrow">Daily Review</p>
      <h1>Today Words</h1>
      <p class="remember-progress-meta">Reviewed <%= @reviewed_count %> / <%= @total_count %> · Pending <%= @pending_count %></p>
    </div>
    <%= link_to "Back to Review", root_path, class: "button button-secondary" %>
  </header>

  <% if @today_words.any? %>
    <section class="today-words-list" aria-label="Today word list">
      <% @today_words.each do |item| %>
        <% word = item[:word] %>
        <article class="today-word-item">
          <div class="today-word-main">
            <p class="today-word-text"><%= word.word %></p>
            <p class="today-word-pronunciation"><%= word.pronunciation.presence || "-" %></p>
          </div>
          <p class="today-word-meaning"><%= word.chinese_meaning %></p>
          <span class="today-word-status <%= item[:reviewed] ? "today-word-status-reviewed" : "today-word-status-pending" %>">
            <%= item[:reviewed] ? "Reviewed" : "Not reviewed" %>
          </span>
        </article>
      <% end %>
    </section>
  <% else %>
    <section class="completion-card">
      <p class="eyebrow">Daily Review</p>
      <h2>No words today</h2>
      <p>You have no review workload for today.</p>
    </section>
  <% end %>
</main>
```

- [ ] **Step 4: Run controller tests to verify page and link behavior**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`

Expected:
- PASS for new today page and link tests
- PASS for existing Remember Words flow tests

- [ ] **Step 5: Commit controller/view implementation**

```bash
git add app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb app/views/remember_words/today.html.erb
git commit -m "feat: add today words page and progress card navigation"
```

### Task 5: Apply Beautiful Styling Matching Index Visual Language

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Add linked-card interaction styles**

```css
.remember-progress-card-link {
  display: block;
  text-decoration: none;
  color: inherit;
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}

.remember-progress-card-link:hover,
.remember-progress-card-link:focus-visible {
  transform: translateY(-2px);
  box-shadow: 0 14px 28px rgba(37, 99, 235, 0.14);
}
```

- [ ] **Step 2: Add today words list styles**

```css
.today-words-list {
  display: grid;
  gap: 0.8rem;
}

.today-word-item {
  display: grid;
  grid-template-columns: 1.5fr 1.5fr auto;
  gap: 0.75rem;
  align-items: center;
  padding: 1rem;
  border: 1px solid #dbe3ef;
  border-radius: 16px;
  background: linear-gradient(180deg, #ffffff 0%, #f8fbff 100%);
}

.today-word-text {
  margin: 0;
  color: #0f172a;
  font-size: 1.1rem;
  font-weight: 760;
}

.today-word-pronunciation,
.today-word-meaning {
  margin: 0;
  color: #475569;
  font-weight: 620;
}
```

- [ ] **Step 3: Add reviewed/not-reviewed badge styles and mobile rules**

```css
.today-word-status {
  justify-self: end;
  padding: 0.3rem 0.65rem;
  border-radius: 999px;
  font-size: 0.8rem;
  font-weight: 760;
}

.today-word-status-reviewed {
  background: #ecfdf3;
  color: #166534;
  border: 1px solid #86efac;
}

.today-word-status-pending {
  background: #eff6ff;
  color: #1d4ed8;
  border: 1px solid #93c5fd;
}

@media (max-width: 640px) {
  .today-word-item {
    grid-template-columns: 1fr;
    gap: 0.4rem;
  }

  .today-word-status {
    justify-self: start;
  }
}
```

- [ ] **Step 4: Run targeted tests**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb test/services/today_words_progress_test.rb`

Expected:
- PASS all tests

- [ ] **Step 5: Commit styling**

```bash
git add app/assets/stylesheets/application.css test/controllers/remember_words_controller_test.rb test/services/today_words_progress_test.rb
git commit -m "style: add today words list design matching review page"
```

### Task 6: Final Verification

**Files:**
- Modify: none (unless fixes are needed)
- Test: `test/controllers/remember_words_controller_test.rb`, `test/services/today_words_progress_test.rb`

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`

Expected:
- PASS with no regressions

- [ ] **Step 2: Manual browser verification**

Run: `bin/rails server`

Verify:
- Root page still shows Remember Progress text and styling.
- Clicking `Remembered X / Y` card opens `/today_words`.
- Today page rows display word, pronunciation, Chinese meaning.
- Reviewed words show `Reviewed`; others show `Not reviewed`.
- Mobile layout stacks cleanly and remains readable.

- [ ] **Step 3: Commit final fixes if any were needed**

```bash
git add <any-updated-files>
git commit -m "chore: finalize today words page verification"
```

## Self-Review

### 1. Spec coverage
- Requirement: Add a “today words” page listing today words.
  - Covered by Task 3 route/tests and Task 4 template/controller.
- Requirement: Distinguish reviewed vs not reviewed.
  - Covered by Task 1 service tests + Task 2 service + Task 4 status chips.
- Requirement: Each item shows word, pronunciation, Chinese meaning.
  - Covered by Task 3 failing test + Task 4 ERB row structure.
- Requirement: Follow index-page design style and keep it beautiful.
  - Covered by Task 5 style extension that reuses existing card palette/shape/spacing.
- Requirement: Clicking `Remembered 29 / 30` redirects to this page.
  - Covered by Task 3 link test + Task 4 progress-card link conversion.

### 2. Placeholder scan
- No `TODO`/`TBD` placeholders.
- Every code-changing step includes concrete code blocks.
- Every validation step includes concrete command and expected outcome.

### 3. Type/signature consistency
- New service API is consistently `TodayWordsProgress.call(day: Date.current)`.
- Data contract from service is consistently `{ word:, reviewed: }`.
- Route helper naming is consistent across tests/views: `today_words_path` / `today_words_url`.
