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

    client = OpenRouterWordMeaningClient.new
    meanings = client.batch_lookup(words)

    created = 0
    failed = []
    meanings.each do |item|
      word = Word.new(
        word: item.word,
        english_meaning: item.english_meaning,
        chinese_meaning: item.chinese_meaning
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
  rescue OpenRouterWordMeaningClient::Error => e
    puts "Batch lookup failed: #{e.message}"
    exit 1
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
