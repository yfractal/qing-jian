# frozen_string_literal: true

class WordBrowseController < ApplicationController
  def index
    @words = Word.order(Arel.sql("LOWER(word)")).to_a
    return unless @words.any?

    @current_word = @words.find { |w| w.id == params[:word_id].to_i } || @words.first
    @current_index = @words.index(@current_word)
    @total_count = @words.size
    @next_word = @words[@current_index + 1]
    @prev_word = @current_index.positive? ? @words[@current_index - 1] : nil
  end
end
