# Remember Word Index Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the remember-word page the app index, load today’s first due word into a question form, and save recall answers that redirect back to the same page.

**Architecture:** Add a dedicated `RememberWordsController#index` that orchestrates `WordsDueForRecall` and `FindOrCreateWordQuestion` to prepare one `WordQuestion` and one `WordQuestionRecord` form object. Add `WordQuestionRecordsController#create` to persist the selected answer and compute correctness server-side before redirecting to the remember index. Keep `WordsController` for word CRUD and expose “Add new word” from the remember page.

**Tech Stack:** Ruby on Rails 8, Minitest (integration/controller tests), ERB views, existing service objects (`WordsDueForRecall`, `FindOrCreateWordQuestion`)

---

## File Structure

- Create: `app/controllers/remember_words_controller.rb` — index page orchestration for recall question loading.
- Create: `app/controllers/word_question_records_controller.rb` — form submit endpoint for answer recording.
- Create: `app/views/remember_words/index.html.erb` — page UI with “Add new word” button and recall question form.
- Modify: `config/routes.rb` — make remember page root and add create route for records.
- Modify: `test/controllers/words_controller_test.rb` — adjust old root/index assumptions if needed.
- Create: `test/controllers/remember_words_controller_test.rb` — verifies index behavior and rendered page states.
- Create: `test/controllers/word_question_records_controller_test.rb` — verifies record creation, correctness, and redirect behavior.

### Task 1: Route Remember Page as Root

**Files:**
- Modify: `config/routes.rb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write the failing route/controller test for remember root**

```ruby
require "test_helper"

class RememberWordsControllerTest < ActionDispatch::IntegrationTest
  test "root renders remember words index" do
    get root_url
    assert_response :success
    assert_select "h1", "Remember words"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: FAIL with missing route or missing `RememberWordsController`.

- [ ] **Step 3: Update routes with new root and records create endpoint**

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "remember_words#index"

  resources :words do
    collection do
      post :lookup
    end
  end

  resources :word_question_records, only: :create
end
```

- [ ] **Step 4: Add minimal remember controller/index to satisfy route**

```ruby
class RememberWordsController < ApplicationController
  def index; end
end
```

```erb
<% content_for :title, "Remember words" %>

<h1>Remember words</h1>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb test/controllers/remember_words_controller_test.rb
git commit -m "feat: route root to remember words index"
```

### Task 2: Build Remember Index Question Loading Flow

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Modify: `app/views/remember_words/index.html.erb`
- Test: `test/controllers/remember_words_controller_test.rb`

- [ ] **Step 1: Write failing tests for service-driven question loading and add-word button**

```ruby
require "test_helper"

class RememberWordsControllerTest < ActionDispatch::IntegrationTest
  test "shows add new word button" do
    get root_url
    assert_response :success
    assert_select "a", "Add new word"
  end

  test "loads first due word question and renders choices form" do
    due_word = words(:cat)
    question = word_questions(:cat_question)
    question.similar_words.create!(word: words(:dog))
    question.similar_words.create!(word: words(:bird))
    question.similar_words.create!(word: Word.create!(word: "fox", english_meaning: "fox", chinese_meaning: "狐"))

    WordsDueForRecall.stub(:call, [due_word]) do
      FindOrCreateWordQuestion.any_instance.stub(:call, question) do
        get root_url
      end
    end

    assert_response :success
    assert_select "form[action='#{word_question_records_path}']"
    assert_match due_word.chinese_meaning, @response.body
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: FAIL because index does not call services or render form.

- [ ] **Step 3: Implement index orchestration with due words + question service**

```ruby
class RememberWordsController < ApplicationController
  def index
    due_words = WordsDueForRecall.call(day: Date.current)
    @question = build_question(due_words.first)
    @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
  end

  private

  def build_question(word)
    return nil unless word

    FindOrCreateWordQuestion.new.call(word: word)
  end
end
```

- [ ] **Step 4: Implement index view with add-word CTA and question form**

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
  <p>No words due today. Nice work!</p>
<% end %>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/remember_words_controller.rb app/views/remember_words/index.html.erb test/controllers/remember_words_controller_test.rb
git commit -m "feat: load first due question on remember index"
```

### Task 3: Implement Record Submission + Redirect Back to Remember Page

**Files:**
- Create: `app/controllers/word_question_records_controller.rb`
- Modify: `app/views/remember_words/index.html.erb`
- Test: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Write failing create action tests (persist + redirect to root)**

```ruby
require "test_helper"

class WordQuestionRecordsControllerTest < ActionDispatch::IntegrationTest
  test "creates a correct record and redirects to remember index" do
    question = word_questions(:cat_question)

    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: question.id,
          picked_word_id: question.word_id
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal true, record.is_correct
    assert_redirected_to root_url
  end

  test "creates an incorrect record and redirects to remember index" do
    question = word_questions(:cat_question)
    wrong_word = words(:dog)

    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: question.id,
          picked_word_id: wrong_word.id
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal false, record.is_correct
    assert_redirected_to root_url
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: FAIL with missing `WordQuestionRecordsController#create`.

- [ ] **Step 3: Implement create action with correctness computed server-side**

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

    redirect_to root_path, notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Could not save answer."
  end

  private

  def record_params
    params.require(:word_question_record).permit(:word_question_id, :picked_word_id)
  end
end
```

- [ ] **Step 4: Ensure form posts only required params**

```erb
<%= form_with model: @word_question_record, url: word_question_records_path do |form| %>
  <%= form.hidden_field :word_question_id, value: @question.id %>

  <% @question.choices.shuffle.each do |choice| %>
    <label>
      <%= radio_button_tag "word_question_record[picked_word_id]", choice.id, false, required: true %>
      <%= choice.word %>
    </label><br>
  <% end %>

  <%= form.submit "Submit answer", class: "button button-primary" %>
<% end %>
```

- [ ] **Step 5: Run tests to verify it passes**

Run: `bin/rails test test/controllers/word_question_records_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/word_question_records_controller.rb app/views/remember_words/index.html.erb test/controllers/word_question_records_controller_test.rb
git commit -m "feat: save recall answer and redirect to remember index"
```

### Task 4: Regression Coverage for Existing Words Pages

**Files:**
- Modify: `test/controllers/words_controller_test.rb`

- [ ] **Step 1: Write/adjust test to ensure words list still works at `/words`**

```ruby
test "should get words index from /words" do
  get words_url
  assert_response :success
  assert_select "h1", "Words"
end
```

- [ ] **Step 2: Run test to verify current behavior (or failure if route assumptions changed)**

Run: `bin/rails test test/controllers/words_controller_test.rb`
Expected: PASS (or targeted failure if previous tests rely on old root behavior).

- [ ] **Step 3: Remove old assumptions tied to root being words index (if present)**

```ruby
# Keep words index assertions using words_url rather than root_url.
# Do not assert root behavior in WordsController tests.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/words_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/controllers/words_controller_test.rb
git commit -m "test: keep words controller coverage independent from root route"
```

### Task 5: Full Verification Pass

**Files:**
- Test: `test/controllers/remember_words_controller_test.rb`
- Test: `test/controllers/word_question_records_controller_test.rb`
- Test: `test/controllers/words_controller_test.rb`
- Test: `test/models/word_question_record_test.rb`
- Test: `test/services/words_due_for_recall_test.rb`

- [ ] **Step 1: Run targeted suite for this feature**

Run: `bin/rails test test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb test/controllers/words_controller_test.rb`
Expected: PASS.

- [ ] **Step 2: Run domain regression tests for recall and question record**

Run: `bin/rails test test/models/word_question_record_test.rb test/services/words_due_for_recall_test.rb test/services/find_or_create_word_question_test.rb`
Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run: `bin/rails test`
Expected: PASS.

- [ ] **Step 4: Commit final verification snapshot (if any test-related edits were made)**

```bash
git add .
git commit -m "test: verify remember-word index flow end-to-end"
```

## Self-Review

- **Spec coverage check:** Covered index page switch, “Add new word” CTA on remember page, service composition (`WordsDueForRecall` then `FindOrCreateWordQuestion` for first due word), record form creation from question, and post-submit redirect back to remember index.
- **Placeholder scan:** No TODO/TBD placeholders; each coding step includes concrete snippets, commands, and expected outcomes.
- **Type consistency check:** Uses existing models/fields consistently (`WordQuestionRecord.word_question_id`, `picked_word_id`, computed `is_correct`, service call signatures already present in codebase).
