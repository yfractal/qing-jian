# Batch Word Lookup and Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add batch word lookup via LLM API, batch word creation endpoint, and a script to automate bulk word import.

**Architecture:** Extend `OpenRouterWordMeaningClient` with batch lookup method that accepts multiple words and returns multiple meanings in one API call. Add batch creation endpoint to `WordsController`. Create a rake task/script that combines batch lookup and batch creation to import word lists.

**Tech Stack:** Ruby on Rails, OpenRouter API, Minitest

---

### Task 1: Add Batch Lookup to OpenRouterWordMeaningClient

**Files:**
- Modify: `app/services/open_router_word_meaning_client.rb`
- Test: `test/services/open_router_word_meaning_client_test.rb`

- [ ] **Step 1: Write the failing test for batch_lookup with empty array**

```ruby
test "batch_lookup raises when words array is empty" do
  client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(*) { raise "should not call" })
  error = assert_raises(OpenRouterWordMeaningClient::Error) { client.batch_lookup([]) }
  assert_equal "words array is empty", error.message
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb:96 -v`
Expected: FAIL with "NoMethodError: undefined method `batch_lookup'"

- [ ] **Step 3: Write the failing test for batch_lookup success case**

```ruby
test "batch_lookup returns array of MeaningResults on success" do
  inner = [
    { "word" => "cat", "english_meaning" => "A small carnivorous mammal.", "chinese_meaning" => "猫" },
    { "word" => "dog", "english_meaning" => "A domesticated carnivorous mammal.", "chinese_meaning" => "狗" }
  ]
  outer = {
    "choices" => [
      { "message" => { "content" => JSON.generate(inner) } }
    ]
  }
  response = OpenStruct.new(code: "200", body: JSON.generate(outer))
  client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

  results = client.batch_lookup(["cat", "dog"])
  assert_equal 2, results.length
  assert_equal "cat", results[0].word
  assert_equal "A small carnivorous mammal.", results[0].english_meaning
  assert_equal "猫", results[0].chinese_meaning
  assert_equal "dog", results[1].word
  assert_equal "A domesticated carnivorous mammal.", results[1].english_meaning
  assert_equal "狗", results[1].chinese_meaning
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb:97 -v`
Expected: FAIL with "NoMethodError: undefined method `batch_lookup'"

- [ ] **Step 5: Write the failing test for batch_lookup handling blanks**

```ruby
test "batch_lookup skips blank words and strips spaces" do
  inner = [
    { "word" => "cat", "english_meaning" => "A small carnivorous mammal.", "chinese_meaning" => "猫" }
  ]
  outer = {
    "choices" => [
      { "message" => { "content" => JSON.generate(inner) } }
    ]
  }
  response = OpenStruct.new(code: "200", body: JSON.generate(outer))
  client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

  results = client.batch_lookup(["  cat  ", "  ", "", nil])
  assert_equal 1, results.length
  assert_equal "cat", results[0].word
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb:118 -v`
Expected: FAIL with "NoMethodError: undefined method `batch_lookup'"

- [ ] **Step 7: Write the failing test for batch_lookup error cases**

```ruby
test "batch_lookup raises when api key is missing" do
  client = OpenRouterWordMeaningClient.new(api_key: "", requester: ->(*) { raise "should not call" })
  error = assert_raises(OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
  assert_equal "OPENROUTER_API_KEY is not set", error.message
end

test "batch_lookup raises on non success status" do
  response = OpenStruct.new(code: "500", body: '{"error":"server error"}')
  client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

  error = assert_raises(OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
  assert_match(/OpenRouter request failed \(500\)/, error.message)
end

test "batch_lookup raises when response JSON is malformed" do
  outer = { "choices" => [ { "message" => { "content" => "not json array" } } ] }
  response = OpenStruct.new(code: "200", body: JSON.generate(outer))
  client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

  error = assert_raises(OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
  assert_match(/Invalid JSON from OpenRouter/, error.message)
end

test "batch_lookup raises when response missing required fields" do
  inner = [{ "word" => "cat", "english_meaning" => "x" }]
  outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
  response = OpenStruct.new(code: "200", body: JSON.generate(outer))
  client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

  error = assert_raises(OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
  assert_match(/missing required fields/, error.message)
end
```

- [ ] **Step 8: Run tests to verify they fail**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb -v`
Expected: Multiple FAILs with "NoMethodError: undefined method `batch_lookup'" and similar errors

- [ ] **Step 9: Add BatchMeaningResult data class and batch_lookup method**

In `app/services/open_router_word_meaning_client.rb`, after the `MeaningResult` definition (line 11), add:

```ruby
BatchMeaningResult = Data.define(:word, :english_meaning, :chinese_meaning)
```

Then add the `batch_lookup` method after the `lookup` method (before `private` keyword):

```ruby
# @param words [Array<String>] list of English lemmas to look up
# @return [Array<BatchMeaningResult>]
def batch_lookup(words)
  raise Error, "OPENROUTER_API_KEY is not set" if @api_key.to_s.strip.empty?

  trimmed_words = words.to_a.map { |w| w.to_s.strip }.reject(&:empty?).uniq
  raise Error, "words array is empty" if trimmed_words.empty?

  payload = build_batch_payload(trimmed_words)
  body_json = JSON.generate(payload)
  response = perform_request(body_json)

  unless response.code.to_i.between?(200, 299)
    snippet = response.body.to_s.byteslice(0, 500)
    raise Error, "OpenRouter request failed (#{response.code}): #{snippet}"
  end

  parse_batch_meanings_from_response(response.body)
end
```

- [ ] **Step 10: Add build_batch_payload helper method**

In the `private` section of `app/services/open_router_word_meaning_client.rb`, after `build_payload` method:

```ruby
def build_batch_payload(words)
  words_list = words.map { |w| "\"#{w.gsub(/\"/, "'")}\"" }.join(", ")
  {
    model: @model,
    messages: [
      {
        role: "user",
        content: <<~PROMPT.squish
          For the following list of English words: [#{words_list}], reply with ONLY a JSON array (no markdown, no code fences).
          Each array element must be an object with exactly three string keys:
          "word" — the input word (exactly as provided);
          "english_meaning" — a concise English definition or gloss suitable for a learner;
          "chinese_meaning" — a concise Chinese translation or gloss for the same sense.
          Example shape: [{"word":"...","english_meaning":"...","chinese_meaning":"..."}]
        PROMPT
      }
    ]
  }
end
```

- [ ] **Step 11: Add parse_batch_meanings_from_response helper method**

In the `private` section of `app/services/open_router_word_meaning_client.rb`, after `parse_meaning_from_response` method:

```ruby
def parse_batch_meanings_from_response(response_body)
  outer = JSON.parse(response_body)
  content = outer.dig("choices", 0, "message", "content")
  raise Error, "OpenRouter response missing message content" if content.to_s.strip.empty?

  inner = JSON.parse(content.strip)
  raise Error, "OpenRouter response is not an array" unless inner.is_a?(Array)

  inner.map do |item|
    word = item["word"]
    en = item["english_meaning"]
    zh = item["chinese_meaning"]
    if word.to_s.strip.empty? || en.to_s.strip.empty? || zh.to_s.strip.empty?
      raise Error, "OpenRouter JSON missing required fields (word, english_meaning, chinese_meaning)"
    end

    BatchMeaningResult.new(
      word: word.to_s.strip,
      english_meaning: en.to_s.strip,
      chinese_meaning: zh.to_s.strip
    )
  end
rescue JSON::ParserError => e
  raise Error, "Invalid JSON from OpenRouter: #{e.message}"
end
```

- [ ] **Step 12: Run tests to verify they pass**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb -v`
Expected: All tests PASS

- [ ] **Step 13: Commit batch lookup functionality**

```bash
git add app/services/open_router_word_meaning_client.rb test/services/open_router_word_meaning_client_test.rb
git commit -m "feat: add batch_lookup method to OpenRouterWordMeaningClient"
```

---

### Task 2: Add Batch Create Endpoint to WordsController

**Files:**
- Modify: `app/controllers/words_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/words_controller_test.rb`

- [ ] **Step 1: Write the failing test for batch_create endpoint with valid data**

In `test/controllers/words_controller_test.rb`, add:

```ruby
test "batch_create should create multiple words successfully" do
  words_data = [
    { word: "apple", english_meaning: "A round fruit", chinese_meaning: "苹果" },
    { word: "banana", english_meaning: "A long yellow fruit", chinese_meaning: "香蕉" }
  ]

  assert_difference("Word.count", 2) do
    post batch_create_words_url, params: { words: words_data }, as: :json
  end

  assert_response :created
  json_response = JSON.parse(response.body)
  assert_equal 2, json_response["created"].length
  assert_equal 0, json_response["failed"].length
  assert_equal "apple", json_response["created"][0]["word"]
  assert_equal "banana", json_response["created"][1]["word"]
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/words_controller_test.rb -v -n test_batch_create_should_create_multiple_words_successfully`
Expected: FAIL with "NoMethodError: undefined method `batch_create_words_url'"

- [ ] **Step 3: Write the failing test for batch_create with partial failures**

In `test/controllers/words_controller_test.rb`, add:

```ruby
test "batch_create should handle partial failures gracefully" do
  Word.create!(word: "existing", english_meaning: "Already exists", chinese_meaning: "已存在")

  words_data = [
    { word: "new_word", english_meaning: "A new word", chinese_meaning: "新词" },
    { word: "existing", english_meaning: "Duplicate", chinese_meaning: "重复" },
    { word: "another", english_meaning: "Another word", chinese_meaning: "另一个" }
  ]

  assert_difference("Word.count", 2) do
    post batch_create_words_url, params: { words: words_data }, as: :json
  end

  assert_response :created
  json_response = JSON.parse(response.body)
  assert_equal 2, json_response["created"].length
  assert_equal 1, json_response["failed"].length
  assert_equal "existing", json_response["failed"][0]["word"]
  assert_match(/has already been taken/, json_response["failed"][0]["errors"])
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/controllers/words_controller_test.rb -v -n test_batch_create_should_handle_partial_failures_gracefully`
Expected: FAIL with "NoMethodError: undefined method `batch_create_words_url'"

- [ ] **Step 5: Write the failing test for batch_create with empty array**

In `test/controllers/words_controller_test.rb`, add:

```ruby
test "batch_create should return error for empty words array" do
  post batch_create_words_url, params: { words: [] }, as: :json

  assert_response :unprocessable_entity
  json_response = JSON.parse(response.body)
  assert_equal "words array cannot be empty", json_response["error"]
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bin/rails test test/controllers/words_controller_test.rb -v -n test_batch_create_should_return_error_for_empty_words_array`
Expected: FAIL with "NoMethodError: undefined method `batch_create_words_url'"

- [ ] **Step 7: Write the failing test for batch_create with missing params**

In `test/controllers/words_controller_test.rb`, add:

```ruby
test "batch_create should return error for missing words param" do
  post batch_create_words_url, params: {}, as: :json

  assert_response :unprocessable_entity
  json_response = JSON.parse(response.body)
  assert_equal "words parameter is required", json_response["error"]
end
```

- [ ] **Step 8: Run test to verify it fails**

Run: `bin/rails test test/controllers/words_controller_test.rb -v -n test_batch_create_should_return_error_for_missing_words_param`
Expected: FAIL with "NoMethodError: undefined method `batch_create_words_url'"

- [ ] **Step 9: Add batch_create route**

In `config/routes.rb`, inside the `resources :words` block (after the `lookup` collection route):

```ruby
resources :words do
  collection do
    post :lookup
    post :batch_create
  end
end
```

- [ ] **Step 10: Run tests to verify routing works but controller method missing**

Run: `bin/rails test test/controllers/words_controller_test.rb -v`
Expected: FAIL with "AbstractController::ActionNotFound: The action 'batch_create' could not be found"

- [ ] **Step 11: Add batch_create action to WordsController**

In `app/controllers/words_controller.rb`, add before the `private` keyword:

```ruby
def batch_create
  words_data = params[:words]

  if words_data.nil?
    render json: { error: "words parameter is required" }, status: :unprocessable_entity
    return
  end

  unless words_data.is_a?(Array)
    render json: { error: "words must be an array" }, status: :unprocessable_entity
    return
  end

  if words_data.empty?
    render json: { error: "words array cannot be empty" }, status: :unprocessable_entity
    return
  end

  created = []
  failed = []

  words_data.each do |word_params|
    word = Word.new(
      word: word_params[:word],
      english_meaning: word_params[:english_meaning],
      chinese_meaning: word_params[:chinese_meaning]
    )

    if word.save
      created << { id: word.id, word: word.word }
    else
      failed << { 
        word: word_params[:word], 
        errors: word.errors.full_messages.join(", ")
      }
    end
  end

  render json: { created: created, failed: failed }, status: :created
end
```

- [ ] **Step 12: Run tests to verify they pass**

Run: `bin/rails test test/controllers/words_controller_test.rb -v`
Expected: All tests PASS

- [ ] **Step 13: Commit batch create endpoint**

```bash
git add app/controllers/words_controller.rb config/routes.rb test/controllers/words_controller_test.rb
git commit -m "feat: add batch_create endpoint to WordsController"
```

---

### Task 3: Create Batch Word Import Script

**Files:**
- Create: `lib/tasks/word_import.rake`
- Test: `test/lib/tasks/word_import_test.rb`

- [ ] **Step 1: Write the failing test for rake task with valid words**

Create `test/lib/tasks/word_import_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "rake"

class WordImportTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["words:batch_import"]
    @task.reenable
  end

  test "batch_import creates words from comma separated list" do
    # Mock the OpenRouterWordMeaningClient
    mock_results = [
      OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "cat",
        english_meaning: "A small carnivorous mammal",
        chinese_meaning: "猫"
      ),
      OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "dog",
        english_meaning: "A domesticated carnivorous mammal",
        chinese_meaning: "狗"
      )
    ]

    mock_client = Minitest::Mock.new
    mock_client.expect(:batch_lookup, mock_results, [["cat", "dog"]])

    OpenRouterWordMeaningClient.stub(:new, mock_client) do
      assert_difference("Word.count", 2) do
        @task.invoke("cat,dog")
      end
    end

    assert_equal "cat", Word.find_by(word: "cat").word
    assert_equal "dog", Word.find_by(word: "dog").word
    mock_client.verify
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/tasks/word_import_test.rb -v`
Expected: FAIL with "RuntimeError: Don't know how to build task 'words:batch_import'"

- [ ] **Step 3: Write the failing test for rake task with file input**

In `test/lib/tasks/word_import_test.rb`, add:

```ruby
test "batch_import creates words from file" do
  file_path = Rails.root.join("tmp", "test_words.txt")
  File.write(file_path, "apple\nbanana\ncherry")

  mock_results = [
    OpenRouterWordMeaningClient::BatchMeaningResult.new(
      word: "apple",
      english_meaning: "A round fruit",
      chinese_meaning: "苹果"
    ),
    OpenRouterWordMeaningClient::BatchMeaningResult.new(
      word: "banana",
      english_meaning: "A long yellow fruit",
      chinese_meaning: "香蕉"
    ),
    OpenRouterWordMeaningClient::BatchMeaningResult.new(
      word: "cherry",
      english_meaning: "A small round stone fruit",
      chinese_meaning: "樱桃"
    )
  ]

  mock_client = Minitest::Mock.new
  mock_client.expect(:batch_lookup, mock_results, [["apple", "banana", "cherry"]])

  OpenRouterWordMeaningClient.stub(:new, mock_client) do
    assert_difference("Word.count", 3) do
      @task.invoke("file:#{file_path}")
    end
  end

  assert Word.exists?(word: "apple")
  assert Word.exists?(word: "banana")
  assert Word.exists?(word: "cherry")
  mock_client.verify
ensure
  File.delete(file_path) if File.exist?(file_path)
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/lib/tasks/word_import_test.rb -v`
Expected: FAIL with "RuntimeError: Don't know how to build task 'words:batch_import'"

- [ ] **Step 5: Write the failing test for rake task error handling**

In `test/lib/tasks/word_import_test.rb`, add:

```ruby
test "batch_import skips existing words and reports failures" do
  Word.create!(word: "cat", english_meaning: "Existing", chinese_meaning: "已存在")

  mock_results = [
    OpenRouterWordMeaningClient::BatchMeaningResult.new(
      word: "cat",
      english_meaning: "A small carnivorous mammal",
      chinese_meaning: "猫"
    ),
    OpenRouterWordMeaningClient::BatchMeaningResult.new(
      word: "dog",
      english_meaning: "A domesticated carnivorous mammal",
      chinese_meaning: "狗"
    )
  ]

  mock_client = Minitest::Mock.new
  mock_client.expect(:batch_lookup, mock_results, [["cat", "dog"]])

  OpenRouterWordMeaningClient.stub(:new, mock_client) do
    output = capture_io do
      assert_difference("Word.count", 1) do
        @task.invoke("cat,dog")
      end
    end

    assert_match(/Successfully created 1 words/, output.join)
    assert_match(/Failed to create 1 words/, output.join)
    assert_match(/cat.*has already been taken/i, output.join)
  end

  mock_client.verify
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bin/rails test test/lib/tasks/word_import_test.rb -v`
Expected: FAIL with "RuntimeError: Don't know how to build task 'words:batch_import'"

- [ ] **Step 7: Create the rake task**

Create `lib/tasks/word_import.rake`:

```ruby
# frozen_string_literal: true

namespace :words do
  desc "Batch import words from comma-separated list or file (usage: rake words:batch_import[cat,dog] or rake words:batch_import[file:/path/to/words.txt])"
  task :batch_import, [:input] => :environment do |_t, args|
    if args[:input].blank?
      puts "Error: Please provide words as comma-separated list or file path"
      puts "Usage: rake words:batch_import[cat,dog,fish]"
      puts "   or: rake words:batch_import[file:/path/to/words.txt]"
      exit 1
    end

    words = parse_input(args[:input])

    if words.empty?
      puts "Error: No valid words found"
      exit 1
    end

    puts "Looking up meanings for #{words.length} words..."
    
    begin
      client = OpenRouterWordMeaningClient.new
      meanings = client.batch_lookup(words)
    rescue OpenRouterWordMeaningClient::Error => e
      puts "Error calling OpenRouter API: #{e.message}"
      exit 1
    end

    puts "Creating words in database..."
    
    created = []
    failed = []

    meanings.each do |meaning|
      word = Word.new(
        word: meaning.word,
        english_meaning: meaning.english_meaning,
        chinese_meaning: meaning.chinese_meaning
      )

      if word.save
        created << word
      else
        failed << { word: meaning.word, errors: word.errors.full_messages }
      end
    end

    puts "\nResults:"
    puts "Successfully created #{created.length} words"
    if failed.any?
      puts "Failed to create #{failed.length} words:"
      failed.each do |failure|
        puts "  - #{failure[:word]}: #{failure[:errors].join(', ')}"
      end
    end
  end

  def parse_input(input)
    if input.start_with?("file:")
      file_path = input.sub(/^file:/, "")
      unless File.exist?(file_path)
        puts "Error: File not found: #{file_path}"
        exit 1
      end
      File.readlines(file_path).map(&:strip).reject(&:empty?)
    else
      input.split(",").map(&:strip).reject(&:empty?)
    end
  end
end
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/lib/tasks/word_import_test.rb -v`
Expected: All tests PASS

- [ ] **Step 9: Commit batch import script**

```bash
git add lib/tasks/word_import.rake test/lib/tasks/word_import_test.rb
git commit -m "feat: add batch word import rake task"
```

---

### Task 4: Add Integration Test for End-to-End Workflow

**Files:**
- Create: `test/integration/batch_word_import_integration_test.rb`

- [ ] **Step 1: Write integration test for complete workflow**

Create `test/integration/batch_word_import_integration_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class BatchWordImportIntegrationTest < ActionDispatch::IntegrationTest
  test "complete batch import workflow with real API call structure" do
    words_to_lookup = ["elephant", "giraffe"]

    # Simulate the OpenRouter API response structure
    mock_response_inner = [
      { "word" => "elephant", "english_meaning" => "A large mammal with a trunk", "chinese_meaning" => "大象" },
      { "word" => "giraffe", "english_meaning" => "A tall mammal with a long neck", "chinese_meaning" => "长颈鹿" }
    ]
    mock_response_outer = {
      "choices" => [
        { "message" => { "content" => JSON.generate(mock_response_inner) } }
      ]
    }
    mock_http_response = OpenStruct.new(code: "200", body: JSON.generate(mock_response_outer))

    # Mock the HTTP request
    mock_requester = ->(body_json) { mock_http_response }
    client = OpenRouterWordMeaningClient.new(api_key: "test-key", requester: mock_requester)

    # Step 1: Batch lookup
    meanings = client.batch_lookup(words_to_lookup)
    assert_equal 2, meanings.length
    assert_equal "elephant", meanings[0].word
    assert_equal "giraffe", meanings[1].word

    # Step 2: Batch create via API
    words_data = meanings.map do |m|
      {
        word: m.word,
        english_meaning: m.english_meaning,
        chinese_meaning: m.chinese_meaning
      }
    end

    assert_difference("Word.count", 2) do
      post batch_create_words_url, params: { words: words_data }, as: :json
    end

    assert_response :created
    json_response = JSON.parse(response.body)
    assert_equal 2, json_response["created"].length
    assert_equal 0, json_response["failed"].length

    # Step 3: Verify words exist in database
    elephant = Word.find_by(word: "elephant")
    giraffe = Word.find_by(word: "giraffe")

    assert_not_nil elephant
    assert_equal "A large mammal with a trunk", elephant.english_meaning
    assert_equal "大象", elephant.chinese_meaning

    assert_not_nil giraffe
    assert_equal "A tall mammal with a long neck", giraffe.english_meaning
    assert_equal "长颈鹿", giraffe.chinese_meaning
  end
end
```

- [ ] **Step 2: Run integration test to verify it passes**

Run: `bin/rails test test/integration/batch_word_import_integration_test.rb -v`
Expected: PASS

- [ ] **Step 3: Commit integration test**

```bash
git add test/integration/batch_word_import_integration_test.rb
git commit -m "test: add integration test for batch word import workflow"
```

---

### Task 5: Add Documentation and Usage Examples

**Files:**
- Create: `docs/batch_word_import.md`

- [ ] **Step 1: Create documentation file**

Create `docs/batch_word_import.md`:

```markdown
# Batch Word Import

This feature allows you to import multiple words at once using the OpenRouter API for meaning lookup and batch creation in the database.

## Components

### 1. OpenRouterWordMeaningClient#batch_lookup

Looks up multiple words in a single API call.

**Usage:**

```ruby
client = OpenRouterWordMeaningClient.new
results = client.batch_lookup(["cat", "dog", "bird"])

results.each do |result|
  puts "#{result.word}: #{result.english_meaning} (#{result.chinese_meaning})"
end
```

**Features:**
- Accepts array of words
- Strips whitespace and removes duplicates
- Skips blank/nil entries
- Returns array of `BatchMeaningResult` objects

### 2. Batch Create API Endpoint

Create multiple words via HTTP POST request.

**Endpoint:** `POST /words/batch_create`

**Request Body:**

```json
{
  "words": [
    {
      "word": "apple",
      "english_meaning": "A round fruit",
      "chinese_meaning": "苹果"
    },
    {
      "word": "banana",
      "english_meaning": "A long yellow fruit",
      "chinese_meaning": "香蕉"
    }
  ]
}
```

**Response:**

```json
{
  "created": [
    { "id": 1, "word": "apple" },
    { "id": 2, "word": "banana" }
  ],
  "failed": []
}
```

**Error Handling:**

If some words fail validation (e.g., duplicates), they're reported in the `failed` array:

```json
{
  "created": [
    { "id": 1, "word": "apple" }
  ],
  "failed": [
    {
      "word": "banana",
      "errors": "Word has already been taken"
    }
  ]
}
```

### 3. Rake Task for Batch Import

Combines lookup and creation in one command.

**Usage:**

**From comma-separated list:**

```bash
bin/rails words:batch_import[cat,dog,bird]
```

**From file:**

Create a text file with one word per line:

```text
apple
banana
cherry
```

Then run:

```bash
bin/rails words:batch_import[file:path/to/words.txt]
```

**Output:**

```
Looking up meanings for 3 words...
Creating words in database...

Results:
Successfully created 3 words
```

**With failures:**

```
Looking up meanings for 3 words...
Creating words in database...

Results:
Successfully created 2 words
Failed to create 1 words:
  - cat: Word has already been taken
```

## Environment Variables

Ensure `OPENROUTER_API_KEY` is set:

```bash
export OPENROUTER_API_KEY=your_api_key_here
```

Optionally set a custom model:

```bash
export OPENROUTER_MODEL=deepseek/deepseek-v4-pro
```

## Testing

Run all batch import tests:

```bash
bin/rails test test/services/open_router_word_meaning_client_test.rb
bin/rails test test/controllers/words_controller_test.rb
bin/rails test test/lib/tasks/word_import_test.rb
bin/rails test test/integration/batch_word_import_integration_test.rb
```

## Example Workflow

1. Prepare a word list in `tmp/my_words.txt`
2. Run the import: `bin/rails words:batch_import[file:tmp/my_words.txt]`
3. Check the database: `bin/rails console` → `Word.last(5)`
```

- [ ] **Step 2: Commit documentation**

```bash
git add docs/batch_word_import.md
git commit -m "docs: add batch word import documentation"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Run all tests to verify everything passes**

Run: `bin/rails test -v`
Expected: All tests PASS

- [ ] **Step 2: Verify rake task is available**

Run: `bin/rails -T words`
Expected: Output shows `rake words:batch_import[input]`

- [ ] **Step 3: Manual smoke test with mock data**

Create test file:

```bash
echo -e "test1\ntest2\ntest3" > tmp/test_words.txt
```

Verify rake task help:

```bash
bin/rails words:batch_import
```

Expected: Shows usage instructions

---

## Self-Review

**Spec Coverage:**
- ✓ Batch lookup API in LLM service accepting list of words
- ✓ Batch creation API endpoint
- ✓ Script combining batch lookup and batch creation

**Placeholder Scan:**
- ✓ No TBD, TODO, or "implement later" placeholders
- ✓ All code blocks complete with actual implementation
- ✓ All test expectations specific and verifiable

**Type Consistency:**
- ✓ `BatchMeaningResult` used consistently across service and tests
- ✓ Controller JSON response format matches test expectations
- ✓ Rake task uses same client and model classes as controller

**File Paths:**
- ✓ All paths explicitly specified
- ✓ Test files match Rails conventions
- ✓ Documentation saved to `docs/` directory
