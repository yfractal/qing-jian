# Word Question Association Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `word_questions.word_id` and `similar_words.word_question_id`, then rewrite the quiz domain so `WordQuestion` associates with both `words` and `similar_words` through an explicit join model.

**Architecture:** Introduce `WordQuestionChoice` as the single ownership link between a question and its four choices (one correct `Word`, three incorrect `SimilarWord`). `WordQuestion` will no longer directly belong to `Word` or directly own `SimilarWord`; instead it owns `word_question_choices`, and choice records point to either a `word` or `similar_word` with role metadata (`correct` / `distractor`). Existing generation, answer-submission, and recall-state logic will be rewritten to read/write through this new relation.

**Tech Stack:** Ruby on Rails 8.1, Active Record migrations, Minitest, fixtures, existing LLM clients and jobs.

---

I'm using the writing-plans skill to create the implementation plan.

## File Structure

- Create: `db/migrate/20260430112000_create_word_question_choices.rb` - join table between `word_questions`, `words`, and `similar_words`.
- Create: `db/migrate/20260430112100_backfill_word_question_choices_and_drop_old_fks.rb` - data migration + drop `word_questions.word_id` and `similar_words.word_question_id`.
- Modify: `db/schema.rb` - regenerated schema after migration.
- Create: `app/models/word_question_choice.rb` - new join model and validations.
- Modify: `app/models/word_question.rb` - move ownership to choices and expose derived APIs for target word and distractors.
- Modify: `app/models/word.rb` - replace direct `has_many :word_questions` with association through `word_question_choices`.
- Modify: `app/models/similar_word.rb` - remove direct `belongs_to :word_question`, add association through choices.
- Modify: `app/services/find_or_create_word_question.rb` - create `WordQuestionChoice` records instead of writing `word_id`/`word_question_id`.
- Modify: `app/jobs/create_batch_word_questions_job.rb` - same rewrite for batch creation path.
- Modify: `app/controllers/remember_words_controller.rb` - resolve due words and build question using the new correct-choice link.
- Modify: `app/controllers/word_question_records_controller.rb` - evaluate correctness by resolved choice identity.
- Modify: `app/views/remember_words/index.html.erb` - read choices through new APIs (no direct `question.word` assumptions).
- Modify fixtures:
  - `test/fixtures/word_questions.yml`
  - `test/fixtures/similar_words.yml`
  - `test/fixtures/word_question_records.yml`
  - Create: `test/fixtures/word_question_choices.yml`
- Modify tests:
  - `test/models/word_question_test.rb`
  - Create: `test/models/word_question_choice_test.rb`
  - `test/services/find_or_create_word_question_test.rb`
  - `test/jobs/create_batch_word_questions_job_test.rb`
  - `test/controllers/remember_words_controller_test.rb`
  - `test/controllers/word_question_records_controller_test.rb`
  - `test/services/words_due_for_recall_test.rb`

### Task 1: Add Join Model for Question Choices

**Files:**
- Create: `app/models/word_question_choice.rb`
- Create: `test/models/word_question_choice_test.rb`
- Create: `db/migrate/20260430112000_create_word_question_choices.rb`

- [ ] **Step 1: Write failing model tests for the new join model**

Create `test/models/word_question_choice_test.rb`:

```ruby
require "test_helper"

class WordQuestionChoiceTest < ActiveSupport::TestCase
  test "valid correct choice with word" do
    choice = WordQuestionChoice.new(
      word_question: word_questions(:cat_question),
      word: words(:cat),
      role: "correct"
    )

    assert choice.valid?
  end

  test "valid distractor choice with similar_word" do
    choice = WordQuestionChoice.new(
      word_question: word_questions(:cat_question),
      similar_word: similar_words(:dog_choice_for_cat_question),
      role: "distractor"
    )

    assert choice.valid?
  end

  test "invalid when both word and similar_word are set" do
    choice = WordQuestionChoice.new(
      word_question: word_questions(:cat_question),
      word: words(:cat),
      similar_word: similar_words(:dog_choice_for_cat_question),
      role: "distractor"
    )

    assert_not choice.valid?
    assert_includes choice.errors[:base], "choose either word or similar_word"
  end

  test "invalid when neither word nor similar_word is set" do
    choice = WordQuestionChoice.new(
      word_question: word_questions(:cat_question),
      role: "distractor"
    )

    assert_not choice.valid?
    assert_includes choice.errors[:base], "choice source is required"
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bin/rails test test/models/word_question_choice_test.rb`
Expected: FAIL because `WordQuestionChoice` table/model do not exist.

- [ ] **Step 3: Add migration to create join table**

Create `db/migrate/20260430112000_create_word_question_choices.rb`:

```ruby
class CreateWordQuestionChoices < ActiveRecord::Migration[8.1]
  def change
    create_table :word_question_choices do |t|
      t.references :word_question, null: false, foreign_key: true
      t.references :word, null: true, foreign_key: true
      t.references :similar_word, null: true, foreign_key: true
      t.string :role, null: false

      t.timestamps
    end

    add_index :word_question_choices, [ :word_question_id, :role ], name: "idx_word_question_choices_question_role"
  end
end
```

- [ ] **Step 4: Implement the join model**

Create `app/models/word_question_choice.rb`:

```ruby
class WordQuestionChoice < ApplicationRecord
  ROLES = %w[correct distractor].freeze

  belongs_to :word_question
  belongs_to :word, optional: true
  belongs_to :similar_word, optional: true

  validates :role, presence: true, inclusion: { in: ROLES }
  validate :exactly_one_choice_source
  validate :role_matches_choice_source

  private

  def exactly_one_choice_source
    if word.present? && similar_word.present?
      errors.add(:base, "choose either word or similar_word")
    elsif word.blank? && similar_word.blank?
      errors.add(:base, "choice source is required")
    end
  end

  def role_matches_choice_source
    return if word.blank? && similar_word.blank?

    if role == "correct" && word.blank?
      errors.add(:role, "correct role requires word")
    end
    if role == "distractor" && similar_word.blank?
      errors.add(:role, "distractor role requires similar_word")
    end
  end
end
```

- [ ] **Step 5: Re-run tests**

Run: `bin/rails db:migrate && bin/rails test test/models/word_question_choice_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260430112000_create_word_question_choices.rb app/models/word_question_choice.rb test/models/word_question_choice_test.rb db/schema.rb
git commit -m "feat: add word_question_choices join model"
```

### Task 2: Backfill Join Data and Drop Old Foreign Keys

**Files:**
- Create: `db/migrate/20260430112100_backfill_word_question_choices_and_drop_old_fks.rb`
- Modify: `db/schema.rb`

- [ ] **Step 1: Write migration safety test expectation (schema-level check)**

Add assertion in an existing migration/integration test file (or create `test/integration/word_question_schema_test.rb`):

```ruby
require "test_helper"

class WordQuestionSchemaTest < ActiveSupport::TestCase
  test "legacy foreign keys are removed from question and similar word tables" do
    question_columns = ActiveRecord::Base.connection.columns(:word_questions).map(&:name)
    similar_columns = ActiveRecord::Base.connection.columns(:similar_words).map(&:name)

    assert_not_includes question_columns, "word_id"
    assert_not_includes similar_columns, "word_question_id"
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bin/rails test test/integration/word_question_schema_test.rb`
Expected: FAIL because both columns still exist.

- [ ] **Step 3: Create data migration with backfill + cleanup**

Create `db/migrate/20260430112100_backfill_word_question_choices_and_drop_old_fks.rb`:

```ruby
class BackfillWordQuestionChoicesAndDropOldFks < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      INSERT INTO word_question_choices (word_question_id, word_id, role, created_at, updated_at)
      SELECT id, word_id, 'correct', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM word_questions
      WHERE word_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      INSERT INTO word_question_choices (word_question_id, similar_word_id, role, created_at, updated_at)
      SELECT word_question_id, id, 'distractor', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM similar_words
      WHERE word_question_id IS NOT NULL
    SQL

    remove_foreign_key :word_questions, :words
    remove_column :word_questions, :word_id

    remove_foreign_key :similar_words, :word_questions
    remove_column :similar_words, :word_question_id
  end

  def down
    add_reference :word_questions, :word, foreign_key: true
    add_reference :similar_words, :word_question, foreign_key: true

    execute <<~SQL.squish
      UPDATE word_questions
      SET word_id = c.word_id
      FROM word_question_choices c
      WHERE c.word_question_id = word_questions.id
        AND c.role = 'correct'
    SQL

    execute <<~SQL.squish
      UPDATE similar_words
      SET word_question_id = c.word_question_id
      FROM word_question_choices c
      WHERE c.similar_word_id = similar_words.id
        AND c.role = 'distractor'
    SQL
  end
end
```

- [ ] **Step 4: Run migrations and schema test**

Run: `bin/rails db:migrate && bin/rails test test/integration/word_question_schema_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260430112100_backfill_word_question_choices_and_drop_old_fks.rb test/integration/word_question_schema_test.rb db/schema.rb
git commit -m "refactor: drop direct question foreign keys after backfill"
```

### Task 3: Rewrite Associations and Core Domain Methods

**Files:**
- Modify: `app/models/word_question.rb`
- Modify: `app/models/word.rb`
- Modify: `app/models/similar_word.rb`
- Modify: `app/services/find_or_create_word_question.rb`
- Modify: `app/jobs/create_batch_word_questions_job.rb`
- Modify: `test/models/word_question_test.rb`
- Modify: `test/services/find_or_create_word_question_test.rb`
- Modify: `test/jobs/create_batch_word_questions_job_test.rb`
- Create: `test/fixtures/word_question_choices.yml`
- Modify: `test/fixtures/word_questions.yml`
- Modify: `test/fixtures/similar_words.yml`

- [ ] **Step 1: Write failing model/service tests for new association contract**

In `test/models/word_question_test.rb`, add:

```ruby
test "target_word resolves from correct choice" do
  question = word_questions(:cat_question)
  assert_equal words(:cat), question.target_word
end

test "distractor_similar_words resolves three similar words from join rows" do
  question = word_questions(:cat_question)
  assert_equal 3, question.distractor_similar_words.size
end
```

In `test/services/find_or_create_word_question_test.rb`, add:

```ruby
test "creates one correct choice and three distractor choices" do
  word = Word.create!(word: "otter", english_meaning: "A semiaquatic mammal.", chinese_meaning: "水獭")
  service = build_service([
    [ "seal", "A marine mammal.", "海豹" ],
    [ "beaver", "A broad-tailed rodent.", "海狸" ],
    [ "mink", "A small carnivorous mammal.", "水貂" ]
  ])

  question = service.call(word: word)

  assert_equal 1, question.word_question_choices.where(role: "correct").count
  assert_equal 3, question.word_question_choices.where(role: "distractor").count
end
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
bin/rails test test/models/word_question_test.rb test/services/find_or_create_word_question_test.rb
```

Expected: FAIL because current models/services still rely on direct foreign keys.

- [ ] **Step 3: Rewrite model associations**

Update `app/models/word_question.rb`:

```ruby
class WordQuestion < ApplicationRecord
  Choice = Data.define(:token, :word, :english_meaning, :chinese_meaning, :correct)

  has_many :word_question_choices, dependent: :destroy
  has_many :words, through: :word_question_choices
  has_many :similar_words, through: :word_question_choices
  has_many :word_question_records, dependent: :destroy

  validate :has_exactly_one_correct_choice
  validate :has_exactly_three_distractors

  def target_word
    word_question_choices.find_by(role: "correct")&.word
  end

  def distractor_similar_words
    word_question_choices.where(role: "distractor").includes(:similar_word).map(&:similar_word)
  end
end
```

Update `app/models/word.rb`:

```ruby
class Word < ApplicationRecord
  has_many :word_question_choices, dependent: :destroy
  has_many :word_questions, through: :word_question_choices
  has_one :word_recall_state, dependent: :destroy
  # ... keep existing validations/callback ...
end
```

Update `app/models/similar_word.rb`:

```ruby
class SimilarWord < ApplicationRecord
  has_many :word_question_choices, dependent: :destroy
  has_many :word_questions, through: :word_question_choices

  validates :word, :english_meaning, :chinese_meaning, presence: true
end
```

- [ ] **Step 4: Rewrite creation paths to fill join rows**

In `app/services/find_or_create_word_question.rb`, replace direct construction with:

```ruby
question = WordQuestion.create!
question.word_question_choices.create!(word: word, role: "correct")
similar_results.each do |result|
  similar = SimilarWord.create!(
    word: result.word,
    english_meaning: result.english_meaning,
    chinese_meaning: result.chinese_meaning
  )
  question.word_question_choices.create!(similar_word: similar, role: "distractor")
end
question
```

In `app/jobs/create_batch_word_questions_job.rb`, apply the same pattern inside transaction for each word.

- [ ] **Step 5: Update fixtures for join-backed data**

Create `test/fixtures/word_question_choices.yml`:

```yaml
cat_correct_choice:
  word_question: cat_question
  word: cat
  role: correct

cat_dog_distractor:
  word_question: cat_question
  similar_word: dog_choice_for_cat_question
  role: distractor

cat_fish_distractor:
  word_question: cat_question
  similar_word: fish_choice_for_cat_question
  role: distractor

cat_bird_distractor:
  word_question: cat_question
  similar_word: bird_choice_for_cat_question
  role: distractor
```

Also remove `word_id` from `test/fixtures/word_questions.yml`, and remove `word_question` linkage from `test/fixtures/similar_words.yml`.

- [ ] **Step 6: Re-run focused model/service/job tests**

Run:

```bash
bin/rails test test/models/word_question_choice_test.rb test/models/word_question_test.rb test/services/find_or_create_word_question_test.rb test/jobs/create_batch_word_questions_job_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/models/word_question.rb app/models/word.rb app/models/similar_word.rb app/services/find_or_create_word_question.rb app/jobs/create_batch_word_questions_job.rb test/models/word_question_test.rb test/services/find_or_create_word_question_test.rb test/jobs/create_batch_word_questions_job_test.rb test/fixtures/word_questions.yml test/fixtures/similar_words.yml test/fixtures/word_question_choices.yml
git commit -m "refactor: route word question relations through choices join"
```

### Task 4: Rewrite Remember Flow and Answer Evaluation

**Files:**
- Modify: `app/controllers/remember_words_controller.rb`
- Modify: `app/controllers/word_question_records_controller.rb`
- Modify: `app/views/remember_words/index.html.erb`
- Modify: `test/controllers/remember_words_controller_test.rb`
- Modify: `test/controllers/word_question_records_controller_test.rb`
- Modify: `test/services/words_due_for_recall_test.rb`
- Modify: `test/fixtures/word_question_records.yml`

- [ ] **Step 1: Write failing controller tests for new query/evaluation paths**

In `test/controllers/remember_words_controller_test.rb`, add:

```ruby
test "renders question using target word from correct choice" do
  get root_url
  assert_response :success
  assert_select "h2", /cat|猫/
end
```

In `test/controllers/word_question_records_controller_test.rb`, add:

```ruby
test "marks answer correct when picked token matches correct choice token" do
  correct_token = "word:#{words(:cat).id}"

  post word_question_records_url, params: {
    word_question_record: {
      word_question_id: word_questions(:cat_question).id,
      picked_choice: correct_token
    }
  }

  assert_equal true, WordQuestionRecord.order(:id).last.is_correct
end
```

- [ ] **Step 2: Run controller tests to verify failure**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb
```

Expected: FAIL until controllers/view stop assuming `question.word`.

- [ ] **Step 3: Rewrite controllers to use choice-derived target**

In `app/controllers/remember_words_controller.rb`, ensure question lookup for a due word uses join:

```ruby
def build_question(word)
  return nil unless word

  FindOrCreateWordQuestion.new.call(word: word)
end
```

And in view rendering references, replace `@question.word` reads with `@question.target_word`.

In `app/controllers/word_question_records_controller.rb`, correctness should be:

```ruby
picked_choice = question.choice_for_token(record_params[:picked_choice])
is_correct = picked_choice&.correct
```

Save record using token/word snapshot as currently done.

- [ ] **Step 4: Update tests and recall-state integration**

In `test/services/words_due_for_recall_test.rb`, replace any `question.word` assumptions with `question.target_word`.

In `test/fixtures/word_question_records.yml`, ensure records remain token-based and do not reference removed columns.

- [ ] **Step 5: Run focused and full test suites**

Run:

```bash
bin/rails test test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb test/services/words_due_for_recall_test.rb
bin/rails test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/remember_words_controller.rb app/controllers/word_question_records_controller.rb app/views/remember_words/index.html.erb test/controllers/remember_words_controller_test.rb test/controllers/word_question_records_controller_test.rb test/services/words_due_for_recall_test.rb test/fixtures/word_question_records.yml
git commit -m "rewrite remember flow for join-based word question associations"
```

## Self-Review

- Spec coverage: Plan removes `word_questions.word_id` and `similar_words.word_question_id`, adds explicit association between `word_questions` and both `words`/`similar_words` through `word_question_choices`, and rewrites related services/jobs/controllers/tests.
- Placeholder scan: No `TODO`/`TBD` placeholders; every task contains concrete files, code, and commands.
- Type consistency: The same choice-token and choice-role model is used across migrations, models, services, controllers, fixtures, and tests.

Plan complete and saved to `docs/superpowers/plans/2026-04-30-word-question-association-rewrite.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
