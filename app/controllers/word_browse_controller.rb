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

  def create_record
    word = Word.find(params[:word_id])
    WordSelfRecallRecord.create!(
      word: word,
      is_correct: ActiveModel::Type::Boolean.new.cast(params[:is_correct])
    )

    if params[:next_word_id].present?
      redirect_to word_browse_path(word_id: params[:next_word_id])
    else
      redirect_to word_browse_path, notice: "All words browsed!"
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to word_browse_path, alert: "Could not save review."
  end
end
