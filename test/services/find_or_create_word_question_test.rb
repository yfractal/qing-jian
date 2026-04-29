# frozen_string_literal: true

require "test_helper"
require "ostruct"

class FindOrCreateWordQuestionTest < ActiveSupport::TestCase
  def build_service(similar_triples)
    inner = similar_triples.map do |word, english, chinese|
      { "word" => word, "english_meaning" => english, "chinese_meaning" => chinese }
    end
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    requester = ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
    llm_client = OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
    FindOrCreateWordQuestion.new(llm_client: llm_client)
  end

  test "returns existing word question when one already exists" do
    word = words(:cat)
    existing_question = word_questions(:cat_question)

    service = build_service([])
    result = service.call(word: word)

    assert_equal existing_question, result
  end

  test "creates a new word question with three similar words" do
    word = Word.create!(word: "elephant", english_meaning: "A large mammal.", chinese_meaning: "大象")
    triples = [
      [ "mammoth", "An extinct large mammal.", "猛犸象" ],
      [ "rhino", "A large herbivore.", "犀牛" ],
      [ "hippo", "A large semiaquatic mammal.", "河马" ]
    ]

    service = build_service(triples)

    assert_difference "WordQuestion.count", 1 do
      @result = service.call(word: word)
    end

    assert_equal word, @result.word
    assert_equal 3, @result.similar_words.size
  end

  test "reuses existing similar words and only creates missing words" do
    word = Word.create!(word: "pony", english_meaning: "A small horse.", chinese_meaning: "小马")
    triples = [
      [ "dog", "A domesticated carnivorous mammal.", "狗" ],
      [ "mule", "A hybrid of horse and donkey.", "骡子" ],
      [ "foal", "A young horse.", "马驹" ]
    ]
    service = build_service(triples)

    assert_difference "Word.count", 2 do
      @result = service.call(word: word)
    end

    words_in_question = @result.similar_words.includes(:word).map { |similar_word| similar_word.word.word }
    assert_includes words_in_question, "dog"
    assert_includes words_in_question, "mule"
    assert_includes words_in_question, "foal"
  end

  test "does not create duplicate questions on repeated calls" do
    word = Word.create!(word: "cedar", english_meaning: "An evergreen tree.", chinese_meaning: "雪松")
    triples = [
      [ "pine", "An evergreen coniferous tree.", "松树" ],
      [ "fir", "A type of conifer.", "冷杉" ],
      [ "spruce", "A coniferous tree.", "云杉" ]
    ]
    service = build_service(triples)

    first = service.call(word: word)

    assert_no_difference "WordQuestion.count" do
      second = service.call(word: word)
      assert_equal first, second
    end
  end
end
