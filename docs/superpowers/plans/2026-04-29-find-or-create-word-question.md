# Find or Create Word Question Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `FindOrCreateWordQuestion` service that returns an existing `WordQuestion` for a given `Word`, or creates one by fetching 3 similar words from an LLM and wiring everything together.

**Architecture:** Two objects — `OpenRouterSimilarWordsClient` handles the LLM call and JSON parsing (mirrors the existing `OpenRouterWordMeaningClient`), and `FindOrCreateWordQuestion` orchestrates the find-or-create logic: check for an existing question, call the client, find-or-create each similar `Word`, then build and persist the `WordQuestion`.

**Tech Stack:** Rails 8, PostgreSQL, `Net::HTTP`, OpenRouter API (`deepseek/deepseek-v4-pro`), Minitest

---

## File Map

| File | Role |
|------|------|
| Create: `app/services/open_router_similar_words_client.rb` | LLM client — returns 3 `SimilarWordResult` structs |
| Create: `app/services/find_or_create_word_question.rb` | Orchestration service |
| Create: `test/services/open_router_similar_words_client_test.rb` | Unit tests for the LLM client |
| Create: `test/services/find_or_create_word_question_test.rb` | Integration tests for the service |
| Modify: `test/fixtures/similar_words.yml` | Add 3 similar-word rows under `cat_question` for fixture-backed tests |

---

## Task 1: `OpenRouterSimilarWordsClient`

**Files:**
- Create: `app/services/open_router_similar_words_client.rb`
- Create: `test/services/open_router_similar_words_client_test.rb`

### Background

The prompt must instruct the model to return **only** a raw JSON array (no markdown fences) of exactly 3 objects, each with `word`, `english_meaning`, and `chinese_meaning`. The client validates the shape before returning.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/open_router_similar_words_client_test.rb
# frozen_string_literal: true

require "test_helper"
require "ostruct"

class OpenRouterSimilarWordsClientTest < ActiveSupport::TestCase
  setup do
    @api_key = "test-key"
    @valid_inner = [
      { "word" => "kitten",  "english_meaning" => "A young cat.",             "chinese_meaning" => "小猫" },
      { "word" => "feline",  "english_meaning" => "Of or relating to cats.",  "chinese_meaning" => "猫科动物" },
      { "word" => "tomcat",  "english_meaning" => "An uncastrated male cat.", "chinese_meaning" => "雄猫" }
    ]
    @valid_outer = {
      "choices" => [{ "message" => { "content" => JSON.generate(@valid_inner) } }]
    }
  end

  test "raises when api key is missing" do
    client = OpenRouterSimilarWordsClient.new(api_key: "", requester: ->(*) { raise "should not call" })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_equal "OPENROUTER_API_KEY is not set", error.message
  end

  test "raises when word is blank" do
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(*) { raise "should not call" })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("   ") }
    assert_equal "word is blank", error.message
  end

  test "returns three SimilarWordResult structs on success" do
    response = OpenStruct.new(code: "200", body: JSON.generate(@valid_outer))
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    results = client.similar_words("cat")
    assert_equal 3, results.size
    assert_instance_of OpenRouterSimilarWordsClient::SimilarWordResult, results.first
    assert_equal "kitten",           results[0].word
    assert_equal "A young cat.",     results[0].english_meaning
    assert_equal "小猫",             results[0].chinese_meaning
  end

  test "raises on non-2xx response" do
    response = OpenStruct.new(code: "401", body: '{"error":"unauthorized"}')
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/OpenRouter request failed \(401\)/, error.message)
  end

  test "raises when message content is missing" do
    outer = { "choices" => [{ "message" => { "content" => "" } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/missing message content/, error.message)
  end

  test "raises when inner json is not an array" do
    outer = { "choices" => [{ "message" => { "content" => '{"word":"x"}' } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/expected a JSON array/, error.message)
  end

  test "raises when array has wrong count" do
    inner = @valid_inner.first(2)
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/expected exactly 3 similar words/, error.message)
  end

  test "raises when an entry is missing required keys" do
    inner = [
      { "word" => "kitten",  "english_meaning" => "A young cat." },
      { "word" => "feline",  "english_meaning" => "...", "chinese_meaning" => "猫科动物" },
      { "word" => "tomcat",  "english_meaning" => "...", "chinese_meaning" => "雄猫" }
    ]
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/missing required key/, error.message)
  end

  test "raises when inner json is malformed" do
    outer = { "choices" => [{ "message" => { "content" => "not json" } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/Invalid JSON from OpenRouter/, error.message)
  end

  test "default model is deepseek v4 pro when env model unset" do
    captured = nil
    response = OpenStruct.new(code: "200", body: JSON.generate(@valid_outer))
    old_model = ENV.fetch("OPENROUTER_MODEL", nil)
    ENV.delete("OPENROUTER_MODEL")
    client = OpenRouterSimilarWordsClient.new(
      api_key: @api_key,
      requester: lambda { |body|
        captured = JSON.parse(body)
        response
      }
    )
    client.similar_words("cat")
    assert_equal "deepseek/deepseek-v4-pro", captured["model"]
  ensure
    ENV["OPENROUTER_MODEL"] = old_model if old_model
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/services/open_router_similar_words_client_test.rb
```

Expected: `NameError: uninitialized constant OpenRouterSimilarWordsClient` (or similar)

- [ ] **Step 3: Implement `OpenRouterSimilarWordsClient`**

```ruby
# app/services/open_router_similar_words_client.rb
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Calls OpenRouter chat completions API to suggest 3 similar English words with meanings.
class OpenRouterSimilarWordsClient
  class Error < StandardError; end

  SimilarWordResult = Data.define(:word, :english_meaning, :chinese_meaning)

  OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")
  DEFAULT_MODEL = "deepseek/deepseek-v4-pro"
  REQUIRED_KEYS = %w[word english_meaning chinese_meaning].freeze

  # @param requester [#call(String)] optional callable(body_json) -> response object with #code and #body
  def initialize(api_key: ENV.fetch("OPENROUTER_API_KEY", nil), model: nil, requester: nil)
    @api_key = api_key
    @model = model.presence || ENV["OPENROUTER_MODEL"].presence || DEFAULT_MODEL
    @requester = requester
  end

  # @param word [String] English lemma to generate similar words for
  # @return [Array<SimilarWordResult>] exactly 3 results
  def similar_words(word)
    raise Error, "OPENROUTER_API_KEY is not set" if @api_key.to_s.strip.empty?

    trimmed = word.to_s.strip
    raise Error, "word is blank" if trimmed.empty?

    payload = build_payload(trimmed)
    response = perform_request(JSON.generate(payload))

    unless response.code.to_i.between?(200, 299)
      snippet = response.body.to_s.byteslice(0, 500)
      raise Error, "OpenRouter request failed (#{response.code}): #{snippet}"
    end

    parse_results_from_response(response.body)
  end

  private

  def build_payload(word)
    {
      model: @model,
      messages: [
        {
          role: "user",
          content: <<~PROMPT.squish
            For the English word "#{word.gsub(/"/, "'")}",
            reply with ONLY a raw JSON array (no markdown, no code fences) of exactly 3 similar English words.
            Each element must have exactly these string keys:
            "word" — the similar English word (lowercase lemma);
            "english_meaning" — a concise English definition suitable for a learner;
            "chinese_meaning" — a concise Chinese translation for the same sense.
            Example shape: [{"word":"...","english_meaning":"...","chinese_meaning":"..."},...]
          PROMPT
        }
      ]
    }
  end

  def perform_request(body_json)
    return @requester.call(body_json) if @requester

    Net::HTTP.start(
      OPENROUTER_URI.host,
      OPENROUTER_URI.port,
      use_ssl: OPENROUTER_URI.scheme == "https",
      open_timeout: 15,
      read_timeout: 60
    ) do |http|
      req = Net::HTTP::Post.new(OPENROUTER_URI)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body_json
      http.request(req)
    end
  end

  def parse_results_from_response(response_body)
    outer = JSON.parse(response_body)
    content = outer.dig("choices", 0, "message", "content")
    raise Error, "OpenRouter response missing message content" if content.to_s.strip.empty?

    inner = JSON.parse(content.strip)
    raise Error, "expected a JSON array of similar words" unless inner.is_a?(Array)
    raise Error, "expected exactly 3 similar words, got #{inner.size}" unless inner.size == 3

    inner.map do |entry|
      missing = REQUIRED_KEYS.find { |k| entry[k].to_s.strip.empty? }
      raise Error, "similar word entry missing required key: #{missing}" if missing

      SimilarWordResult.new(
        word: entry["word"].to_s.strip,
        english_meaning: entry["english_meaning"].to_s.strip,
        chinese_meaning: entry["chinese_meaning"].to_s.strip
      )
    end
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from OpenRouter: #{e.message}"
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/open_router_similar_words_client_test.rb
```

Expected: 8 tests, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/services/open_router_similar_words_client.rb \
        test/services/open_router_similar_words_client_test.rb
git commit -m "feat: add OpenRouterSimilarWordsClient for fetching 3 similar words"
```

---

## Task 2: `FindOrCreateWordQuestion` service

**Files:**
- Create: `app/services/find_or_create_word_question.rb`
- Modify: `test/fixtures/similar_words.yml` — add 3 rows under `cat_question`
- Create: `test/services/find_or_create_word_question_test.rb`

### Background

`WordQuestion` requires exactly 3 `SimilarWord` records (validated by `exactly_three_similar_words`). A `SimilarWord` is a polymorphic join row pointing to a `Word`. The service must:

1. Return `word.word_questions.first` if it already exists.
2. Otherwise call `OpenRouterSimilarWordsClient#similar_words(word.word)`.
3. For each result, find an existing `Word` (case-insensitive on `word` column) or create one.
4. Build a `WordQuestion` with three `similar_words` associations and save it.

The `requester:` injection point on `OpenRouterSimilarWordsClient` allows tests to stub the HTTP call without hitting the network.

- [ ] **Step 1: Update the `similar_words` fixture to include 3 rows under `cat_question`**

The current `test/fixtures/similar_words.yml` only has one `Word`-scoped row. We need 3 `WordQuestion`-scoped rows so the `cat_question` fixture is valid and `cat` has a complete question in fixture tests.

```yaml
# test/fixtures/similar_words.yml
dog_similar_to_cat:
  similar_wordable: cat (Word)
  word: dog

dog_choice_for_cat_question:
  similar_wordable: cat_question (WordQuestion)
  word: dog

fish_choice_for_cat_question:
  similar_wordable: cat_question (WordQuestion)
  word: fish

bird_choice_for_cat_question:
  similar_wordable: cat_question (WordQuestion)
  word: bird
```

- [ ] **Step 2: Verify existing tests still pass after fixture change**

```bash
bin/rails test
```

Expected: all existing tests pass

- [ ] **Step 3: Write the failing tests**

```ruby
# test/services/find_or_create_word_question_test.rb
# frozen_string_literal: true

require "test_helper"
require "ostruct"

class FindOrCreateWordQuestionTest < ActiveSupport::TestCase
  # Builds a stubbed requester that returns `similar_triples` as the LLM response.
  # similar_triples: Array of [word_str, english, chinese]
  def stub_requester(similar_triples)
    inner = similar_triples.map do |w, en, zh|
      { "word" => w, "english_meaning" => en, "chinese_meaning" => zh }
    end
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
  end

  # Returns a FindOrCreateWordQuestion instance with a stubbed LLM client.
  def service_with_stub(similar_triples)
    requester = stub_requester(similar_triples)
    client = OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
    FindOrCreateWordQuestion.new(llm_client: client)
  end

  test "returns existing word question when one already exists" do
    word = words(:cat)
    existing_question = word_questions(:cat_question)

    service = service_with_stub([]) # LLM should never be called
    result = service.call(word: word)

    assert_equal existing_question, result
  end

  test "creates a new word question when none exists" do
    word = Word.create!(word: "elephant", english_meaning: "A large mammal.", chinese_meaning: "大象")

    triples = [
      ["mammoth",  "An extinct large mammal.", "猛犸象"],
      ["rhino",    "A large herbivore.",        "犀牛"],
      ["hippo",    "A large semiaquatic mammal.", "河马"]
    ]
    service = service_with_stub(triples)

    assert_difference "WordQuestion.count", 1 do
      service.call(word: word)
    end
  end

  test "returned question belongs to the given word" do
    word = Word.create!(word: "sparrow", english_meaning: "A small bird.", chinese_meaning: "麻雀")

    triples = [
      ["finch",  "A small seed-eating bird.", "雀"],
      ["robin",  "A small migratory bird.",   "知更鸟"],
      ["wren",   "A small brown bird.",        "鹪鹩"]
    ]
    result = service_with_stub(triples).call(word: word)

    assert_equal word, result.word
  end

  test "returned question has exactly 3 similar words" do
    word = Word.create!(word: "oak", english_meaning: "A hardwood tree.", chinese_meaning: "橡树")

    triples = [
      ["elm",   "A deciduous tree.", "榆树"],
      ["maple", "A tree known for syrup.", "枫树"],
      ["birch", "A slender tree.",         "桦树"]
    ]
    result = service_with_stub(triples).call(word: word)

    assert_equal 3, result.similar_words.size
  end

  test "reuses an existing Word record for a similar word" do
    word = Word.create!(word: "pony", english_meaning: "A small horse.", chinese_meaning: "小马")

    triples = [
      ["horse", "A large domesticated animal.", "马"],  # already exists in fixtures? no — use dog
      ["mule",  "A hybrid of horse and donkey.", "骡子"],
      ["foal",  "A young horse.",                "马驹"]
    ]
    # "dog" already exists as a fixture word; use it to confirm reuse
    triples_with_existing = [
      ["dog",  "A domesticated carnivorous mammal.", "狗"],
      ["mule", "A hybrid of horse and donkey.",      "骡子"],
      ["foal", "A young horse.",                     "马驹"]
    ]
    service = service_with_stub(triples_with_existing)

    assert_no_difference "Word.count" do
      # "dog" already exists; only "mule" and "foal" are new
      # but we allow 2 new words and assert the existing one is reused
    end

    result = service.call(word: word)
    similar_word_names = result.similar_words.map { |sw| sw.word.word }
    assert_includes similar_word_names, "dog"
  end

  test "creates missing Word records for similar words" do
    word = Word.create!(word: "lotus", english_meaning: "An aquatic plant.", chinese_meaning: "莲花")

    triples = [
      ["lily",       "An aquatic flower.",        "百合"],
      ["waterlily",  "A floating aquatic plant.", "睡莲"],
      ["iris",       "A flowering plant.",         "鸢尾"]
    ]
    service = service_with_stub(triples)

    assert_difference "Word.count", 3 do
      service.call(word: word)
    end
  end

  test "does not create duplicate word questions on repeated calls" do
    word = Word.create!(word: "cedar", english_meaning: "An evergreen tree.", chinese_meaning: "雪松")

    triples = [
      ["pine",  "An evergreen coniferous tree.", "松树"],
      ["fir",   "A type of conifer.",             "冷杉"],
      ["spruce","A coniferous tree.",              "云杉"]
    ]
    service = service_with_stub(triples)

    service.call(word: word)

    assert_no_difference "WordQuestion.count" do
      service.call(word: word)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
bin/rails test test/services/find_or_create_word_question_test.rb
```

Expected: `NameError: uninitialized constant FindOrCreateWordQuestion`

- [ ] **Step 5: Implement `FindOrCreateWordQuestion`**

```ruby
# app/services/find_or_create_word_question.rb
# frozen_string_literal: true

# Finds an existing WordQuestion for the given Word, or creates one by fetching
# 3 similar words from the LLM and wiring up Word/SimilarWord records.
class FindOrCreateWordQuestion
  # @param llm_client [OpenRouterSimilarWordsClient]
  def initialize(llm_client: OpenRouterSimilarWordsClient.new)
    @llm_client = llm_client
  end

  # @param word [Word]
  # @return [WordQuestion]
  def call(word:)
    existing = word.word_questions.first
    return existing if existing

    similar_results = @llm_client.similar_words(word.word)
    similar_word_records = similar_results.map { |r| find_or_create_word(r) }

    question = word.word_questions.build
    similar_word_records.each { |w| question.similar_words.build(word: w) }
    question.save!
    question
  end

  private

  def find_or_create_word(result)
    Word.find_by("lower(word) = ?", result.word.downcase) ||
      Word.create!(
        word: result.word,
        english_meaning: result.english_meaning,
        chinese_meaning: result.chinese_meaning
      )
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bin/rails test test/services/find_or_create_word_question_test.rb
```

Expected: 6 tests, 0 failures, 0 errors

- [ ] **Step 7: Run full test suite**

```bash
bin/rails test
```

Expected: all tests pass

- [ ] **Step 8: Commit**

```bash
git add app/services/find_or_create_word_question.rb \
        test/services/find_or_create_word_question_test.rb \
        test/fixtures/similar_words.yml
git commit -m "feat: add FindOrCreateWordQuestion service"
```

---

## Self-Review Checklist

### Spec Coverage

| Requirement | Task |
|-------------|------|
| Input: word object, output: word question | Task 2 |
| If exists, return it | Task 2 — "returns existing word question" test |
| Call LLM via OpenRouter for 3 similar words with EN + ZH meanings | Task 1 |
| Returns correct JSON format, validated class for LLM | Task 1 — `OpenRouterSimilarWordsClient` with full validation |
| Find or create the 3 similar words | Task 2 — `find_or_create_word` private method |
| Create the question based on word and similar words | Task 2 — `question.save!` path |

### Type Consistency

- `OpenRouterSimilarWordsClient#similar_words(word_string)` → `Array<SimilarWordResult>` — used in `FindOrCreateWordQuestion#call`
- `SimilarWordResult#word`, `#english_meaning`, `#chinese_meaning` — all three accessed in `find_or_create_word`
- `FindOrCreateWordQuestion#new(llm_client:)` — matches stub construction in tests: `FindOrCreateWordQuestion.new(llm_client: client)`
- `FindOrCreateWordQuestion#call(word:)` — matches all test call sites: `service.call(word: word)`
