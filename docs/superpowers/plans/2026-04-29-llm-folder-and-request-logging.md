# LLM Folder Restructure and Request Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move LLM-related services into a dedicated `llm` folder and add start/end/duration logging around shared request sending.

**Architecture:** Introduce a new `Llm` namespace under `app/services/llm` and move both OpenRouter clients there to satisfy Rails autoload conventions. Extract shared HTTP request behavior into `Llm::RequestSender#send_request`, then add structured logs before and after each LLM request (including model, prompt, start time, end time, and duration in milliseconds). Update all application/test references to the new namespaced classes.

**Tech Stack:** Ruby on Rails, ActiveSupport::Concern, Net::HTTP, Minitest

---

## File Structure Map

- Create: `app/services/llm/request_sender.rb` (shared `send_request` with logging and HTTP execution)
- Create: `app/services/llm/open_router_word_meaning_client.rb` (moved + namespaced meaning client)
- Create: `app/services/llm/open_router_similar_words_client.rb` (moved + namespaced similar-words client)
- Modify: `app/services/find_or_create_word_question.rb` (switch default client to `Llm::OpenRouterSimilarWordsClient`)
- Modify: `app/controllers/words_controller.rb` (switch class attribute + rescues to `Llm::OpenRouterWordMeaningClient`)
- Modify: `lib/tasks/words_batch_import.rake` (switch client + rescue constants)
- Modify: `test/services/open_router_word_meaning_client_test.rb` (new class name + logging tests)
- Modify: `test/services/open_router_similar_words_client_test.rb` (new class name + logging tests)
- Modify: `test/services/find_or_create_word_question_test.rb` (new client class reference)
- Modify: `test/controllers/words_controller_test.rb` (fake/raising clients use namespaced result/error constants)
- Modify: `test/lib/tasks/words_batch_import_test.rb` (namespaced constants)
- Modify: `README.md` (update client class names in docs)
- Delete: `app/services/open_router_word_meaning_client.rb`
- Delete: `app/services/open_router_similar_words_client.rb`

---

### Task 1: Move LLM clients into `Llm` namespace with failing-reference tests first

**Files:**
- Modify: `test/services/open_router_word_meaning_client_test.rb`
- Modify: `test/services/open_router_similar_words_client_test.rb`
- Modify: `test/services/find_or_create_word_question_test.rb`
- Modify: `test/controllers/words_controller_test.rb`
- Modify: `test/lib/tasks/words_batch_import_test.rb`

- [ ] **Step 1: Update word meaning client test class/constant references (failing first)**

```ruby
# test/services/open_router_word_meaning_client_test.rb
class Llm::OpenRouterWordMeaningClientTest < ActiveSupport::TestCase
  test "lookup raises when api key is missing" do
    client = Llm::OpenRouterWordMeaningClient.new(api_key: "", requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_equal "OPENROUTER_API_KEY is not set", error.message
  end
end
```

- [ ] **Step 2: Update similar words client test class/constant references (failing first)**

```ruby
# test/services/open_router_similar_words_client_test.rb
class Llm::OpenRouterSimilarWordsClientTest < ActiveSupport::TestCase
  test "similar_words raises when api key is missing" do
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: "", requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_equal "OPENROUTER_API_KEY is not set", error.message
  end
end
```

- [ ] **Step 3: Update downstream tests to namespaced constants (failing first)**

```ruby
# test/services/find_or_create_word_question_test.rb
llm_client = Llm::OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)

# test/controllers/words_controller_test.rb
Llm::OpenRouterWordMeaningClient::MeaningResult.new(...)
raise Llm::OpenRouterWordMeaningClient::Error, "API down"

# test/lib/tasks/words_batch_import_test.rb
Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(...)
Llm::OpenRouterWordMeaningClient.stub(:new, mock_client) do
  @task.invoke("cat,dog")
end
```

- [ ] **Step 4: Run targeted tests to confirm constant-resolution failures before implementation**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb test/services/find_or_create_word_question_test.rb test/controllers/words_controller_test.rb test/lib/tasks/words_batch_import_test.rb -v`
Expected: FAIL with `NameError` or uninitialized constants under `Llm::...` (this confirms tests now describe desired structure).

- [ ] **Step 5: Commit failing-test reference updates**

```bash
git add test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb test/services/find_or_create_word_question_test.rb test/controllers/words_controller_test.rb test/lib/tasks/words_batch_import_test.rb
git commit -m "test: point LLM client tests to new Llm namespace"
```

---

### Task 2: Implement shared `Llm::RequestSender#send_request` with start/end/duration logs

**Files:**
- Create: `app/services/llm/request_sender.rb`
- Modify: `test/services/open_router_word_meaning_client_test.rb`
- Modify: `test/services/open_router_similar_words_client_test.rb`

- [ ] **Step 1: Add failing test for start log (model + prompt + start time)**

```ruby
test "lookup logs request start with model and prompt" do
  logs = []
  logger = ActiveSupport::Logger.new(StringIO.new)
  logger.formatter = proc { |_severity, _time, _progname, msg| logs << msg; "" }

  response = OpenStruct.new(code: "200", body: JSON.generate(
    "choices" => [{ "message" => { "content" => '{"english_meaning":"x","chinese_meaning":"y"}' } }]
  ))

  Rails.stub(:logger, logger) do
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })
    client.lookup("cat")
  end

  assert logs.any? { |msg| msg.include?("llm.request.start") && msg.include?("model=") && msg.include?("prompt=") }
end
```

- [ ] **Step 2: Add failing test for end log (end time + duration)**

```ruby
test "similar_words logs request end with end_time and duration_ms" do
  logs = []
  logger = ActiveSupport::Logger.new(StringIO.new)
  logger.formatter = proc { |_severity, _time, _progname, msg| logs << msg; "" }

  response = OpenStruct.new(code: "200", body: JSON.generate(@valid_outer))

  Rails.stub(:logger, logger) do
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
    client.similar_words("cat")
  end

  assert logs.any? { |msg| msg.include?("llm.request.finish") && msg.include?("end_time=") && msg.include?("duration_ms=") }
end
```

- [ ] **Step 3: Run targeted tests to verify they fail before request-logging implementation**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb -v`
Expected: FAIL because expected `llm.request.start`/`llm.request.finish` log entries do not exist yet.

- [ ] **Step 4: Implement shared request sender with required logging fields**

```ruby
# app/services/llm/request_sender.rb
# frozen_string_literal: true

module Llm
  module RequestSender
    private

    def send_request(body_json:, model:, prompt:)
      if @requester
        start_request_log(model: model, prompt: prompt)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = @requester.call(body_json)
        finish_request_log(started_at: started_at)
        return response
      end

      start_request_log(model: model, prompt: prompt)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Net::HTTP.start(
        self.class::OPENROUTER_URI.host,
        self.class::OPENROUTER_URI.port,
        use_ssl: self.class::OPENROUTER_URI.scheme == "https",
        open_timeout: 15,
        read_timeout: 60
      ) do |http|
        req = Net::HTTP::Post.new(self.class::OPENROUTER_URI)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@api_key}"
        req.body = body_json
        http.request(req)
      end
      finish_request_log(started_at: started_at)
      response
    end

    def start_request_log(model:, prompt:)
      Rails.logger.info("llm.request.start start_time=#{Time.current.iso8601(3)} model=#{model} prompt=#{prompt}")
    end

    def finish_request_log(started_at:)
      ended_at = Time.current
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      Rails.logger.info("llm.request.finish end_time=#{ended_at.iso8601(3)} duration_ms=#{duration_ms}")
    end
  end
end
```

- [ ] **Step 5: Run targeted tests to verify new logging tests pass**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb -v`
Expected: PASS for new logging assertions and existing behavior tests.

- [ ] **Step 6: Commit shared request sender and logging tests**

```bash
git add app/services/llm/request_sender.rb test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb
git commit -m "feat: add shared LLM send_request logging start and duration"
```

---

### Task 3: Move both OpenRouter clients into `app/services/llm` and reuse `send_request`

**Files:**
- Create: `app/services/llm/open_router_word_meaning_client.rb`
- Create: `app/services/llm/open_router_similar_words_client.rb`
- Delete: `app/services/open_router_word_meaning_client.rb`
- Delete: `app/services/open_router_similar_words_client.rb`

- [ ] **Step 1: Create namespaced word meaning client using shared `send_request`**

```ruby
# app/services/llm/open_router_word_meaning_client.rb
module Llm
  class OpenRouterWordMeaningClient
    include RequestSender

    class Error < StandardError; end
    MeaningResult = Data.define(:english_meaning, :chinese_meaning)
    BatchMeaningResult = Data.define(:word, :english_meaning, :chinese_meaning)

    OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")
    DEFAULT_MODEL = "deepseek/deepseek-v4-pro"

    def lookup(word)
      # ... existing validation
      payload = build_payload(trimmed)
      body_json = JSON.generate(payload)
      response = send_request(body_json: body_json, model: @model, prompt: payload.dig(:messages, 0, :content))
      # ... existing response handling
    end
  end
end
```

- [ ] **Step 2: Create namespaced similar words client using shared `send_request`**

```ruby
# app/services/llm/open_router_similar_words_client.rb
module Llm
  class OpenRouterSimilarWordsClient
    include RequestSender

    class Error < StandardError; end
    SimilarWordResult = Data.define(:word, :english_meaning, :chinese_meaning)

    OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")
    DEFAULT_MODEL = "deepseek/deepseek-v4-pro"

    def similar_words(word)
      # ... existing validation
      payload = build_payload(trimmed)
      body_json = JSON.generate(payload)
      response = send_request(body_json: body_json, model: @model, prompt: payload.dig(:messages, 0, :content))
      # ... existing response handling
    end
  end
end
```

- [ ] **Step 3: Remove obsolete top-level client files**

Run:
```bash
rm app/services/open_router_word_meaning_client.rb app/services/open_router_similar_words_client.rb
```
Expected: Files removed; only namespaced files remain under `app/services/llm`.

- [ ] **Step 4: Run service tests for both moved clients**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb -v`
Expected: PASS with no `Zeitwerk::NameError` and all existing parsing/validation tests still green.

- [ ] **Step 5: Commit client move and send_request reuse**

```bash
git add app/services/llm/open_router_word_meaning_client.rb app/services/llm/open_router_similar_words_client.rb app/services/open_router_word_meaning_client.rb app/services/open_router_similar_words_client.rb
git commit -m "refactor: move openrouter clients into llm namespace"
```

---

### Task 4: Update all app wiring to use namespaced clients

**Files:**
- Modify: `app/services/find_or_create_word_question.rb`
- Modify: `app/controllers/words_controller.rb`
- Modify: `lib/tasks/words_batch_import.rake`
- Modify: `README.md`

- [ ] **Step 1: Update service dependency injection default**

```ruby
# app/services/find_or_create_word_question.rb
def initialize(llm_client: Llm::OpenRouterSimilarWordsClient.new)
  @llm_client = llm_client
end
```

- [ ] **Step 2: Update controller class attribute and error rescues**

```ruby
# app/controllers/words_controller.rb
class_attribute :meaning_client_class, default: Llm::OpenRouterWordMeaningClient

rescue Llm::OpenRouterWordMeaningClient::Error => e
  render json: { error: e.message }, status: :unprocessable_entity
end
```

- [ ] **Step 3: Update rake task client construction and rescue constant**

```ruby
# lib/tasks/words_batch_import.rake
client = Llm::OpenRouterWordMeaningClient.new
meanings = client.batch_lookup(words)
rescue Llm::OpenRouterWordMeaningClient::Error => e
  puts "Batch lookup failed: #{e.message}"
  exit 1
```

- [ ] **Step 4: Update README class-name references**

```markdown
# README.md
The OpenRouter clients (`Llm::OpenRouterWordMeaningClient` and `Llm::OpenRouterSimilarWordsClient`) read these env vars:
```

- [ ] **Step 5: Run focused app-layer tests**

Run: `bin/rails test test/services/find_or_create_word_question_test.rb test/controllers/words_controller_test.rb test/lib/tasks/words_batch_import_test.rb -v`
Expected: PASS with all references resolved through `Llm::...`.

- [ ] **Step 6: Commit app wiring updates**

```bash
git add app/services/find_or_create_word_question.rb app/controllers/words_controller.rb lib/tasks/words_batch_import.rake README.md
git commit -m "refactor: wire app to namespaced llm clients"
```

---

### Task 5: Full verification and cleanup

**Files:**
- Verify previously changed files

- [ ] **Step 1: Run full relevant test suite**

Run: `bin/rails test test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb test/services/find_or_create_word_question_test.rb test/controllers/words_controller_test.rb test/lib/tasks/words_batch_import_test.rb -v`
Expected: PASS all tests.

- [ ] **Step 2: Run linters for changed files (if configured)**

Run: `bin/rubocop app/services/llm app/services/find_or_create_word_question.rb app/controllers/words_controller.rb lib/tasks/words_batch_import.rake test/services/open_router_word_meaning_client_test.rb test/services/open_router_similar_words_client_test.rb test/services/find_or_create_word_question_test.rb test/controllers/words_controller_test.rb test/lib/tasks/words_batch_import_test.rb`
Expected: No offenses, or only pre-existing offenses unrelated to this change.

- [ ] **Step 3: Quick manual smoke test for logging output**

Run: `bin/rails runner 'client = Llm::OpenRouterWordMeaningClient.new(api_key: "x", requester: ->(_) { OpenStruct.new(code: "500", body: "{\"error\":\"x\"}") }); begin; client.lookup("cat"); rescue; end'`
Expected: App logs include one `llm.request.start ... model=... prompt=...` line and one `llm.request.finish ... end_time=... duration_ms=...` line.

- [ ] **Step 4: Final commit if verification required changes**

```bash
git add -A
git commit -m "test: verify llm folder move and request logging behavior"
```

---

## Self-Review

- **Spec coverage:** Covered creating an `llm` folder, moving LLM files into it, reusing a shared `send_request` method, and logging request start (with model and prompt) plus finish (with end time and duration).
- **Placeholder scan:** No TBD/TODO placeholders; every code-change step contains concrete code and every validation step has explicit commands and expected outcomes.
- **Type consistency:** All references consistently use `Llm::OpenRouterWordMeaningClient` and `Llm::OpenRouterSimilarWordsClient`; shared method naming consistently uses `send_request`.

Plan complete and saved to `docs/superpowers/plans/2026-04-29-llm-folder-and-request-logging.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
