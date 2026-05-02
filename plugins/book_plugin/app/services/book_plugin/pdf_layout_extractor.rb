require "json"
require "open3"
require "tmpdir"

module BookPlugin
  class PdfLayoutExtractor
    Result = Struct.new(:layout, :width, :height, :error_message, keyword_init: true) do
      def success?
        error_message.nil?
      end
    end

    DEFAULT_TIMEOUT_SECONDS = 30

    class << self
      def call(pdf_path:, page_number:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
        normalized_page_number = normalize_page_number(page_number)
        return failure("Page number must be an integer greater than or equal to 1") unless normalized_page_number

        Dir.mktmpdir("book-plugin-extract") do |workdir|
          command = [
            "python3",
            layout_extractor_script_path,
            pdf_path.to_s,
            "--page",
            (normalized_page_number - 1).to_s,
            "--output-dir",
            workdir
          ]

          stdout, stderr, status, timed_out = execute_command(command:, timeout_seconds:)
          return failure("Extractor timed out") if timed_out
          return failure(build_process_failure_message(status:, stderr:)) unless status.success?

          payload = parse_layout_json(stdout)
          return failure("Extractor produced invalid JSON output") unless payload

          layout = payload.fetch("layout")
          # Dir.mktmpdir deletes workdir when this block ends; layout JSON still points at
          # files under workdir unless we read them now.
          materialize_layout_images!(layout)

          Result.new(
            layout: layout,
            width: payload.fetch("width"),
            height: payload.fetch("height"),
            error_message: nil
          )
        end
      rescue StandardError => e
        failure("Extractor failed: #{e.message}")
      end

      private

      def parse_layout_json(raw)
        value = JSON.parse(raw.to_s)
        value if value.is_a?(Hash)
      rescue JSON::ParserError, TypeError
        nil
      end

      def materialize_layout_images!(layout)
        return unless layout.is_a?(Array)

        layout.each do |item|
          next unless item.is_a?(Hash)
          next unless item["type"] == "image"

          path = item["file"]
          next if path.blank?
          next unless File.file?(path)

          item["__pending_upload__"] = {
            "filename" => File.basename(path),
            "data" => File.binread(path)
          }
          item.delete("file")
        end
      end

      def execute_command(command:, timeout_seconds:)
        Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          stdout_reader = Thread.new { stdout.read.to_s }
          stderr_reader = Thread.new { stderr.read.to_s }

          timed_out = wait_thr.join(timeout_seconds).nil?
          terminate_and_reap(wait_thr) if timed_out

          status = wait_thr.value
          [stdout_reader.value, stderr_reader.value, status, timed_out]
        ensure
          stdout.close unless stdout.closed?
          stderr.close unless stderr.closed?
        end
      end

      def terminate_and_reap(wait_thr)
        pid = wait_thr.pid
        Process.kill("TERM", pid)
      rescue Errno::ESRCH
        nil
      ensure
        if wait_thr.join(0.2).nil?
          begin
            Process.kill("KILL", pid)
          rescue Errno::ESRCH
            nil
          end
          wait_thr.join
        end
      end

      def failure(message)
        Result.new(layout: nil, width: nil, height: nil, error_message: message)
      end

      def normalize_page_number(page_number)
        parsed_value = page_number.is_a?(String) ? Integer(page_number, 10) : Integer(page_number)
        return nil if parsed_value < 1

        parsed_value
      rescue ArgumentError, TypeError
        nil
      end

      def build_process_failure_message(status:, stderr:)
        diagnostic =
          if status.signaled?
            "terminated by signal #{status.termsig}"
          elsif status.exited?
            "failed with exit status #{status.exitstatus}"
          else
            "ended abnormally (#{status.inspect})"
          end

        stderr_text = stderr.to_s.strip
        return "Extractor #{diagnostic}" if stderr_text.empty?

        "Extractor #{diagnostic}: #{stderr_text}"
      end

      def layout_extractor_script_path
        repo_root = BookPlugin::Engine.root.join("..", "..").expand_path
        repo_root.join("pdf_layout_extract.py").to_s
      end
    end
  end
end
