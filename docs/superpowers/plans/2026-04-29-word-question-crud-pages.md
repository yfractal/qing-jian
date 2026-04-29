# Word Question CRUD Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build admin-style Rails CRUD pages for creating, viewing, editing, listing, and deleting `WordQuestion` records.

**Architecture:** Add a standard RESTful `WordQuestionsController` backed by Rails integration tests. The form accepts one correct `word_id` and exactly three `similar_word_ids`, then the controller rebuilds the associated `SimilarWord` rows through the existing polymorphic association. Views are plain ERB and reuse one `_form` partial for new and edit pages.

**Tech Stack:** Ruby on Rails 8.1, Active Record, ERB, Minitest integration tests, Propshaft CSS.

---

## Scope Check

This plan covers one subsystem: CRUD pages for `WordQuestion`. It does not build the quiz/practice flow or answer recording UI for `WordQuestionRecord`.

## File Structure

- Modify `config/routes.rb`: expose `word_questions` REST routes and make the CRUD index the app root.
- Modify `app/models/word_question.rb`: enable autosave for `similar_words` so update forms can mark old choices for destruction and save replacements atomically.
- Create `app/controllers/word_questions_controller.rb`: implement REST actions and form parameter handling.
- Create `app/views/word_questions/index.html.erb`: list existing questions with correct word and similar word choices.
- Create `app/views/word_questions/show.html.erb`: display one question and its choices.
- Create `app/views/word_questions/new.html.erb`: render the shared form for a new question.
- Create `app/views/word_questions/edit.html.erb`: render the shared form for an existing question.
- Create `app/views/word_questions/_form.html.erb`: shared form with one correct-word select and similar-word checkboxes.
- Modify `app/views/layouts/application.html.erb`: show flash messages and wrap page content in a main container.
- Modify `app/assets/stylesheets/application.css`: add minimal readable styles for CRUD pages, forms, errors, and action links.
- Modify `test/fixtures/similar_words.yml`: make `word_questions(:cat_question)` valid by giving it exactly three similar words.
- Create `test/controllers/word_questions_controller_test.rb`: cover index/show/new/create/edit/update/destroy and validation failure.

---

### Task 1: Routes And Valid Fixture Baseline

**Files:**
- Modify: `config/routes.rb`
- Modify: `test/fixtures/similar_words.yml`
- Create: `test/controllers/word_questions_controller_test.rb`

- [ ] **Step 1: Write the failing route and read tests**

Create `test/controllers/word_questions_controller_test.rb`:

```ruby
require "test_helper"

class WordQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @word_question = word_questions(:cat_question)
  end

  test "gets index" do
    get word_questions_url

    assert_response :success
    assert_select "h1", "Word Questions"
    assert_select "td", text: "cat"
  end

  test "gets show" do
    get word_question_url(@word_question)

    assert_response :success
    assert_select "h1", "Word Question"
    assert_select "li", text: /cat/
  end
end
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: failure or error mentioning an undefined `word_questions_url` route helper.

- [ ] **Step 3: Add REST routes**

Replace `config/routes.rb` with:

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :word_questions

  root "word_questions#index"
end
```

- [ ] **Step 4: Make the existing word question fixture valid**

Replace `test/fixtures/similar_words.yml` with:

```yaml
dog_similar_to_cat_question:
  similar_wordable: cat_question (WordQuestion)
  word: dog

fish_similar_to_cat_question:
  similar_wordable: cat_question (WordQuestion)
  word: fish

bird_similar_to_cat_question:
  similar_wordable: cat_question (WordQuestion)
  word: bird
```

- [ ] **Step 5: Run the test to verify the next failure**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: failure or error mentioning `uninitialized constant WordQuestionsController`.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb test/fixtures/similar_words.yml test/controllers/word_questions_controller_test.rb
git commit -m "test: add word question CRUD route coverage"
```

---

### Task 2: Index And Show Pages

**Files:**
- Create: `app/controllers/word_questions_controller.rb`
- Create: `app/views/word_questions/index.html.erb`
- Create: `app/views/word_questions/show.html.erb`
- Modify: `test/controllers/word_questions_controller_test.rb`

- [ ] **Step 1: Expand the read tests**

Replace `test/controllers/word_questions_controller_test.rb` with:

```ruby
require "test_helper"

class WordQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @word_question = word_questions(:cat_question)
  end

  test "gets index" do
    get word_questions_url

    assert_response :success
    assert_select "h1", "Word Questions"
    assert_select "td", text: "cat"
    assert_select "td", text: /dog, fish, bird/
    assert_select "a", text: "New Word Question"
  end

  test "gets show" do
    get word_question_url(@word_question)

    assert_response :success
    assert_select "h1", "Word Question"
    assert_select "p", text: /Correct word: cat/
    assert_select "li", text: "dog"
    assert_select "li", text: "fish"
    assert_select "li", text: "bird"
    assert_select "a", text: "Edit"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: failure or error mentioning missing `WordQuestionsController` or missing templates.

- [ ] **Step 3: Create the controller read actions**

Create `app/controllers/word_questions_controller.rb`:

```ruby
class WordQuestionsController < ApplicationController
  before_action :set_word_question, only: %i[ show ]

  def index
    @word_questions = WordQuestion.includes(:word, similar_words: :word).order(created_at: :desc)
  end

  def show
  end

  private

  def set_word_question
    @word_question = WordQuestion.includes(:word, similar_words: :word).find(params[:id])
  end
end
```

- [ ] **Step 4: Create the index view**

Create `app/views/word_questions/index.html.erb`:

```erb
<% content_for :title, "Word Questions" %>

<div class="page-header">
  <h1>Word Questions</h1>
  <%= link_to "New Word Question", new_word_question_path, class: "button" %>
</div>

<% if @word_questions.any? %>
  <table>
    <thead>
      <tr>
        <th>Correct word</th>
        <th>Similar words</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <% @word_questions.each do |word_question| %>
        <tr>
          <td><%= word_question.word.english_meaning %></td>
          <td><%= word_question.similar_words.map { |similar_word| similar_word.word.english_meaning }.join(", ") %></td>
          <td class="actions">
            <%= link_to "Show", word_question_path(word_question) %>
            <%= link_to "Edit", edit_word_question_path(word_question) %>
            <%= button_to "Delete", word_question_path(word_question), method: :delete, form: { data: { turbo_confirm: "Delete this word question?" } } %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p>No word questions yet.</p>
<% end %>
```

- [ ] **Step 5: Create the show view**

Create `app/views/word_questions/show.html.erb`:

```erb
<% content_for :title, "Word Question" %>

<div class="page-header">
  <h1>Word Question</h1>
  <div class="actions">
    <%= link_to "Edit", edit_word_question_path(@word_question), class: "button" %>
    <%= link_to "Back", word_questions_path %>
  </div>
</div>

<section class="card">
  <p><strong>Correct word:</strong> <%= @word_question.word.english_meaning %></p>
  <p><strong>Chinese meaning:</strong> <%= @word_question.word.chinese_meaning %></p>

  <h2>Similar Words</h2>
  <ul>
    <% @word_question.similar_words.each do |similar_word| %>
      <li><%= similar_word.word.english_meaning %></li>
    <% end %>
  </ul>
</section>
```

- [ ] **Step 6: Run the read tests to verify they pass**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/word_questions_controller.rb app/views/word_questions/index.html.erb app/views/word_questions/show.html.erb test/controllers/word_questions_controller_test.rb
git commit -m "feat: add word question index and show pages"
```

---

### Task 3: New And Create Pages

**Files:**
- Modify: `app/controllers/word_questions_controller.rb`
- Create: `app/views/word_questions/new.html.erb`
- Create: `app/views/word_questions/_form.html.erb`
- Modify: `test/controllers/word_questions_controller_test.rb`

- [ ] **Step 1: Add failing new and create tests**

Replace `test/controllers/word_questions_controller_test.rb` with:

```ruby
require "test_helper"

class WordQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @word_question = word_questions(:cat_question)
    @cat = words(:cat)
    @dog = words(:dog)
    @fish = words(:fish)
    @bird = words(:bird)
  end

  test "gets index" do
    get word_questions_url

    assert_response :success
    assert_select "h1", "Word Questions"
    assert_select "td", text: "cat"
    assert_select "td", text: /dog, fish, bird/
    assert_select "a", text: "New Word Question"
  end

  test "gets show" do
    get word_question_url(@word_question)

    assert_response :success
    assert_select "h1", "Word Question"
    assert_select "p", text: /Correct word: cat/
    assert_select "li", text: "dog"
    assert_select "li", text: "fish"
    assert_select "li", text: "bird"
    assert_select "a", text: "Edit"
  end

  test "gets new" do
    get new_word_question_url

    assert_response :success
    assert_select "h1", "New Word Question"
    assert_select "select[name='word_question[word_id]']"
    assert_select "input[name='word_question[similar_word_ids][]'][type='checkbox']", 4
  end

  test "creates word question with exactly three similar words" do
    assert_difference("WordQuestion.count", 1) do
      post word_questions_url, params: {
        word_question: {
          word_id: @cat.id,
          similar_word_ids: [ @dog.id, @fish.id, @bird.id ]
        }
      }
    end

    word_question = WordQuestion.order(:created_at).last
    assert_redirected_to word_question_url(word_question)
    assert_equal @cat.id, word_question.word_id
    assert_equal [ @dog.id, @fish.id, @bird.id ].sort, word_question.similar_words.map(&:word_id).sort
  end

  test "does not create word question with fewer than three similar words" do
    assert_no_difference("WordQuestion.count") do
      post word_questions_url, params: {
        word_question: {
          word_id: @cat.id,
          similar_word_ids: [ @dog.id, @fish.id ]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".error-message", text: "Similar words must have exactly 3"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: failure or error mentioning missing `new` action, missing `create` action, or missing `new` template.

- [ ] **Step 3: Implement new and create actions**

Replace `app/controllers/word_questions_controller.rb` with:

```ruby
class WordQuestionsController < ApplicationController
  before_action :set_word_question, only: %i[ show ]
  before_action :set_words, only: %i[ new create ]

  def index
    @word_questions = WordQuestion.includes(:word, similar_words: :word).order(created_at: :desc)
  end

  def show
  end

  def new
    @word_question = WordQuestion.new
  end

  def create
    @word_question = WordQuestion.new(word_question_params)
    build_similar_words(@word_question)

    if @word_question.save
      redirect_to @word_question, notice: "Word question was created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_word_question
    @word_question = WordQuestion.includes(:word, similar_words: :word).find(params[:id])
  end

  def set_words
    @words = Word.order(:english_meaning)
  end

  def word_question_params
    params.require(:word_question).permit(:word_id)
  end

  def selected_similar_word_ids
    Array(params.dig(:word_question, :similar_word_ids)).reject(&:blank?)
  end

  def build_similar_words(word_question)
    selected_similar_word_ids.each do |word_id|
      word_question.similar_words.build(word_id: word_id)
    end
  end
end
```

- [ ] **Step 4: Create the new view**

Create `app/views/word_questions/new.html.erb`:

```erb
<% content_for :title, "New Word Question" %>

<div class="page-header">
  <h1>New Word Question</h1>
  <%= link_to "Back", word_questions_path %>
</div>

<%= render "form", word_question: @word_question, words: @words %>
```

- [ ] **Step 5: Create the shared form partial**

Create `app/views/word_questions/_form.html.erb`:

```erb
<% selected_similar_word_ids = word_question.similar_words.reject(&:marked_for_destruction?).map(&:word_id) %>

<%= form_with model: word_question, class: "form" do |form| %>
  <% if word_question.errors.any? %>
    <div class="errors">
      <h2><%= pluralize(word_question.errors.count, "error") %> prevented this word question from being saved:</h2>
      <ul>
        <% word_question.errors.full_messages.each do |message| %>
          <li class="error-message"><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="field">
    <%= form.label :word_id, "Correct word" %>
    <%= form.collection_select :word_id, words, :id, :english_meaning, { prompt: "Choose the correct word" }, required: true %>
  </div>

  <fieldset class="field">
    <legend>Similar words</legend>
    <p class="hint">Choose exactly 3 similar words.</p>
    <%= hidden_field_tag "word_question[similar_word_ids][]", "" %>

    <div class="checkbox-list">
      <% words.each do |word| %>
        <label>
          <%= check_box_tag "word_question[similar_word_ids][]", word.id, selected_similar_word_ids.include?(word.id) %>
          <%= word.english_meaning %> (<%= word.chinese_meaning %>)
        </label>
      <% end %>
    </div>
  </fieldset>

  <div class="actions">
    <%= form.submit %>
  </div>
<% end %>
```

- [ ] **Step 6: Run new and create tests to verify they pass**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: 5 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/word_questions_controller.rb app/views/word_questions/new.html.erb app/views/word_questions/_form.html.erb test/controllers/word_questions_controller_test.rb
git commit -m "feat: add word question creation page"
```

---

### Task 4: Edit, Update, And Destroy Pages

**Files:**
- Modify: `app/models/word_question.rb`
- Modify: `app/controllers/word_questions_controller.rb`
- Create: `app/views/word_questions/edit.html.erb`
- Modify: `test/controllers/word_questions_controller_test.rb`

- [ ] **Step 1: Add failing edit, update, and destroy tests**

Replace `test/controllers/word_questions_controller_test.rb` with:

```ruby
require "test_helper"

class WordQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @word_question = word_questions(:cat_question)
    @cat = words(:cat)
    @dog = words(:dog)
    @fish = words(:fish)
    @bird = words(:bird)
  end

  test "gets index" do
    get word_questions_url

    assert_response :success
    assert_select "h1", "Word Questions"
    assert_select "td", text: "cat"
    assert_select "td", text: /dog, fish, bird/
    assert_select "a", text: "New Word Question"
  end

  test "gets show" do
    get word_question_url(@word_question)

    assert_response :success
    assert_select "h1", "Word Question"
    assert_select "p", text: /Correct word: cat/
    assert_select "li", text: "dog"
    assert_select "li", text: "fish"
    assert_select "li", text: "bird"
    assert_select "a", text: "Edit"
  end

  test "gets new" do
    get new_word_question_url

    assert_response :success
    assert_select "h1", "New Word Question"
    assert_select "select[name='word_question[word_id]']"
    assert_select "input[name='word_question[similar_word_ids][]'][type='checkbox']", 4
  end

  test "creates word question with exactly three similar words" do
    assert_difference("WordQuestion.count", 1) do
      post word_questions_url, params: {
        word_question: {
          word_id: @cat.id,
          similar_word_ids: [ @dog.id, @fish.id, @bird.id ]
        }
      }
    end

    word_question = WordQuestion.order(:created_at).last
    assert_redirected_to word_question_url(word_question)
    assert_equal @cat.id, word_question.word_id
    assert_equal [ @dog.id, @fish.id, @bird.id ].sort, word_question.similar_words.map(&:word_id).sort
  end

  test "does not create word question with fewer than three similar words" do
    assert_no_difference("WordQuestion.count") do
      post word_questions_url, params: {
        word_question: {
          word_id: @cat.id,
          similar_word_ids: [ @dog.id, @fish.id ]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".error-message", text: "Similar words must have exactly 3"
  end

  test "gets edit" do
    get edit_word_question_url(@word_question)

    assert_response :success
    assert_select "h1", "Edit Word Question"
    assert_select "input[name='word_question[similar_word_ids][]'][checked='checked']", 3
  end

  test "updates word question and replaces similar words" do
    patch word_question_url(@word_question), params: {
      word_question: {
        word_id: @dog.id,
        similar_word_ids: [ @cat.id, @fish.id, @bird.id ]
      }
    }

    assert_redirected_to word_question_url(@word_question)
    @word_question.reload
    assert_equal @dog.id, @word_question.word_id
    assert_equal [ @cat.id, @fish.id, @bird.id ].sort, @word_question.similar_words.map(&:word_id).sort
  end

  test "does not update word question with fewer than three similar words" do
    patch word_question_url(@word_question), params: {
      word_question: {
        word_id: @dog.id,
        similar_word_ids: [ @cat.id, @fish.id ]
      }
    }

    assert_response :unprocessable_entity
    assert_select ".error-message", text: "Similar words must have exactly 3"
    @word_question.reload
    assert_equal @cat.id, @word_question.word_id
    assert_equal [ @dog.id, @fish.id, @bird.id ].sort, @word_question.similar_words.map(&:word_id).sort
  end

  test "destroys word question" do
    assert_difference("WordQuestion.count", -1) do
      delete word_question_url(@word_question)
    end

    assert_redirected_to word_questions_url
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: failure or error mentioning missing `edit`, `update`, or `destroy` actions.

- [ ] **Step 3: Enable autosave on similar words**

Replace `app/models/word_question.rb` with:

```ruby
class WordQuestion < ApplicationRecord
  belongs_to :word
  has_many :similar_words, as: :similar_wordable, dependent: :destroy, autosave: true
  has_many :word_question_records, dependent: :destroy

  validates :word, presence: true
  validate :exactly_three_similar_words

  def choices
    [word] + similar_words.map(&:word)
  end

  private

  def exactly_three_similar_words
    return if similar_words.reject(&:marked_for_destruction?).size == 3

    errors.add(:similar_words, "must have exactly 3")
  end
end
```

- [ ] **Step 4: Implement edit, update, and destroy actions**

Replace `app/controllers/word_questions_controller.rb` with:

```ruby
class WordQuestionsController < ApplicationController
  before_action :set_word_question, only: %i[ show edit update destroy ]
  before_action :set_words, only: %i[ new create edit update ]

  def index
    @word_questions = WordQuestion.includes(:word, similar_words: :word).order(created_at: :desc)
  end

  def show
  end

  def new
    @word_question = WordQuestion.new
  end

  def create
    @word_question = WordQuestion.new(word_question_params)
    build_similar_words(@word_question)

    if @word_question.save
      redirect_to @word_question, notice: "Word question was created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    ActiveRecord::Base.transaction do
      @word_question.assign_attributes(word_question_params)
      replace_similar_words(@word_question)

      if @word_question.save
        redirect_to @word_question, notice: "Word question was updated."
      else
        raise ActiveRecord::Rollback
      end
    end

    return if performed?

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @word_question.destroy

    redirect_to word_questions_path, notice: "Word question was deleted.", status: :see_other
  end

  private

  def set_word_question
    @word_question = WordQuestion.includes(:word, similar_words: :word).find(params[:id])
  end

  def set_words
    @words = Word.order(:english_meaning)
  end

  def word_question_params
    params.require(:word_question).permit(:word_id)
  end

  def selected_similar_word_ids
    Array(params.dig(:word_question, :similar_word_ids)).reject(&:blank?)
  end

  def build_similar_words(word_question)
    selected_similar_word_ids.each do |word_id|
      word_question.similar_words.build(word_id: word_id)
    end
  end

  def replace_similar_words(word_question)
    word_question.similar_words.each(&:mark_for_destruction)
    build_similar_words(word_question)
  end
end
```

- [ ] **Step 5: Create the edit view**

Create `app/views/word_questions/edit.html.erb`:

```erb
<% content_for :title, "Edit Word Question" %>

<div class="page-header">
  <h1>Edit Word Question</h1>
  <div class="actions">
    <%= link_to "Show", word_question_path(@word_question) %>
    <%= link_to "Back", word_questions_path %>
  </div>
</div>

<%= render "form", word_question: @word_question, words: @words %>
```

- [ ] **Step 6: Run CRUD tests to verify they pass**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: 9 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/models/word_question.rb app/controllers/word_questions_controller.rb app/views/word_questions/edit.html.erb test/controllers/word_questions_controller_test.rb
git commit -m "feat: add word question editing and deletion"
```

---

### Task 5: Layout, Styling, And Full Verification

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add flash and page wrapper to the layout**

Replace `app/views/layouts/application.html.erb` with:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Qing Jian" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="Qing Jian">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <%# Enable PWA manifest for installable apps (make sure to enable in config/routes.rb too!) %>
    <%#= tag.link rel: "manifest", href: pwa_manifest_path(format: :json) %>

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%# Includes all stylesheet files in app/assets/stylesheets %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
  </head>

  <body>
    <main class="container">
      <% flash.each do |type, message| %>
        <div class="flash flash-<%= type %>"><%= message %></div>
      <% end %>

      <%= yield %>
    </main>
  </body>
</html>
```

- [ ] **Step 2: Add minimal CRUD page styles**

Replace `app/assets/stylesheets/application.css` with:

```css
/*
 * This is a manifest file that'll be compiled into application.css.
 *
 * With Propshaft, assets are served efficiently without preprocessing steps. You can still include
 * application-wide styles in this file, but keep in mind that CSS precedence will follow the standard
 * cascading order, meaning styles declared later in the document or manifest will override earlier ones,
 * depending on specificity.
 *
 * Consider organizing styles into separate files for maintainability.
 */

body {
  color: #1f2937;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  margin: 0;
}

a {
  color: #2563eb;
}

.container {
  margin: 0 auto;
  max-width: 960px;
  padding: 2rem;
}

.page-header {
  align-items: center;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  margin-bottom: 1.5rem;
}

.actions {
  align-items: center;
  display: flex;
  gap: 0.75rem;
}

.button,
input[type="submit"],
button {
  background: #2563eb;
  border: 0;
  border-radius: 0.375rem;
  color: white;
  cursor: pointer;
  display: inline-block;
  font: inherit;
  padding: 0.5rem 0.75rem;
  text-decoration: none;
}

table {
  border-collapse: collapse;
  width: 100%;
}

th,
td {
  border-bottom: 1px solid #e5e7eb;
  padding: 0.75rem;
  text-align: left;
}

.card,
.form {
  border: 1px solid #e5e7eb;
  border-radius: 0.5rem;
  padding: 1rem;
}

.field {
  margin-bottom: 1rem;
}

.field label,
legend {
  font-weight: 600;
}

select {
  display: block;
  font: inherit;
  margin-top: 0.25rem;
  min-width: 16rem;
  padding: 0.4rem;
}

fieldset {
  border: 1px solid #e5e7eb;
  border-radius: 0.5rem;
}

.hint {
  color: #6b7280;
  margin-top: 0.25rem;
}

.checkbox-list {
  display: grid;
  gap: 0.5rem;
}

.checkbox-list label {
  font-weight: 400;
}

.errors {
  background: #fef2f2;
  border: 1px solid #fecaca;
  border-radius: 0.5rem;
  color: #991b1b;
  margin-bottom: 1rem;
  padding: 1rem;
}

.flash {
  border-radius: 0.5rem;
  margin-bottom: 1rem;
  padding: 0.75rem 1rem;
}

.flash-notice {
  background: #ecfdf5;
  color: #065f46;
}
```

- [ ] **Step 3: Run focused CRUD tests**

Run:

```bash
bin/rails test test/controllers/word_questions_controller_test.rb
```

Expected: 9 runs, 0 failures, 0 errors.

- [ ] **Step 4: Run model tests**

Run:

```bash
bin/rails test test/models/word_question_test.rb test/models/word_test.rb test/models/similar_word_test.rb test/models/word_question_record_test.rb
```

Expected: all model tests pass with 0 failures and 0 errors.

- [ ] **Step 5: Run the full test suite**

Run:

```bash
bin/rails test
```

Expected: the full suite passes with 0 failures and 0 errors.

- [ ] **Step 6: Run Rails style checks**

Run:

```bash
bin/rubocop
```

Expected: no offenses.

- [ ] **Step 7: Commit**

```bash
git add app/views/layouts/application.html.erb app/assets/stylesheets/application.css
git commit -m "style: polish word question CRUD pages"
```

---

## Self-Review

- Spec coverage: the plan implements standard admin CRUD for `WordQuestion`, including index, show, new, create, edit, update, destroy, validation failure rendering, and exactly-three similar word selection.
- Placeholder scan: the plan contains concrete file paths, commands, expected failures, expected passing outputs, and full code blocks for every code change.
- Type consistency: route helpers use `word_questions_*` and `word_question_*`; controller parameters use `word_question[:word_id]` and `word_question[:similar_word_ids]`; model associations use existing `WordQuestion`, `Word`, and `SimilarWord` names.
