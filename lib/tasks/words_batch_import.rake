# frozen_string_literal: true

namespace :words do
  desc "Batch lookup meanings with LLM and create words (input: comma list or file:/path)"
  task :batch_import, [:input] => :environment do |_task, args|
    input = args[:input].to_s.strip
    if input.empty?
      puts "Usage: bin/rails 'words:batch_import[cat,dog]'"
      puts "   or: bin/rails 'words:batch_import[file:tmp/words.txt]'"
      exit 1
    end

    words = parse_words_batch_input(input)
    if words.empty?
      puts "No valid words found in input."
      exit 1
    end

    client = Llm::OpenRouterWordMeaningClient.new
    meanings = client.batch_lookup(words)

    created = 0
    failed = []
    meanings.each do |item|
      word = Word.new(
        word: item.word,
        english_meaning: item.english_meaning,
        chinese_meaning: item.chinese_meaning,
        pronunciation: item.pronunciation,
        example_sentence: item.example_sentence
      )

      if word.save
        created += 1
      else
        failed << "#{item.word}: #{word.errors.full_messages.join(', ')}"
      end
    end

    puts "Successfully created #{created} words"
    puts "Failed to create #{failed.size} words" unless failed.empty?
    failed.each { |line| puts line }
  rescue Llm::OpenRouterWordMeaningClient::Error => e
    puts "Batch lookup failed: #{e.message}"
    exit 1
  end

  desc "Create questions for words that do not have any questions yet"
  task :backfill_questions, [:batch_size] => :environment do |_task, args|
    batch_size = args[:batch_size].to_i
    batch_size = 30 if batch_size <= 0

    initial_missing = Word.where.missing(:word_questions).count
    if initial_missing.zero?
      puts "No words are missing questions."
      next
    end

    puts "Starting backfill for #{initial_missing} words (batch_size=#{batch_size})"

    last_id = 0
    attempted = 0

    loop do
      word_ids = Word.where.missing(:word_questions)
                     .where("words.id > ?", last_id)
                     .order(:id)
                     .limit(batch_size)
                     .pluck(:id)
      break if word_ids.empty?

      CreateBatchWordQuestionsJob.perform_now(word_ids)
      attempted += word_ids.size
      last_id = word_ids.last

      remaining = Word.where.missing(:word_questions).count
      puts "Processed #{attempted}/#{initial_missing} words, remaining without questions: #{remaining}"
    end

    final_missing = Word.where.missing(:word_questions).count
    puts "Backfill complete. Attempted: #{attempted}, still missing questions: #{final_missing}"
  end

  desc "Lowercase the word column for all Word records (skips rows that would violate uniqueness)"
  task lowercase: :environment do
    updated = 0
    skipped_conflict = 0

    Word.find_each do |record|
      lowered = record.word.to_s.downcase
      next if record.word == lowered

      if Word.where.not(id: record.id).where("LOWER(word) = ?", lowered).exists?
        warn "Skip id=#{record.id} #{record.word.inspect} -> #{lowered.inspect} (another row already uses this spelling case-insensitively)"
        skipped_conflict += 1
        next
      end

      record.update!(word: lowered)
      updated += 1
    end

    puts "Lowercased #{updated} words."
    puts "Skipped #{skipped_conflict} words due to uniqueness conflict." if skipped_conflict.positive?
  end
end

def parse_words_batch_input(input)
  if input.start_with?("file:")
    file_path = input.delete_prefix("file:")
    return [] unless File.exist?(file_path)

    File.readlines(file_path, chomp: true).map(&:strip).reject(&:empty?).uniq
  else
    input.split(",").map(&:strip).reject(&:empty?).uniq
  end
end
