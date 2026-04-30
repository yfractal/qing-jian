# LLM Question Jobs for Single and Batch Word Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically generate missing-word questions after word creation, using a single-word background job for normal create and a batch background job for batch create.

**Architecture:** Keep question creation asynchronous via Active Job. Route single-word creation to a per-word job that delegates to `FindOrCreateWordQuestion`, and route batch creation to a new batch job that sends one LLM request for all newly created words. Remove `CreateMissingWordQuestionsBatch` and its references to avoid duplicate pathways.

**Tech Stack:** Ruby on Rails, Active Job, Solid Queue recurring config, Minitest, existing `Llm::OpenRouterSimilarWordsClient`, existing `FindOrCreateWordQuestion`.

---

## File Responsibility Map

- **Modify:** `app/controllers/words_controller.rb`
  - Enqueue single-word question generation job after successful `create`.
  - Enqueue batch question generation job once after `batch_create` finishes creating words.
- **Create:** `app/jobs/create_word_question_job.rb`
  - Handles one `word_id`, creates question via `FindOrCreateWordQuestion`.
- **Create:** `app/jobs/create_batch_word_questions_job.rb`
  - Handles many `word_ids`, performs one batched LLM call and persists questions.
- **Modify:** `app/services/find_or_create_word_question.rb`
  - Keep reusable helper for creating/reusing distractor words from similar-word results; may add small API surface for batch job reuse if needed.
- **Delete:** `app/services/create_missing_word_questions_batch.rb`
  - Remove obsolete periodic missing-question batch service.
- **Modify:** `app/jobs/create_missing_word_questions_job.rb`
  - Remove or repurpose to avoid dependence on deleted service.
- **Modify:** `config/recurring.yml`
  - Remove recurring schedule for deleted missing-question sweep job.
- **Modify tests:** `test/controllers/words_controller_test.rb`
  - Verify enqueue behavior for `create` vs `batch_create`.
- **Create tests:** `test/jobs/create_word_question_job_test.rb`
  - Verify single-word job creates question and is idempotent-safe.
- **Create tests:** `test/jobs/create_batch_word_questions_job_test.rb`
  - Verify batch job uses one LLM batch response and creates expected questions.
- **Delete tests:** `test/services/create_missing_word_questions_batch_test.rb`
  - Remove obsolete service tests.
- **Modify tests:** `test/jobs/create_missing_word_questions_job_test.rb`
  - Remove obsolete job expectations or replace with tests for new behavior.

### Task 1: Add single-word async question job

**Files:**
- Create: `app/jobs/create_word_question_job.rb`
- Test: `test/jobs/create_word_question_job_test.rb`

- [ ] **Step 1: Write the failing job test (single word path)**

```ruby
# test/jobs/create_word_question_job_test.rb
require "test_helper"
require "ostruct"

class CreateWordQuestionJobTest < ActiveJob::TestCase
  def build_client_for(word_lemma)
    inner = [
      { "word" => "#{word_lemma}_a", "english_meaning" => "m a", "chinese_meaning" => "甲" },
      { "word" => "#{word_lemma}_b", "english_meaning" => "m b", "chinese_meaning" => "乙" },
      { "word" => "#{word_lemma}_c", "english_meaning" => "m c", "chinese_meaning" => "丙" }
    ]
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    requester = ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
    Llm::OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
  end

  test "creates question for a word id" do
    word = Word.create!(word: "single_async_word", english_meaning: "m", chinese_meaning: "中")
    client = build_client_for(word.word)

    assert_difference("WordQuestion.count", 1) do
      CreateWordQuestionJob.perform_now(word.id, llm_client: client)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/create_word_question_job_test.rb -v`
Expected: FAIL with `uninitialized constant CreateWordQuestionJob` or wrong method signature.

- [ ] **Step 3: Implement minimal single-word job**

```ruby
# app/jobs/create_word_question_job.rb
class CreateWordQuestionJob < ApplicationJob
  queue_as :default

  # llm_client is injectable for tests.
  def perform(word_id, llm_client: nil)
    word = Word.find_by(id: word_id)
    return unless word

    FindOrCreateWordQuestion.new(llm_client: llm_client || Llm::OpenRouterSimilarWordsClient.new).call(word: word)
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateWordQuestionJob LLM error for word_id=#{word_id}: #{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/create_word_question_job_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/create_word_question_job.rb test/jobs/create_word_question_job_test.rb
git commit -m "feat: add async single-word question generation job"
```

### Task 2: Enqueue single-word job after normal word creation

**Files:**
- Modify: `app/controllers/words_controller.rb`
- Modify: `test/controllers/words_controller_test.rb`

- [ ] **Step 1: Write failing controller enqueue test**

```ruby
test "create enqueues single-word question job" do
  assert_enqueued_with(job: CreateWordQuestionJob) do
    post words_url, params: {
      word: {
        word: "enqueue_single_#{Time.now.to_i}",
        english_meaning: "A gloss",
        chinese_meaning: "中文"
      }
    }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/words_controller_test.rb -n "/create enqueues single-word question job/" -v`
Expected: FAIL because no job is enqueued yet.

- [ ] **Step 3: Implement enqueue in `create` action**

```ruby
# app/controllers/words_controller.rb (inside create success branch)
if @word.save
  CreateWordQuestionJob.perform_later(@word.id)
  redirect_to @word, notice: "Word was successfully created."
else
  # unchanged
end
```

- [ ] **Step 4: Run focused controller tests**

Run: `bin/rails test test/controllers/words_controller_test.rb -n "/should create word|create enqueues single-word question job/" -v`
Expected: PASS for both creation and enqueue tests.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/words_controller.rb test/controllers/words_controller_test.rb
git commit -m "feat: enqueue question generation after single word create"
```

### Task 3: Add batch async job for newly created words

**Files:**
- Create: `app/jobs/create_batch_word_questions_job.rb`
- Create: `test/jobs/create_batch_word_questions_job_test.rb`
- Modify (optional reuse helper only): `app/services/find_or_create_word_question.rb`

- [ ] **Step 1: Write failing batch job test**

```ruby
# test/jobs/create_batch_word_questions_job_test.rb
require "test_helper"
require "ostruct"

class CreateBatchWordQuestionsJobTest < ActiveJob::TestCase
  def build_batch_client(lemmas)
    inner = lemmas.map do |lemma|
      {
        "word" => lemma,
        "similar_words" => 3.times.map do |i|
          { "word" => "#{lemma}_sim_#{i}", "english_meaning" => "m#{i}", "chinese_meaning" => "义#{i}" }
        end
      }
    end
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    requester = ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
    Llm::OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
  end

  test "creates questions for all provided word ids in one run" do
    words = [
      Word.create!(word: "batch_async_1", english_meaning: "m1", chinese_meaning: "中1"),
      Word.create!(word: "batch_async_2", english_meaning: "m2", chinese_meaning: "中2")
    ]
    client = build_batch_client(words.map(&:word))

    assert_difference("WordQuestion.count", 2) do
      CreateBatchWordQuestionsJob.perform_now(words.map(&:id), llm_client: client)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/create_batch_word_questions_job_test.rb -v`
Expected: FAIL with missing job implementation.

- [ ] **Step 3: Implement batch job**

```ruby
# app/jobs/create_batch_word_questions_job.rb
class CreateBatchWordQuestionsJob < ApplicationJob
  queue_as :default

  def perform(word_ids, llm_client: nil)
    words = Word.where(id: Array(word_ids)).order(:id).to_a
    words = words.reject { |word| word.word_questions.exists? }
    return if words.empty?

    client = llm_client || Llm::OpenRouterSimilarWordsClient.new
    similar_by_target = client.similar_words_for_words(words.map(&:word))

    words.each do |word|
      next if word.word_questions.exists?

      triples = similar_by_target[word.word]
      next unless triples&.size == 3

      ActiveRecord::Base.transaction do
        word.reload
        next if word.word_questions.exists?

        records = triples.map { |result| FindOrCreateWordQuestion.find_or_create_word_for_similar_result(result) }
        question = word.word_questions.build
        records.each { |record| question.similar_words.build(word: record) }
        question.save!
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("CreateBatchWordQuestionsJob skipped word_id=#{word.id}: #{e.class}: #{e.message}")
    end
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateBatchWordQuestionsJob LLM error: #{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 4: Run batch job test**

Run: `bin/rails test test/jobs/create_batch_word_questions_job_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/create_batch_word_questions_job.rb test/jobs/create_batch_word_questions_job_test.rb
git commit -m "feat: add async batch word question generation job"
```

### Task 4: Enqueue batch job from `batch_create` and skip per-word job

**Files:**
- Modify: `app/controllers/words_controller.rb`
- Modify: `test/controllers/words_controller_test.rb`

- [ ] **Step 1: Write failing test asserting only batch job enqueued**

```ruby
test "batch_create enqueues one batch question job and no single jobs" do
  payload = [
    { word: "batch_enqueue_1", english_meaning: "m1", chinese_meaning: "中1" },
    { word: "batch_enqueue_2", english_meaning: "m2", chinese_meaning: "中2" }
  ]

  assert_enqueued_with(job: CreateBatchWordQuestionsJob) do
    post batch_create_words_url, params: { words: payload }, as: :json
  end

  single_jobs = enqueued_jobs.count { |job| job[:job] == CreateWordQuestionJob }
  assert_equal 0, single_jobs
end
```

- [ ] **Step 2: Run focused test to verify failure**

Run: `bin/rails test test/controllers/words_controller_test.rb -n "/batch_create enqueues one batch question job and no single jobs/" -v`
Expected: FAIL because no batch job is enqueued yet.

- [ ] **Step 3: Implement `batch_create` enqueue with created IDs**

```ruby
# app/controllers/words_controller.rb (inside batch_create)
created_word_ids = []

words.each do |entry|
  word = Word.new(
    word: entry[:word] || entry["word"],
    english_meaning: entry[:english_meaning] || entry["english_meaning"],
    chinese_meaning: entry[:chinese_meaning] || entry["chinese_meaning"]
  )

  if word.save
    created << { id: word.id, word: word.word }
    created_word_ids << word.id
  else
    failed << { word: word.word.presence || (entry[:word] || entry["word"]), errors: word.errors.full_messages.join(", ") }
  end
end

CreateBatchWordQuestionsJob.perform_later(created_word_ids) if created_word_ids.any?
render json: { created: created, failed: failed }, status: :created
```

- [ ] **Step 4: Run controller tests for batch create behaviors**

Run: `bin/rails test test/controllers/words_controller_test.rb -n "/batch_create/" -v`
Expected: PASS for existing creation/failure assertions and new enqueue assertions.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/words_controller.rb test/controllers/words_controller_test.rb
git commit -m "feat: enqueue batch question generation after batch create"
```

### Task 5: Remove obsolete missing-question batch service and recurring job

**Files:**
- Delete: `app/services/create_missing_word_questions_batch.rb`
- Modify or Delete: `app/jobs/create_missing_word_questions_job.rb`
- Modify: `config/recurring.yml`
- Delete: `test/services/create_missing_word_questions_batch_test.rb`
- Modify or Delete: `test/jobs/create_missing_word_questions_job_test.rb`

- [ ] **Step 1: Write failing tests reflecting removal**

```ruby
# test/jobs/create_missing_word_questions_job_test.rb
require "test_helper"

class CreateMissingWordQuestionsJobTest < ActiveJob::TestCase
  test "legacy missing-word questions job is removed" do
    assert_raises(NameError) { CreateMissingWordQuestionsJob }
  end
end
```

- [ ] **Step 2: Run affected tests to confirm current dependency**

Run: `bin/rails test test/services/create_missing_word_questions_batch_test.rb test/jobs/create_missing_word_questions_job_test.rb -v`
Expected: Existing tests pass before removal (baseline), then fail after deletions until test updates are complete.

- [ ] **Step 3: Remove obsolete code and recurring schedule**

```yaml
# config/recurring.yml
production: {}
```

```ruby
# Remove files entirely:
# - app/services/create_missing_word_questions_batch.rb
# - test/services/create_missing_word_questions_batch_test.rb
# - app/jobs/create_missing_word_questions_job.rb (if fully unused)
# - test/jobs/create_missing_word_questions_job_test.rb (replace with new-job coverage)
```

- [ ] **Step 4: Run suite segments to verify no references remain**

Run: `bin/rails test test/controllers/words_controller_test.rb test/jobs/create_word_question_job_test.rb test/jobs/create_batch_word_questions_job_test.rb -v`
Expected: PASS

Run: `bin/rails test -v`
Expected: PASS (or only pre-existing unrelated failures).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove legacy missing-question batch service and scheduler"
```

### Task 6: Final verification and documentation touch-up

**Files:**
- Modify (if needed): `README.md`

- [ ] **Step 1: Add or update async behavior docs (if README has job behavior section)**

```markdown
## background jobs

- Creating a single word enqueues `CreateWordQuestionJob`.
- Batch creating words enqueues one `CreateBatchWordQuestionsJob`.
- Similar words are fetched via OpenRouter and used to build `WordQuestion` distractors.
```

- [ ] **Step 2: Run formatting/lint checks used by project**

Run: `bin/rubocop`
Expected: PASS (or only pre-existing offenses not caused by this change).

- [ ] **Step 3: Re-run key tests as release gate**

Run: `bin/rails test test/controllers/words_controller_test.rb test/jobs/create_word_question_job_test.rb test/jobs/create_batch_word_questions_job_test.rb -v`
Expected: PASS

- [ ] **Step 4: Confirm clean diff and summarize**

Run: `git status`
Expected: only intended files changed; no leftover references to `CreateMissingWordQuestionsBatch`.

- [ ] **Step 5: Commit docs update (if changed separately)**

```bash
git add README.md
git commit -m "docs: describe async word question generation flow"
```

## Self-Review

### 1) Spec coverage check

- Requirement: "after word has been created create a background job ..." -> Covered by Task 1 and Task 2.
- Requirement: "batch words creation ... skip single word background job and call a batch background job ..." -> Covered by Task 3 and Task 4.
- Requirement: "delete the CreateMissingWordQuestionsBatch" -> Covered by Task 5.

No gaps found.

### 2) Placeholder scan

- Checked for `TODO`, `TBD`, "handle edge cases", and vague "write tests for above" language.
- All tasks include explicit file paths, code snippets, runnable commands, and expected outcomes.

### 3) Type/signature consistency

- `CreateWordQuestionJob.perform(word_id, llm_client: nil)` is used consistently across tests and controller enqueue path.
- `CreateBatchWordQuestionsJob.perform(word_ids, llm_client: nil)` is used consistently across tests and controller enqueue path.
- Reused helper `FindOrCreateWordQuestion.find_or_create_word_for_similar_result` matches current service API.

Plan complete and saved to `docs/superpowers/plans/2026-04-30-llm-question-jobs-for-single-and-batch-words.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
