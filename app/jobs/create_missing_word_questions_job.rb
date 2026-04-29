# frozen_string_literal: true

class CreateMissingWordQuestionsJob < ApplicationJob
  queue_as :default

  # @param batcher [#call] defaults to CreateMissingWordQuestionsBatch (injected in tests only)
  def perform(batcher: nil)
    (batcher || CreateMissingWordQuestionsBatch.new).call
  end
end
