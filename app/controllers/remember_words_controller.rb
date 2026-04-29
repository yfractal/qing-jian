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
