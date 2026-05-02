require "open3"
require "tmpdir"

module BookPlugin
  class PdfHtmlExtractor
    Result = Struct.new(:html, :images, :error_message, keyword_init: true) do
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
          html_path = File.join(workdir, "page.html")

          command = [
            "python3",
            extractor_script_path,
            pdf_path.to_s,
            "--page",
            (normalized_page_number - 1).to_s,
            "--out",
            html_path,
            "--output-dir",
            workdir
          ]

          _stdout, stderr, status, timed_out = execute_command(command:, timeout_seconds:)
          return failure("Extractor timed out") if timed_out

          unless status.success?
            return failure(build_process_failure_message(status:, stderr:))
          end

          html = File.exist?(html_path) ? File.read(html_path) : ""
          return failure("Extractor produced empty HTML output") if html.strip.empty?

          images = build_images_payload(html, workdir)
          Result.new(html:, images:, error_message: nil)
        end
      rescue StandardError => e
        failure("Extractor failed: #{e.message}")
      end

      private

      def build_images_payload(html, workdir)
        base = File.expand_path(workdir)
        paths = []
        html.scan(/<img[^>]+src=["']([^"']+)["']/i) do |m|
          raw = m[0]
          next if raw.start_with?("data:", "http://", "https://", "/rails/active_storage")

          path = File.absolute_path(raw, workdir)
          next unless path.start_with?(base + File::SEPARATOR) && File.file?(path)

          paths << path
        end
        paths.uniq.map do |path|
          { filename: File.basename(path), data: File.binread(path) }
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
          stderr.close unless stdout.closed?
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
        Result.new(html: nil, images: [], error_message: message)
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

      def extractor_script_path
        repo_root = BookPlugin::Engine.root.join("..", "..").expand_path
        repo_root.join("extract2.py").to_s
      end
    end
  end
end
