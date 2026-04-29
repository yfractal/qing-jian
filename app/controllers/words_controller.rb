# frozen_string_literal: true

class WordsController < ApplicationController
  class_attribute :meaning_client_class, default: OpenRouterWordMeaningClient

  before_action :set_word, only: %i[show edit update destroy]

  def index
    @words = Word.order(Arel.sql("LOWER(word)"))
  end

  def show; end

  def new
    @word = Word.new
  end

  def lookup
    trimmed = params[:english_word].to_s.strip
    if trimmed.empty?
      flash.now[:alert] = "Please enter an English word."
      @word = Word.new
      render :new, status: :unprocessable_entity
      return
    end

    result = meaning_client.lookup(trimmed)
    @word = Word.new(
      word: trimmed,
      english_meaning: result.english_meaning,
      chinese_meaning: result.chinese_meaning
    )
    render :new
  rescue OpenRouterWordMeaningClient::Error => e
    flash.now[:alert] = e.message
    @word = Word.new(word: trimmed)
    render :new, status: :unprocessable_entity
  end

  def create
    @word = Word.new(word_params)
    if @word.save
      redirect_to @word, notice: "Word was successfully created."
    else
      flash.now[:alert] = "Could not save word."
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @word.update(word_params)
      redirect_to @word, notice: "Word was successfully updated."
    else
      flash.now[:alert] = "Could not update word."
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @word.destroy!
    redirect_to words_url, notice: "Word was removed."
  end

  private

  def set_word
    @word = Word.find(params[:id])
  end

  def word_params
    params.require(:word).permit(:word, :english_meaning, :chinese_meaning)
  end

  def meaning_client
    @meaning_client ||= self.class.meaning_client_class.new
  end
end
