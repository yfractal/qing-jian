require "open3"
require "pathname"
require "tempfile"
require "timeout"

module BookPlugin
  class PdfHtmlExtractor
    Result = Struct.new(:html, :error_message, keyword_init: true) do
      def success?
        error_message.nil?
      end
    end

    DEFAULT_TIMEOUT_SECONDS = 30

    class << self
      def call(pdf_path:, page_number:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
        Tempfile.create(["book-plugin-page", ".html"]) do |tmp_html|
          tmp_html_path = tmp_html.path
          tmp_html.close

          command = [
            "python3",
            extractor_script_path,
            pdf_path.to_s,
            "--page",
            (page_number.to_i - 1).to_s,
            "--out",
            tmp_html_path
          ]

          _stdout, stderr, status = with_timeout(timeout_seconds) do
            run_command(*command)
          end

          unless status.exitstatus.zero?
            stderr_text = stderr.to_s.strip
            return failure("Extractor failed with exit code #{status.exitstatus}: #{stderr_text}")
          end

          html = File.exist?(tmp_html_path) ? File.read(tmp_html_path) : ""
          return failure("Extractor produced empty HTML output") if html.strip.empty?

          Result.new(html:, error_message: nil)
        end
      rescue Timeout::Error
        failure("Extractor timed out")
      rescue StandardError => e
        failure("Extractor failed: #{e.message}")
      end

      def run_command(*args)
        Open3.capture3(*args)
      end

      def with_timeout(seconds, &block)
        Timeout.timeout(seconds, &block)
      end

      private

      def failure(message)
        Result.new(html: nil, error_message: message)
      end

      def extractor_script_path
        repo_root = BookPlugin::Engine.root.join("..", "..").expand_path
        repo_root.join("extract2.py").to_s
      end
    end
  end
end
