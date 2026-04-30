# frozen_string_literal: true

class WordsController < ApplicationController
  class_attribute :meaning_client_class, default: Llm::OpenRouterWordMeaningClient

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
      chinese_meaning: result.chinese_meaning,
      pronunciation: result.pronunciation
    )
    render :new
  rescue Llm::OpenRouterWordMeaningClient::Error => e
    flash.now[:alert] = e.message
    @word = Word.new(word: trimmed)
    render :new, status: :unprocessable_entity
  end

  def batch_lookup
    words = params[:words]
    if words.nil?
      render json: { error: "words parameter is required" }, status: :unprocessable_entity
      return
    end

    unless words.is_a?(Array)
      render json: { error: "words must be an array" }, status: :unprocessable_entity
      return
    end

    results = meaning_client.batch_lookup(words)
    render json: {
      meanings: results.map do |result|
        {
          word: result.word,
          english_meaning: result.english_meaning,
          chinese_meaning: result.chinese_meaning,
          pronunciation: result.pronunciation
        }
      end
    }
  rescue Llm::OpenRouterWordMeaningClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  def batch_create
    words = params[:words]
    if words.nil?
      render json: { error: "words parameter is required" }, status: :unprocessable_entity
      return
    end

    unless words.is_a?(Array)
      render json: { error: "words must be an array" }, status: :unprocessable_entity
      return
    end

    if words.empty?
      render json: { error: "words array cannot be empty" }, status: :unprocessable_entity
      return
    end

    created = []
    failed = []
    created_word_ids = []

    words.each do |entry|
      word = Word.new(
        word: entry[:word] || entry["word"],
        english_meaning: entry[:english_meaning] || entry["english_meaning"],
        chinese_meaning: entry[:chinese_meaning] || entry["chinese_meaning"],
        pronunciation: entry[:pronunciation] || entry["pronunciation"],
        skip_create_word_question_job: true
      )

      if word.save
        created << { id: word.id, word: word.word }
        created_word_ids << word.id
      else
        failed << { word: word.word.presence || (entry[:word] || entry["word"]), errors: word.errors.full_messages.join(", ") }
      end
    end

    CreateBatchWordQuestionsJob.perform_later(created_word_ids) if created_word_ids.any?
    render json: { created: created, failed: failed }, status: :created
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
    params.require(:word).permit(:word, :english_meaning, :chinese_meaning, :pronunciation)
  end

  def meaning_client
    @meaning_client ||= self.class.meaning_client_class.new
  end
end
