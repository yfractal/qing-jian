# frozen_string_literal: true

namespace :words do
  desc "Backfill example_sentence for words that are missing it"
  task :backfill_example_sentences, [:batch_size] => :environment do |_task, args|
    batch_size = args[:batch_size].to_i
    batch_size = 30 if batch_size <= 0

    scope = Word.where(example_sentence: [nil, ""])
    total = scope.count
    if total.zero?
      puts "No words are missing example_sentence."
      next
    end

    puts "Starting backfill for #{total} words (batch_size=#{batch_size})"

    client = Llm::OpenRouterWordMeaningClient.new
    last_id = 0
    processed = 0

    loop do
      batch = scope.where("words.id > ?", last_id)
                   .order(:id)
                   .limit(batch_size)
                   .pluck(:id, :word)
      break if batch.empty?

      words = batch.map(&:last)
      results = client.batch_lookup(words)
      by_word = results.index_by { |item| item.word.to_s.downcase }

      batch.each do |(id, spelling)|
        item = by_word[spelling.to_s.downcase]
        unless item
          warn "No LLM result matched word id=#{id} #{spelling.inspect}"
          next
        end

        record = Word.find_by(id: id)
        next unless record
        next unless record.example_sentence.to_s.strip.empty?

        record.update!(example_sentence: item.example_sentence)
      end

      processed += batch.size
      last_id = batch.last.first
      remaining = Word.where(example_sentence: [nil, ""]).count
      puts "Processed #{processed}/#{total}, remaining missing example_sentence: #{remaining}"
    end

    final_missing = Word.where(example_sentence: [nil, ""]).count
    puts "Backfill complete. Still missing example_sentence: #{final_missing}"
  rescue Llm::OpenRouterWordMeaningClient::Error => e
    puts "Backfill failed: #{e.message}"
    exit 1
  end
end
