# Word Pronunciation Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend word lookup so the LLM returns pronunciation, persist it on words, and let users play pronunciation audio from the word form.

**Architecture:** Keep the existing Rails-first server-rendered flow. The OpenRouter client returns one additional field (`pronunciation`) for both single and batch lookup, `WordsController` passes it through, and `Word` persists it as an optional attribute. The `new` word page renders pronunciation text and a play button that uses browser speech synthesis with `SpeechSynthesisUtterance`.

**Tech Stack:** Ruby on Rails 8.1, ERB views, Active Record migrations, Minitest (controller + service + model tests), browser Web Speech API (`speechSynthesis`).

---

## File Structure

- Create: `db/migrate/<timestamp>_add_pronunciation_to_words.rb` - add nullable `pronunciation` column for persisted words.
- Modify: `db/schema.rb` - schema snapshot after migration.
- Modify: `app/models/word.rb` - validate pronunciation length/format boundaries without making it required.
- Modify: `app/services/llm/open_router_word_meaning_client.rb` - ask LLM for pronunciation and parse it.
- Modify: `app/controllers/words_controller.rb` - assign and permit pronunciation in lookup/create/batch_create/batch_lookup responses.
- Modify: `app/views/words/_form.html.erb` - show pronunciation field and play button.
- Modify: `app/views/words/new.html.erb` - include lightweight page script for playback behavior.
- Modify: `app/assets/stylesheets/application.css` - style pronunciation row and play button.
- Modify: `test/services/open_router_word_meaning_client_test.rb` - enforce pronunciation parsing.
- Modify: `test/controllers/words_controller_test.rb` - verify lookup/batch payload and UI behavior includes pronunciation.
- Create: `test/models/word_test.rb` additions for pronunciation validation and persistence behavior.

## Task 1: Add Pronunciation To Persistence Layer

**Files:**
- Create: `db/migrate/<timestamp>_add_pronunciation_to_words.rb`
- Modify: `app/models/word.rb`
- Modify: `db/schema.rb`
- Test: `test/models/word_test.rb`

- [ ] **Step 1: Write failing model tests for pronunciation behavior**

Add these tests in `test/models/word_test.rb`:

```ruby
  test "word remains valid without pronunciation" do
    word = Word.new(
      word: "harbor_#{SecureRandom.hex(4)}",
      english_meaning: "a place for ships",
      chinese_meaning: "港口"
    )

    assert word.valid?
  end

  test "word accepts pronunciation when provided" do
    word = Word.new(
      word: "resilient_#{SecureRandom.hex(4)}",
      english_meaning: "able to recover quickly",
      chinese_meaning: "有韧性的",
      pronunciation: "/rɪˈzɪliənt/"
    )

    assert word.valid?
  end

  test "word rejects overly long pronunciation" do
    word = Word.new(
      word: "overflow_#{SecureRandom.hex(4)}",
      english_meaning: "to spill over",
      chinese_meaning: "溢出",
      pronunciation: "a" * 256
    )

    assert_not word.valid?
    assert_includes word.errors[:pronunciation], "is too long (maximum is 255 characters)"
  end
```

- [ ] **Step 2: Run model test file to confirm failures**

Run:

```bash
bin/rails test test/models/word_test.rb
```

Expected: failures because `pronunciation` attribute/validation does not exist yet.

- [ ] **Step 3: Create migration for pronunciation column**

Generate migration:

```bash
bin/rails generate migration AddPronunciationToWords pronunciation:string
```

Replace generated migration body with:

```ruby
class AddPronunciationToWords < ActiveRecord::Migration[8.1]
  def change
    add_column :words, :pronunciation, :string
  end
end
```

- [ ] **Step 4: Add model validation**

Update `app/models/word.rb`:

```ruby
class Word < ApplicationRecord
  attr_accessor :skip_create_word_question_job

  has_many :word_questions, dependent: :destroy
  has_one :word_recall_state, dependent: :destroy

  validates :word, presence: true, uniqueness: { case_sensitive: false }
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true
  validates :pronunciation, length: { maximum: 255 }, allow_blank: true

  after_create :create_initial_recall_state
  after_create_commit :enqueue_create_word_question_job, unless: :skip_create_word_question_job
```

- [ ] **Step 5: Run migration and rerun model tests**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/word_test.rb
```

Expected: migration succeeds and `word_test.rb` passes.

- [ ] **Step 6: Commit checkpoint**

```bash
git add db/migrate db/schema.rb app/models/word.rb test/models/word_test.rb
git commit -m "Add optional pronunciation field to words"
```

## Task 2: Make LLM Return Pronunciation

**Files:**
- Modify: `app/services/llm/open_router_word_meaning_client.rb`
- Test: `test/services/open_router_word_meaning_client_test.rb`

- [ ] **Step 1: Write failing service tests for pronunciation**

In `test/services/open_router_word_meaning_client_test.rb`, update success fixtures and assertions:

```ruby
inner = {
  "english_meaning" => "A small carnivorous mammal.",
  "chinese_meaning" => "猫",
  "pronunciation" => "/kæt/"
}
```

And add:

```ruby
assert_equal "/kæt/", result.pronunciation
```

For batch success fixtures, update each item:

```ruby
{ "word" => "cat", "english_meaning" => "A small carnivorous mammal.", "chinese_meaning" => "猫", "pronunciation" => "/kæt/" }
```

Then assert:

```ruby
assert_equal "/dɔɡ/", results[1].pronunciation
```

Add a missing-field test:

```ruby
test "lookup raises when pronunciation missing" do
  outer = { "choices" => [ { "message" => { "content" => '{"english_meaning":"x","chinese_meaning":"y"}' } } ] }
  response = OpenStruct.new(code: "200", body: JSON.generate(outer))
  client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

  error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
  assert_match(/missing english_meaning or chinese_meaning or pronunciation/, error.message)
end
```

- [ ] **Step 2: Run service test file and confirm failures**

Run:

```bash
bin/rails test test/services/open_router_word_meaning_client_test.rb
```

Expected: failures because result structs and parsers do not include pronunciation.

- [ ] **Step 3: Implement pronunciation in OpenRouter client**

In `app/services/llm/open_router_word_meaning_client.rb`, apply these updates:

```ruby
MeaningResult = Data.define(:english_meaning, :chinese_meaning, :pronunciation)
BatchMeaningResult = Data.define(:word, :english_meaning, :chinese_meaning, :pronunciation)
```

Update single lookup prompt segment:

```ruby
content: <<~PROMPT.squish
  For the English word "#{word.gsub(/\"/, "'")}", reply with ONLY a single JSON object (no markdown, no code fences) with exactly three string keys:
  "english_meaning" — a concise English definition or gloss suitable for a learner;
  "chinese_meaning" — a concise Chinese translation or gloss for the same sense;
  "pronunciation" — a concise pronunciation string for the English word (IPA preferred, otherwise clear phonetic spelling).
  Example shape: {"english_meaning":"...","chinese_meaning":"...","pronunciation":"..."}
PROMPT
```

Update batch prompt segment:

```ruby
content: <<~PROMPT.squish
  For the following list of English words: [#{escaped_words}], reply with ONLY a JSON array (no markdown, no code fences).
  Each array element must be an object with exactly four string keys:
  "word" — the input word;
  "english_meaning" — a concise English definition or gloss suitable for a learner;
  "chinese_meaning" — a concise Chinese translation or gloss for the same sense;
  "pronunciation" — a concise pronunciation string for the English word (IPA preferred, otherwise clear phonetic spelling).
  Example shape: [{"word":"cat","english_meaning":"...","chinese_meaning":"...","pronunciation":"..."}]
PROMPT
```

Update parser methods:

```ruby
pronunciation = inner["pronunciation"]
raise Error, "OpenRouter JSON missing english_meaning or chinese_meaning or pronunciation" if en.to_s.strip.empty? || zh.to_s.strip.empty? || pronunciation.to_s.strip.empty?

MeaningResult.new(
  english_meaning: en.to_s.strip,
  chinese_meaning: zh.to_s.strip,
  pronunciation: pronunciation.to_s.strip
)
```

And for batch:

```ruby
pronunciation = entry["pronunciation"]
if word.to_s.strip.empty? || english_meaning.to_s.strip.empty? || chinese_meaning.to_s.strip.empty? || pronunciation.to_s.strip.empty?
  raise Error, "OpenRouter JSON missing required fields (word, english_meaning, chinese_meaning, pronunciation)"
end

BatchMeaningResult.new(
  word: word.to_s.strip,
  english_meaning: english_meaning.to_s.strip,
  chinese_meaning: chinese_meaning.to_s.strip,
  pronunciation: pronunciation.to_s.strip
)
```

- [ ] **Step 4: Run service tests**

Run:

```bash
bin/rails test test/services/open_router_word_meaning_client_test.rb
```

Expected: all OpenRouter meaning client tests pass.

- [ ] **Step 5: Commit checkpoint**

```bash
git add app/services/llm/open_router_word_meaning_client.rb test/services/open_router_word_meaning_client_test.rb
git commit -m "Return pronunciation from word meaning client"
```

## Task 3: Pass Pronunciation Through Controller And JSON Endpoints

**Files:**
- Modify: `app/controllers/words_controller.rb`
- Test: `test/controllers/words_controller_test.rb`

- [ ] **Step 1: Add failing controller tests**

In `test/controllers/words_controller_test.rb`, update fake client data objects:

```ruby
Llm::OpenRouterWordMeaningClient::MeaningResult.new(
  english_meaning: "Definition for #{word}",
  chinese_meaning: "释义",
  pronunciation: "/#{word}/"
)
```

And batch fake results:

```ruby
Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
  word: trimmed,
  english_meaning: "Definition for #{trimmed}",
  chinese_meaning: "释义",
  pronunciation: "/#{trimmed}/"
)
```

Add assertions in existing tests:

```ruby
assert_match "/hello/", @response.body
assert_equal "/cat/", body.fetch("meanings")[0].fetch("pronunciation")
```

Add batch_create persistence test:

```ruby
test "batch_create persists pronunciation when provided" do
  payload = [
    { word: "audio_word_1", english_meaning: "m1", chinese_meaning: "中1", pronunciation: "/ˈɔːdi.oʊ/" }
  ]

  post batch_create_words_url, params: { words: payload }, as: :json
  assert_response :created

  created_word = Word.find_by!(word: "audio_word_1")
  assert_equal "/ˈɔːdi.oʊ/", created_word.pronunciation
end
```

- [ ] **Step 2: Run controller tests and confirm failures**

Run:

```bash
bin/rails test test/controllers/words_controller_test.rb
```

Expected: failures because controller does not assign, permit, or render pronunciation.

- [ ] **Step 3: Implement controller propagation**

Update `app/controllers/words_controller.rb`:

```ruby
@word = Word.new(
  word: trimmed,
  english_meaning: result.english_meaning,
  chinese_meaning: result.chinese_meaning,
  pronunciation: result.pronunciation
)
```

Update `batch_lookup` response map:

```ruby
{
  word: result.word,
  english_meaning: result.english_meaning,
  chinese_meaning: result.chinese_meaning,
  pronunciation: result.pronunciation
}
```

Update batch create entry parsing:

```ruby
word = Word.new(
  word: entry[:word] || entry["word"],
  english_meaning: entry[:english_meaning] || entry["english_meaning"],
  chinese_meaning: entry[:chinese_meaning] || entry["chinese_meaning"],
  pronunciation: entry[:pronunciation] || entry["pronunciation"],
  skip_create_word_question_job: true
)
```

Update strong params:

```ruby
params.require(:word).permit(:word, :english_meaning, :chinese_meaning, :pronunciation)
```

- [ ] **Step 4: Re-run controller tests**

Run:

```bash
bin/rails test test/controllers/words_controller_test.rb
```

Expected: all controller tests pass.

- [ ] **Step 5: Commit checkpoint**

```bash
git add app/controllers/words_controller.rb test/controllers/words_controller_test.rb
git commit -m "Propagate pronunciation through words controller"
```

## Task 4: Add Pronunciation UI And Play Button

**Files:**
- Modify: `app/views/words/_form.html.erb`
- Modify: `app/views/words/new.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/words_controller_test.rb`

- [ ] **Step 1: Add failing UI assertions**

In `test/controllers/words_controller_test.rb`, extend `lookup fills form`:

```ruby
assert_select "label", text: "Pronunciation"
assert_select "input[name='word[pronunciation]'][value='/hello/']"
assert_select "button[data-pronunciation-play]", text: "Play"
```

- [ ] **Step 2: Run controller tests and confirm UI assertion failures**

Run:

```bash
bin/rails test test/controllers/words_controller_test.rb
```

Expected: pronunciation field/play button assertions fail.

- [ ] **Step 3: Add pronunciation field and play button to form**

In `app/views/words/_form.html.erb`, insert pronunciation block after the English word field:

```erb
  <div class="field pronunciation-field">
    <%= f.label :pronunciation, "Pronunciation" %>
    <div class="pronunciation-row">
      <%= f.text_field :pronunciation, autocomplete: "off", placeholder: "/həˈloʊ/" %>
      <button
        type="button"
        class="button button-secondary pronunciation-play"
        data-pronunciation-play
        data-pronunciation-input-id="<%= f.object_name %>_pronunciation"
        data-word-input-id="<%= f.object_name %>_word">
        Play
      </button>
    </div>
  </div>
```

- [ ] **Step 4: Add playback script using requested API**

In `app/views/words/new.html.erb`, add this at the bottom of the file:

```erb
<script>
  document.addEventListener("click", function(event) {
    const button = event.target.closest("[data-pronunciation-play]");
    if (!button) return;

    const pronunciationInput = document.getElementById(button.dataset.pronunciationInputId);
    const wordInput = document.getElementById(button.dataset.wordInputId);
    const text = (pronunciationInput && pronunciationInput.value.trim()) || (wordInput && wordInput.value.trim());
    if (!text) return;

    if (window.speechSynthesis) {
      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = "en-US";
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(utterance);
    }
  });
</script>
```

- [ ] **Step 5: Add focused styling**

Append to `app/assets/stylesheets/application.css`:

```css
.pronunciation-row {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.pronunciation-row input[type="text"] {
  flex: 1 1 auto;
}

.pronunciation-play {
  flex: 0 0 auto;
  white-space: nowrap;
}
```

- [ ] **Step 6: Re-run controller tests**

Run:

```bash
bin/rails test test/controllers/words_controller_test.rb
```

Expected: UI-related assertions pass.

- [ ] **Step 7: Commit checkpoint**

```bash
git add app/views/words/_form.html.erb app/views/words/new.html.erb app/assets/stylesheets/application.css test/controllers/words_controller_test.rb
git commit -m "Add pronunciation field and play button on word form"
```

## Task 5: Full Verification And Manual Audio Check

**Files:**
- Modify only if tests reveal issues in files already touched.

- [ ] **Step 1: Run focused automated tests**

Run:

```bash
bin/rails test test/models/word_test.rb test/services/open_router_word_meaning_client_test.rb test/controllers/words_controller_test.rb
```

Expected: all three test files pass.

- [ ] **Step 2: Run full test suite**

Run:

```bash
bin/rails test
```

Expected: full suite passes with no regressions.

- [ ] **Step 3: Manual browser verification for pronunciation playback**

Run server if needed:

```bash
bin/rails server
```

In browser, open `/words/new` and verify:

- Lookup a word and confirm pronunciation is prefilled.
- Click `Play` and confirm speech plays.
- Clear pronunciation, keep English word, click `Play`, and confirm fallback speech still plays.
- Save word and confirm pronunciation appears in saved record after reload (via edit page or Rails console).

- [ ] **Step 4: Optional final commit (only if user asks)**

```bash
git add app/models/word.rb app/services/llm/open_router_word_meaning_client.rb app/controllers/words_controller.rb app/views/words/_form.html.erb app/views/words/new.html.erb app/assets/stylesheets/application.css test/models/word_test.rb test/services/open_router_word_meaning_client_test.rb test/controllers/words_controller_test.rb db/migrate db/schema.rb docs/superpowers/plans/2026-04-30-word-pronunciation-playback.md
git commit -m "Add pronunciation support with browser playback"
```

Expected: commit succeeds and feature is merge-ready.

## Self-Review Notes

- Spec coverage: Plan includes LLM response shape update, persistence, controller pass-through, batch endpoints, and UI playback interaction using `SpeechSynthesisUtterance`.
- Placeholder scan: Every code-changing step includes concrete snippets and executable commands with explicit expected outcomes.
- Type consistency: `pronunciation` naming is consistent across Data structs, JSON keys, strong params, model attributes, and form fields.
- Scope check: Keeps feature limited to word lookup/create UX; it does not alter remember-word quiz logic or scheduling.
