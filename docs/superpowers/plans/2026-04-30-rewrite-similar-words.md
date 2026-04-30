# Rewrite Similar Words Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `similar_words` so it no longer stores `similar_wordable_id`, `similar_wordable_type`, or `word_id`, and instead stores the same user-facing fields as `words`: `word`, `english_meaning`, and `chinese_meaning`.

**Architecture:** `SimilarWord` becomes a real distractor-choice row owned by a `WordQuestion`, not a polymorphic join to `Word`. Because incorrect answer choices will no longer be `Word` records, answer submission will use an explicit choice token and `WordQuestionRecord` will store the picked choice text instead of a `picked_word_id` foreign key.

**Tech Stack:** Rails 8.1, Active Record migrations/models, ERB views, Minitest fixtures and integration tests.

---

## File Structure

- Modify `db/migrate/20260429004710_create_similar_words.rb`: replace the polymorphic and `word` references with `word_question_id`, `word`, `english_meaning`, and `chinese_meaning`.
- Create `db/migrate/20260430104000_rewrite_similar_words_as_word_choices.rb`: migrate an existing dev/test database from the old join-shaped table to the new word-shaped table.
- Create `db/migrate/20260430104100_rewrite_word_question_records_picked_choice.rb`: replace `word_question_records.picked_word_id` with choice snapshot fields.
- Modify `db/schema.rb`: regenerate through `bin/rails db:migrate` after migrations run.
- Modify `app/models/similar_word.rb`: make it belong to `word_question` and validate the word-shaped fields.
- Modify `app/models/word.rb`: remove the obsolete polymorphic `has_many :similar_words`.
- Modify `app/models/word_question.rb`: own `similar_words`, validate exactly three, and expose typed choice objects for the view/controller.
- Modify `app/models/word_question_record.rb`: validate picked choice snapshot fields instead of `picked_word`.
- Modify `app/services/find_or_create_word_question.rb`: build `SimilarWord` rows directly from LLM results without creating `Word` rows.
- Modify `app/jobs/create_batch_word_questions_job.rb`: build `SimilarWord` rows directly from batched LLM results.
- Modify `app/controllers/word_question_records_controller.rb`: accept `picked_choice`, resolve it against the question, and persist the selected choice snapshot.
- Modify `app/views/remember_words/index.html.erb`: submit choice tokens rather than raw `Word` ids.
- Modify fixtures:
  - `test/fixtures/similar_words.yml`
  - `test/fixtures/word_question_records.yml`
- Modify tests:
  - `test/models/similar_word_test.rb`
  - `test/models/word_question_test.rb`
  - `test/models/word_question_record_test.rb`
  - `test/services/find_or_create_word_question_test.rb`
  - `test/jobs/create_batch_word_questions_job_test.rb`
  - `test/controllers/word_question_records_controller_test.rb`
  - `test/services/words_due_for_recall_test.rb`

## Behavioral Notes

- `similar_words` will contain `word`, `english_meaning`, `chinese_meaning`, `created_at`, and `updated_at`, plus `word_question_id` so each question can keep its three generated distractors.
- Similar words are not promoted into the main `words` table.
- The correct answer remains the `WordQuestion#word`.
- The three incorrect choices are `SimilarWord` rows attached to the question.
- Answer submissions use tokens like `word:12` and `similar_word:34` to avoid collisions between ids from different tables.
- `WordQuestionRecord` stores `picked_choice_token` and `picked_choice_word` so old recall-state behavior can still use `is_correct` and `word_question.word`.

---

### Task 1: Rewrite SimilarWord Schema and Model

**Files:**
- Modify: `db/migrate/20260429004710_create_similar_words.rb`
- Create: `db/migrate/20260430104000_rewrite_similar_words_as_word_choices.rb`
- Modify: `app/models/similar_word.rb`
- Modify: `app/models/word.rb`
- Modify: `test/fixtures/similar_words.yml`
- Modify: `test/models/similar_word_test.rb`

- [ ] **Step 1: Write the failing SimilarWord model test**

Replace `test/models/similar_word_test.rb` with:

```ruby
require "test_helper"

class SimilarWordTest < ActiveSupport::TestCase
  test "valid with a word question and word-shaped fields" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      word: "kitten",
      english_meaning: "A young cat.",
      chinese_meaning: "小猫"
    )

    assert similar_word.valid?
  end

  test "invalid without word_question" do
    similar_word = SimilarWord.new(
      word: "kitten",
      english_meaning: "A young cat.",
      chinese_meaning: "小猫"
    )

    assert_not similar_word.valid?
    assert_includes similar_word.errors[:word_question], "must exist"
  end

  test "invalid without word" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      english_meaning: "A young cat.",
      chinese_meaning: "小猫"
    )

    assert_not similar_word.valid?
    assert_includes similar_word.errors[:word], "can't be blank"
  end

  test "invalid without english meaning" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      word: "kitten",
      chinese_meaning: "小猫"
    )

    assert_not similar_word.valid?
    assert_includes similar_word.errors[:english_meaning], "can't be blank"
  end

  test "invalid without chinese meaning" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      word: "kitten",
      english_meaning: "A young cat."
    )

    assert_not similar_word.valid?
    assert_includes similar_word.errors[:chinese_meaning], "can't be blank"
  end
end
```

- [ ] **Step 2: Run the SimilarWord model test to verify it fails**

Run:

```bash
bin/rails test test/models/similar_word_test.rb
```

Expected: FAIL because `SimilarWord` still requires `similar_wordable` and `word`, and the `similar_words` table does not have `word`, `english_meaning`, `chinese_meaning`, or `word_question_id`.

- [ ] **Step 3: Update the original create migration for fresh databases**

Replace `db/migrate/20260429004710_create_similar_words.rb` with:

```ruby
class CreateSimilarWords < ActiveRecord::Migration[8.1]
  def change
    create_table :similar_words do |t|
      t.references :word_question, null: false, foreign_key: true
      t.string :word, null: false
      t.string :english_meaning, null: false
      t.string :chinese_meaning, null: false

      t.timestamps
    end
  end
end
```

- [ ] **Step 4: Add a migration for existing databases**

Create `db/migrate/20260430104000_rewrite_similar_words_as_word_choices.rb`:

```ruby
# frozen_string_literal: true

class RewriteSimilarWordsAsWordChoices < ActiveRecord::Migration[8.1]
  def up
    add_reference :similar_words, :word_question, foreign_key: true
    add_column :similar_words, :word, :string
    add_column :similar_words, :english_meaning, :string
    add_column :similar_words, :chinese_meaning, :string

    execute <<~SQL.squish
      UPDATE similar_words
      SET
        word_question_id = similar_wordable_id,
        word = words.word,
        english_meaning = words.english_meaning,
        chinese_meaning = words.chinese_meaning
      FROM words
      WHERE similar_words.word_id = words.id
        AND similar_words.similar_wordable_type = 'WordQuestion'
    SQL

    execute <<~SQL.squish
      DELETE FROM similar_words
      WHERE word_question_id IS NULL
    SQL

    change_column_null :similar_words, :word_question_id, false
    change_column_null :similar_words, :word, false
    change_column_null :similar_words, :english_meaning, false
    change_column_null :similar_words, :chinese_meaning, false

    remove_index :similar_words, name: "index_similar_words_on_similar_wordable"
    remove_index :similar_words, :word_id
    remove_foreign_key :similar_words, :words
    remove_column :similar_words, :similar_wordable_id
    remove_column :similar_words, :similar_wordable_type
    remove_column :similar_words, :word_id
  end

  def down
    add_reference :similar_words, :similar_wordable, polymorphic: true
    add_reference :similar_words, :word, foreign_key: true

    execute <<~SQL.squish
      INSERT INTO words (word, english_meaning, chinese_meaning, created_at, updated_at)
      SELECT DISTINCT similar_words.word, similar_words.english_meaning, similar_words.chinese_meaning, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM similar_words
      WHERE NOT EXISTS (
        SELECT 1 FROM words WHERE LOWER(words.word) = LOWER(similar_words.word)
      )
    SQL

    execute <<~SQL.squish
      UPDATE similar_words
      SET
        similar_wordable_id = word_question_id,
        similar_wordable_type = 'WordQuestion',
        word_id = words.id
      FROM words
      WHERE LOWER(words.word) = LOWER(similar_words.word)
    SQL

    change_column_null :similar_words, :similar_wordable_id, false
    change_column_null :similar_words, :similar_wordable_type, false
    change_column_null :similar_words, :word_id, false

    remove_column :similar_words, :word_question_id
    remove_column :similar_words, :word
    remove_column :similar_words, :english_meaning
    remove_column :similar_words, :chinese_meaning
  end
end
```

- [ ] **Step 5: Update the SimilarWord model**

Replace `app/models/similar_word.rb` with:

```ruby
class SimilarWord < ApplicationRecord
  belongs_to :word_question

  validates :word, presence: true
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true
end
```

- [ ] **Step 6: Remove the obsolete Word association**

Replace `app/models/word.rb` with:

```ruby
class Word < ApplicationRecord
  has_many :word_questions, dependent: :destroy
  has_many :word_question_records, foreign_key: :picked_word_id, dependent: :destroy
  has_one :word_recall_state, dependent: :destroy

  validates :word, presence: true, uniqueness: { case_sensitive: false }
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true

  after_create :create_initial_recall_state

  private

  def create_initial_recall_state
    create_word_recall_state!(due_day: created_at.to_date)
  end
end
```

This temporarily leaves `has_many :word_question_records` in place. Task 3 removes it when records stop using `picked_word_id`.

- [ ] **Step 7: Update similar word fixtures**

Replace `test/fixtures/similar_words.yml` with:

```yaml
dog_choice_for_cat_question:
  word_question: cat_question
  word: dog
  chinese_meaning: 狗
  english_meaning: A domesticated carnivorous mammal.

fish_choice_for_cat_question:
  word_question: cat_question
  word: fish
  chinese_meaning: 鱼
  english_meaning: A limbless cold-blooded vertebrate animal.

bird_choice_for_cat_question:
  word_question: cat_question
  word: bird
  chinese_meaning: 鸟
  english_meaning: A warm-blooded egg-laying vertebrate animal.
```

- [ ] **Step 8: Run migration and SimilarWord test**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/similar_word_test.rb
```

Expected: PASS for `test/models/similar_word_test.rb`.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260429004710_create_similar_words.rb db/migrate/20260430104000_rewrite_similar_words_as_word_choices.rb db/schema.rb app/models/similar_word.rb app/models/word.rb test/fixtures/similar_words.yml test/models/similar_word_test.rb
git commit -m "refactor similar words as word-shaped choices"
```

---

### Task 2: Update WordQuestion Choices and Question Creation

**Files:**
- Modify: `app/models/word_question.rb`
- Modify: `app/services/find_or_create_word_question.rb`
- Modify: `app/jobs/create_batch_word_questions_job.rb`
- Modify: `test/models/word_question_test.rb`
- Modify: `test/services/find_or_create_word_question_test.rb`
- Modify: `test/jobs/create_batch_word_questions_job_test.rb`

- [ ] **Step 1: Write failing WordQuestion choice tests**

Replace `test/models/word_question_test.rb` with:

```ruby
require "test_helper"

class WordQuestionTest < ActiveSupport::TestCase
  def build_question_with_similar_count(count)
    question = WordQuestion.new(word: words(:cat))
    [
      [ "dog", "A domesticated carnivorous mammal.", "狗" ],
      [ "fish", "A limbless cold-blooded vertebrate animal.", "鱼" ],
      [ "bird", "A warm-blooded egg-laying vertebrate animal.", "鸟" ]
    ].first(count).each do |word, english_meaning, chinese_meaning|
      question.similar_words.build(
        word: word,
        english_meaning: english_meaning,
        chinese_meaning: chinese_meaning
      )
    end
    question
  end

  test "valid with a word and exactly 3 similar words" do
    question = build_question_with_similar_count(3)
    assert question.valid?
  end

  test "invalid without a word" do
    question = WordQuestion.new
    question.similar_words.build(word: "dog", english_meaning: "A dog.", chinese_meaning: "狗")
    question.similar_words.build(word: "fish", english_meaning: "A fish.", chinese_meaning: "鱼")
    question.similar_words.build(word: "bird", english_meaning: "A bird.", chinese_meaning: "鸟")
    assert_not question.valid?
    assert_includes question.errors[:word], "must exist"
  end

  test "invalid with fewer than 3 similar words" do
    question = build_question_with_similar_count(2)
    assert_not question.valid?
    assert_includes question.errors[:similar_words], "must have exactly 3"
  end

  test "invalid with more than 3 similar words" do
    question = build_question_with_similar_count(3)
    question.similar_words.build(word: "kitten", english_meaning: "A young cat.", chinese_meaning: "小猫")
    assert_not question.valid?
    assert_includes question.errors[:similar_words], "must have exactly 3"
  end

  test "choices expose tokens and correctness for target word and similar words" do
    question = word_questions(:cat_question)

    choices = question.choices

    assert_equal 4, choices.size
    assert_equal "word:#{question.word.id}", choices.first.token
    assert_equal question.word.word, choices.first.word
    assert_equal true, choices.first.correct
    assert_equal "similar_word:#{similar_words(:dog_choice_for_cat_question).id}", choices.second.token
    assert_equal false, choices.second.correct
  end

  test "choice_for_token resolves a valid choice token" do
    question = word_questions(:cat_question)
    token = "similar_word:#{similar_words(:dog_choice_for_cat_question).id}"

    choice = question.choice_for_token(token)

    assert_equal token, choice.token
    assert_equal "dog", choice.word
    assert_equal false, choice.correct
  end

  test "choice_for_token returns nil for a choice from another question" do
    other_question = WordQuestion.create!(word: words(:dog)) do |question|
      question.similar_words.build(word: "wolf", english_meaning: "A wild canine.", chinese_meaning: "狼")
      question.similar_words.build(word: "fox", english_meaning: "A wild canine.", chinese_meaning: "狐狸")
      question.similar_words.build(word: "puppy", english_meaning: "A young dog.", chinese_meaning: "小狗")
    end
    token = "similar_word:#{other_question.similar_words.first.id}"

    assert_nil word_questions(:cat_question).choice_for_token(token)
  end
end
```

- [ ] **Step 2: Run WordQuestion test to verify it fails**

Run:

```bash
bin/rails test test/models/word_question_test.rb
```

Expected: FAIL because `WordQuestion#choices` still returns Active Record rows and there is no `choice_for_token`.

- [ ] **Step 3: Update WordQuestion**

Replace `app/models/word_question.rb` with:

```ruby
class WordQuestion < ApplicationRecord
  Choice = Data.define(:token, :word, :english_meaning, :chinese_meaning, :correct)

  belongs_to :word
  has_many :similar_words, dependent: :destroy
  has_many :word_question_records, dependent: :destroy

  validates :word, presence: true
  validate :exactly_three_similar_words

  def choices
    [
      Choice.new(
        token: "word:#{word.id}",
        word: word.word,
        english_meaning: word.english_meaning,
        chinese_meaning: word.chinese_meaning,
        correct: true
      )
    ] + similar_words.map do |similar_word|
      Choice.new(
        token: "similar_word:#{similar_word.id}",
        word: similar_word.word,
        english_meaning: similar_word.english_meaning,
        chinese_meaning: similar_word.chinese_meaning,
        correct: false
      )
    end
  end

  def choice_for_token(token)
    choices.find { |choice| choice.token == token }
  end

  private

  def exactly_three_similar_words
    return if similar_words.reject(&:marked_for_destruction?).size == 3

    errors.add(:similar_words, "must have exactly 3")
  end
end
```

- [ ] **Step 4: Update single-question creation service**

Replace `app/services/find_or_create_word_question.rb` with:

```ruby
# frozen_string_literal: true

# Finds an existing WordQuestion for a word, or creates one via LLM-suggested similar words.
class FindOrCreateWordQuestion
  def initialize(llm_client: Llm::OpenRouterSimilarWordsClient.new)
    @llm_client = llm_client
  end

  # @param word [Word]
  # @return [WordQuestion]
  def call(word:)
    existing = word.word_questions.first
    return existing if existing

    similar_results = @llm_client.similar_words(word.word)

    question = word.word_questions.build
    similar_results.each do |result|
      question.similar_words.build(
        word: result.word,
        english_meaning: result.english_meaning,
        chinese_meaning: result.chinese_meaning
      )
    end
    question.save!
    question
  end
end
```

- [ ] **Step 5: Update batch question creation job**

Replace `app/jobs/create_batch_word_questions_job.rb` with:

```ruby
# frozen_string_literal: true

class CreateBatchWordQuestionsJob < ApplicationJob
  queue_as :default

  def perform(word_ids)
    words = Word.where(id: Array(word_ids)).order(:id).to_a
    words = words.reject { |word| word.word_questions.exists? }
    return if words.empty?

    similar_by_target = Llm::OpenRouterSimilarWordsClient.new.similar_words_for_words(words.map(&:word))

    words.each do |word|
      create_question_for_word(word, similar_by_target)
    end
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateBatchWordQuestionsJob LLM error: #{e.class}: #{e.message}")
  end

  private

  def create_question_for_word(word, similar_by_target)
    return if word.word_questions.exists?

    triples = similar_by_target[word.word]
    unless triples&.size == 3
      Rails.logger.warn("CreateBatchWordQuestionsJob skipping word_id=#{word.id}: missing similar words in batch response")
      return
    end

    ActiveRecord::Base.transaction do
      word.reload
      return if word.word_questions.exists?

      question = word.word_questions.build
      triples.each do |result|
        question.similar_words.build(
          word: result.word,
          english_meaning: result.english_meaning,
          chinese_meaning: result.chinese_meaning
        )
      end
      question.save!
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("CreateBatchWordQuestionsJob skipped word_id=#{word.id}: #{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 6: Update service tests for no Word promotion**

In `test/services/find_or_create_word_question_test.rb`, replace the test named `"reuses existing similar words and only creates missing words"` with:

```ruby
  test "stores similar words on the question without creating Word records" do
    word = Word.create!(word: "pony", english_meaning: "A small horse.", chinese_meaning: "小马")
    triples = [
      [ "dog", "A domesticated carnivorous mammal.", "狗" ],
      [ "mule", "A hybrid of horse and donkey.", "骡子" ],
      [ "foal", "A young horse.", "马驹" ]
    ]
    service = build_service(triples)

    assert_no_difference "Word.count" do
      @result = service.call(word: word)
    end

    words_in_question = @result.similar_words.map(&:word)
    assert_equal [ "dog", "mule", "foal" ], words_in_question
  end
```

- [ ] **Step 7: Run question creation tests**

Run:

```bash
bin/rails test test/models/word_question_test.rb test/services/find_or_create_word_question_test.rb test/jobs/create_batch_word_questions_job_test.rb
```

Expected: PASS for all three test files. If `test/jobs/create_batch_word_questions_job_test.rb` still expects new `Word` rows, update those assertions to check `SimilarWord.count` and `question.similar_words.map(&:word)` instead.

- [ ] **Step 8: Commit**

```bash
git add app/models/word_question.rb app/services/find_or_create_word_question.rb app/jobs/create_batch_word_questions_job.rb test/models/word_question_test.rb test/services/find_or_create_word_question_test.rb test/jobs/create_batch_word_questions_job_test.rb
git commit -m "store generated choices as similar words"
```

---

### Task 3: Update Answer Submission and WordQuestionRecord

**Files:**
- Create: `db/migrate/20260430104100_rewrite_word_question_records_picked_choice.rb`
- Modify: `app/models/word.rb`
- Modify: `app/models/word_question_record.rb`
- Modify: `app/controllers/word_question_records_controller.rb`
- Modify: `app/views/remember_words/index.html.erb`
- Modify: `test/fixtures/word_question_records.yml`
- Modify: `test/models/word_question_record_test.rb`
- Modify: `test/controllers/word_question_records_controller_test.rb`

- [ ] **Step 1: Write failing WordQuestionRecord model tests**

Replace `test/models/word_question_record_test.rb` with:

```ruby
require "test_helper"

class WordQuestionRecordTest < ActiveSupport::TestCase
  def setup
    @question = word_questions(:cat_question)
  end

  test "valid with a question and picked choice snapshot" do
    record = WordQuestionRecord.new(
      word_question: @question,
      picked_choice_token: "word:#{@question.word.id}",
      picked_choice_word: @question.word.word,
      is_correct: true
    )
    assert record.valid?
  end

  test "invalid without word_question" do
    record = WordQuestionRecord.new(
      picked_choice_token: "word:#{words(:cat).id}",
      picked_choice_word: "cat",
      is_correct: false
    )
    assert_not record.valid?
    assert_includes record.errors[:word_question], "must exist"
  end

  test "invalid without picked choice token" do
    record = WordQuestionRecord.new(
      word_question: @question,
      picked_choice_word: "cat",
      is_correct: false
    )
    assert_not record.valid?
    assert_includes record.errors[:picked_choice_token], "can't be blank"
  end

  test "invalid without picked choice word" do
    record = WordQuestionRecord.new(
      word_question: @question,
      picked_choice_token: "word:#{@question.word.id}",
      is_correct: false
    )
    assert_not record.valid?
    assert_includes record.errors[:picked_choice_word], "can't be blank"
  end

  test "is_correct defaults to false" do
    record = WordQuestionRecord.new
    assert_equal false, record.is_correct
  end

  test "correct? returns true when is_correct is true" do
    record = WordQuestionRecord.new(is_correct: true)
    assert record.correct?
  end

  test "correct? returns false when is_correct is false" do
    record = WordQuestionRecord.new(is_correct: false)
    assert_not record.correct?
  end

  test "creating a correct record updates the target word recall state" do
    state = @question.word.word_recall_state || @question.word.create_word_recall_state!(
      remember_times: 0,
      due_day: @question.word.created_at.to_date
    )
    state.update!(remember_times: 0, due_day: Date.new(2026, 4, 1))

    WordQuestionRecord.create!(
      word_question: @question,
      picked_choice_token: "word:#{@question.word.id}",
      picked_choice_word: @question.word.word,
      is_correct: true,
      created_at: Time.zone.local(2026, 4, 1, 10),
      updated_at: Time.zone.local(2026, 4, 1, 10)
    )

    state.reload
    assert_equal 1, state.remember_times
    assert_equal Date.new(2026, 4, 3), state.due_day
  end

  test "creating an incorrect record does not update the target word recall state" do
    state = @question.word.word_recall_state || @question.word.create_word_recall_state!(
      remember_times: 0,
      due_day: @question.word.created_at.to_date
    )
    state.update!(remember_times: 0, due_day: Date.new(2026, 4, 1))

    WordQuestionRecord.create!(
      word_question: @question,
      picked_choice_token: "similar_word:#{similar_words(:dog_choice_for_cat_question).id}",
      picked_choice_word: "dog",
      is_correct: false,
      created_at: Time.zone.local(2026, 4, 1, 10),
      updated_at: Time.zone.local(2026, 4, 1, 10)
    )

    state.reload
    assert_equal 0, state.remember_times
    assert_equal Date.new(2026, 4, 1), state.due_day
  end
end
```

- [ ] **Step 2: Run record model tests to verify they fail**

Run:

```bash
bin/rails test test/models/word_question_record_test.rb
```

Expected: FAIL because `picked_choice_token` and `picked_choice_word` do not exist yet.

- [ ] **Step 3: Add record migration**

Create `db/migrate/20260430104100_rewrite_word_question_records_picked_choice.rb`:

```ruby
# frozen_string_literal: true

class RewriteWordQuestionRecordsPickedChoice < ActiveRecord::Migration[8.1]
  def up
    add_column :word_question_records, :picked_choice_token, :string
    add_column :word_question_records, :picked_choice_word, :string

    execute <<~SQL.squish
      UPDATE word_question_records
      SET
        picked_choice_token = 'word:' || picked_word_id,
        picked_choice_word = words.word
      FROM words
      WHERE word_question_records.picked_word_id = words.id
    SQL

    change_column_null :word_question_records, :picked_choice_token, false
    change_column_null :word_question_records, :picked_choice_word, false

    remove_index :word_question_records, :picked_word_id
    remove_foreign_key :word_question_records, column: :picked_word_id
    remove_column :word_question_records, :picked_word_id
  end

  def down
    add_reference :word_question_records, :picked_word, foreign_key: { to_table: :words }

    execute <<~SQL.squish
      UPDATE word_question_records
      SET picked_word_id = CAST(SPLIT_PART(picked_choice_token, ':', 2) AS bigint)
      WHERE picked_choice_token LIKE 'word:%'
    SQL

    execute <<~SQL.squish
      UPDATE word_question_records
      SET picked_word_id = word_questions.word_id
      FROM word_questions
      WHERE word_question_records.word_question_id = word_questions.id
        AND word_question_records.picked_word_id IS NULL
    SQL

    change_column_null :word_question_records, :picked_word_id, false
    add_index :word_question_records, :picked_word_id

    remove_column :word_question_records, :picked_choice_token
    remove_column :word_question_records, :picked_choice_word
  end
end
```

- [ ] **Step 4: Update Word and WordQuestionRecord models**

Replace `app/models/word.rb` with:

```ruby
class Word < ApplicationRecord
  has_many :word_questions, dependent: :destroy
  has_one :word_recall_state, dependent: :destroy

  validates :word, presence: true, uniqueness: { case_sensitive: false }
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true

  after_create :create_initial_recall_state

  private

  def create_initial_recall_state
    create_word_recall_state!(due_day: created_at.to_date)
  end
end
```

Replace `app/models/word_question_record.rb` with:

```ruby
class WordQuestionRecord < ApplicationRecord
  belongs_to :word_question

  validates :word_question, presence: true
  validates :picked_choice_token, presence: true
  validates :picked_choice_word, presence: true

  after_create :update_word_recall_state

  def correct?
    is_correct
  end

  private

  def update_word_recall_state
    WordsDueForRecall.update_state_for(self)
  end
end
```

- [ ] **Step 5: Update controller**

Replace `app/controllers/word_question_records_controller.rb` with:

```ruby
class WordQuestionRecordsController < ApplicationController
  DIRECTIONS = %w[english_to_chinese chinese_to_english].freeze

  def create
    question = WordQuestion.find(record_params[:word_question_id])
    choice = question.choice_for_token(record_params[:picked_choice])
    raise ActiveRecord::RecordNotFound unless choice

    WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: choice.token,
      picked_choice_word: choice.word,
      is_correct: choice.correct
    )

    redirect_to root_path_with_state(recalled_word_ids + [ question.word_id ]), notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path_with_state(recalled_word_ids), alert: "Could not save answer."
  end

  private

  def record_params
    params.require(:word_question_record).permit(:word_question_id, :picked_choice)
  end

  def recalled_word_ids
    params[:recalled_word_ids].to_s.split(",").filter_map do |word_id|
      parsed_id = Integer(word_id, exception: false)
      parsed_id if parsed_id&.positive?
    end.uniq
  end

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
end
```

- [ ] **Step 6: Update answer form**

In `app/views/remember_words/index.html.erb`, replace the radio button inside the choices loop:

```erb
<%= radio_button_tag "word_question_record[picked_word_id]", choice.id, false, required: true %>
```

with:

```erb
<%= radio_button_tag "word_question_record[picked_choice]", choice.token, false, required: true %>
```

- [ ] **Step 7: Update record fixture**

Replace `test/fixtures/word_question_records.yml` with:

```yaml
correct_answer:
  word_question: cat_question
  picked_choice_token: word:<%= ActiveRecord::FixtureSet.identify(:cat) %>
  picked_choice_word: cat
  is_correct: true
```

- [ ] **Step 8: Update controller tests**

In `test/controllers/word_question_records_controller_test.rb`, update `setup` to build similar words directly:

```ruby
  def setup
    @word = Word.create!(
      word: "test_word_#{SecureRandom.hex(4)}",
      english_meaning: "test",
      chinese_meaning: "测试"
    )
    @question = WordQuestion.new(word: @word)
    @question.similar_words.build(word: "similar_1_#{SecureRandom.hex(4)}", english_meaning: "s1", chinese_meaning: "s1")
    @question.similar_words.build(word: "similar_2_#{SecureRandom.hex(4)}", english_meaning: "s2", chinese_meaning: "s2")
    @question.similar_words.build(word: "similar_3_#{SecureRandom.hex(4)}", english_meaning: "s3", chinese_meaning: "s3")
    @question.save!
  end
```

In the correct-answer test params, replace:

```ruby
picked_word_id: @word.id
```

with:

```ruby
picked_choice: "word:#{@word.id}"
```

In the incorrect-answer test setup and params, replace:

```ruby
wrong_word = @question.similar_words.first.word
```

with:

```ruby
wrong_choice = @question.similar_words.first
```

and replace:

```ruby
picked_word_id: wrong_word.id
```

with:

```ruby
picked_choice: "similar_word:#{wrong_choice.id}"
```

For every other controller test request, replace:

```ruby
picked_word_id: @word.id
```

with:

```ruby
picked_choice: "word:#{@word.id}"
```

- [ ] **Step 9: Run migration and record/controller tests**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/word_question_record_test.rb test/controllers/word_question_records_controller_test.rb
```

Expected: PASS for both test files.

- [ ] **Step 10: Commit**

```bash
git add db/migrate/20260430104100_rewrite_word_question_records_picked_choice.rb db/schema.rb app/models/word.rb app/models/word_question_record.rb app/controllers/word_question_records_controller.rb app/views/remember_words/index.html.erb test/fixtures/word_question_records.yml test/models/word_question_record_test.rb test/controllers/word_question_records_controller_test.rb
git commit -m "record selected question choices by token"
```

---

### Task 4: Update Recall Tests and Run Full Verification

**Files:**
- Modify: `test/services/words_due_for_recall_test.rb`
- Regenerate: `db/schema.rb`

- [ ] **Step 1: Update recall test helpers that build question choices**

In `test/services/words_due_for_recall_test.rb`, replace:

```ruby
question.similar_words.build(word: similar_word)
```

with:

```ruby
question.similar_words.build(
  word: similar_word.word,
  english_meaning: similar_word.english_meaning,
  chinese_meaning: similar_word.chinese_meaning
)
```

- [ ] **Step 2: Search for obsolete APIs**

Run:

```bash
rg "similar_wordable|picked_word_id|picked_word|question\.similar_words\.build\(word: Word|includes\(:word\)|\.similar_words\.first\.word\.word" app test db
```

Expected: no matches, except migration `down` methods may contain `picked_word_id` and `similar_wordable` for rollback.

- [ ] **Step 3: Run the focused test set**

Run:

```bash
bin/rails test test/models/similar_word_test.rb test/models/word_question_test.rb test/models/word_question_record_test.rb test/services/find_or_create_word_question_test.rb test/jobs/create_batch_word_questions_job_test.rb test/controllers/word_question_records_controller_test.rb test/services/words_due_for_recall_test.rb
```

Expected: PASS.

- [ ] **Step 4: Run the full test suite**

Run:

```bash
bin/rails test
```

Expected: PASS.

- [ ] **Step 5: Verify schema has the requested similar_words shape**

Run:

```bash
bin/rails runner 'puts ActiveRecord::Base.connection.columns(:similar_words).map(&:name)'
```

Expected output includes:

```text
id
word_question_id
word
english_meaning
chinese_meaning
created_at
updated_at
```

Expected output does not include:

```text
similar_wordable_id
similar_wordable_type
word_id
```

- [ ] **Step 6: Commit**

```bash
git add db/schema.rb test/services/words_due_for_recall_test.rb
git commit -m "finish similar word schema rewrite"
```

---

## Self-Review

**Spec coverage:** The plan removes `similar_wordable_id`, `similar_wordable_type`, and `word_id` from `similar_words`. It adds `word`, `english_meaning`, and `chinese_meaning` to `similar_words`, matching the user-facing fields on `words`. It also updates the surrounding quiz flow required because similar choices stop being `Word` records.

**Placeholder scan:** The plan has no `TBD`, `TODO`, "implement later", or "similar to" placeholders. Every code-changing step includes the concrete code or exact replacement.

**Type consistency:** `WordQuestion#choices` returns `Choice` objects with `token`, `word`, `english_meaning`, `chinese_meaning`, and `correct`. The controller consumes those same fields. `WordQuestionRecord` stores `picked_choice_token` and `picked_choice_word`, matching the migration, fixtures, and tests.
