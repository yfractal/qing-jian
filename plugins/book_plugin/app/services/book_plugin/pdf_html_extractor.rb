require "open3"
require "tempfile"

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

          _stdout, stderr, status, timed_out = execute_command(command:, timeout_seconds:)
          return failure("Extractor timed out") if timed_out

          unless status.success?
            return failure(build_process_failure_message(status:, stderr:))
          end

          html = File.exist?(tmp_html_path) ? File.read(tmp_html_path) : ""
          return failure("Extractor produced empty HTML output") if html.strip.empty?

          Result.new(html:, error_message: nil)
        end
      rescue StandardError => e
        failure("Extractor failed: #{e.message}")
      end

      private

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
        Result.new(html: nil, error_message: message)
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

      def extractor_script_path
        repo_root = BookPlugin::Engine.root.join("..", "..").expand_path
        repo_root.join("extract2.py").to_s
      end
    end
  end
end
