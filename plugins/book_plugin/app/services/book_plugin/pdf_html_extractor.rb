require "json"
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
      def call(pdf_path:, page_number:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, scale: 1.5, area: nil, load_js: false)
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

          unless status.success?
            return failure(build_process_failure_message(status:, stderr:))
          end

          payload = parse_layout_json(stdout)
          return failure("Extractor produced invalid JSON output") unless payload

          layout = payload.fetch("layout")
          width = payload.fetch("width")
          height = payload.fetch("height")

          html = PdfPageHtmlRenderer.render(
            layout: layout,
            width: width,
            height: height,
            scale: scale,
            area: area,
            load_js: load_js
          )
          return failure("Extractor produced empty HTML output") if html.strip.empty?

          images = build_images_payload(html, workdir)
          Result.new(html:, images:, error_message: nil)
        end
      rescue StandardError => e
        failure("Extractor failed: #{e.message}")
      end

      private

      def parse_layout_json(raw)
        val = JSON.parse(raw.to_s)
        return val if val.is_a?(Hash)

        nil
      rescue JSON::ParserError, TypeError
        nil
      end

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

      def layout_extractor_script_path
        repo_root = BookPlugin::Engine.root.join("..", "..").expand_path
        repo_root.join("pdf_layout_extract.py").to_s
      end
    end
  end
end
