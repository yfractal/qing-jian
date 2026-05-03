class Word < ApplicationRecord
  attr_accessor :skip_create_word_question_job

  has_many :word_questions, dependent: :destroy
  has_many :word_self_recall_records, dependent: :destroy
  has_one :word_recall_state, dependent: :destroy

  validates :word, presence: true, uniqueness: { case_sensitive: false }
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true
  validates :pronunciation, length: { maximum: 255 }, allow_blank: true

  after_create :create_initial_recall_state
  after_create_commit :enqueue_create_word_question_job, unless: :skip_create_word_question_job

  private

  def create_initial_recall_state
    create_word_recall_state!(due_day: created_at.to_date)
  end

  def enqueue_create_word_question_job
    CreateWordQuestionJob.perform_later(id)
  end
end
