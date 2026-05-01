require "test_helper"

module BookPlugin
  class PdfHtmlExtractorTest < ActiveSupport::TestCase
    StatusDouble = Struct.new(:success?, :exitstatus, :signaled?, :termsig, :exited?)

    def with_singleton_stub(target, method_name, replacement)
      eigenclass = class << target; self; end
      original_defined = target.respond_to?(method_name, true)
      original_method = target.method(method_name) if original_defined

      eigenclass.send(:define_method, method_name, &replacement)
      yield
    ensure
      if original_defined
        eigenclass.send(:define_method, method_name, original_method.to_proc)
      else
        eigenclass.send(:remove_method, method_name)
      end
    end

    test "returns html on successful extraction" do
      status = StatusDouble.new(true, 0, false, nil, true)
      command_args = nil
      timeout_value = nil
      option_lookup = ->(command, flag) { command[command.index(flag) + 1] }

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        timeout_value = timeout_seconds
        command_args = command
        out_path = option_lookup.call(command, "--out")
        File.write(out_path, "<article>Extracted</article>")
        ["", "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 5)

        assert_predicate result, :success?
        assert_equal "<article>Extracted</article>", result.html
        assert_nil result.error_message
        assert_equal 30, timeout_value
        assert_equal "python3", command_args[0]
        assert_match(%r{/extract2\.py\z}, command_args[1])
        assert_equal "/tmp/book.pdf", command_args[2]
        assert_equal "4", option_value(command_args, "--page")
        assert_equal "1", option_value(command_args, "--load-js")
        assert option_value(command_args, "--out").end_with?(".html")
        refute_includes command_args, "--scale"
        refute_includes command_args, "--output-dir"
      end
    end

    test "passes explicit load_js false to extractor command" do
      status = StatusDouble.new(true, 0, false, nil, true)
      command_args = nil
      option_lookup = ->(command, flag) { command[command.index(flag) + 1] }

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        command_args = command
        out_path = option_lookup.call(command, "--out")
        File.write(out_path, "<article>Extracted</article>")
        ["", "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 5, load_js: false)

        assert_predicate result, :success?
        assert_equal "0", option_value(command_args, "--load-js")
      end
    end

    test "returns error when extractor exits non zero" do
      status = StatusDouble.new(false, 1, false, nil, true)
      command_args = nil
      timeout_value = nil

      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(command:, timeout_seconds:) {
        command_args = command
        timeout_value = timeout_seconds
        ["", "boom", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 2)

        refute_predicate result, :success?
        assert_nil result.html
        assert_equal "/tmp/book.pdf", command_args[2]
        assert_equal 30, timeout_value
        assert_match(/exit status 1/, result.error_message)
        assert_match(/boom/, result.error_message)
      end
    end

    test "returns error when process exits by signal" do
      status = StatusDouble.new(false, nil, true, 9, false)
      command_args = nil
      timeout_value = nil

      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(command:, timeout_seconds:) {
        command_args = command
        timeout_value = timeout_seconds
        ["", "killed", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 9)

        refute_predicate result, :success?
        assert_nil result.html
        assert_equal "/tmp/book.pdf", command_args[2]
        assert_equal 30, timeout_value
        assert_match(/signal 9/, result.error_message)
        assert_match(/killed/, result.error_message)
      end
    end

    test "returns timeout error when extraction exceeds timeout" do
      timeout_status = StatusDouble.new(false, nil, true, 15, false)
      command_args = nil
      timeout_value = nil

      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(command:, timeout_seconds:) {
        command_args = command
        timeout_value = timeout_seconds
        ["", "", timeout_status, true]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 1)

        refute_predicate result, :success?
        assert_nil result.html
        assert_equal "/tmp/book.pdf", command_args[2]
        assert_equal 30, timeout_value
        assert_match(/timed out/i, result.error_message)
      end
    end

    test "reaps process when execute_command times out" do
      status = nil
      timed_out = nil

      _stdout, _stderr, status, timed_out = PdfHtmlExtractor.send(
        :execute_command,
        command: ["python3", "-c", "import time; time.sleep(5)"],
        timeout_seconds: 0.1
      )

      assert_equal true, timed_out
      refute_predicate status, :success?
      assert_predicate status, :signaled?
    end

    test "returns error when extractor output is empty" do
      status = StatusDouble.new(true, 0, false, nil, true)
      timeout_value = nil
      option_lookup = ->(command, flag) { command[command.index(flag) + 1] }

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        timeout_value = timeout_seconds
        out_path = option_lookup.call(command, "--out")
        File.write(out_path, " \n")
        ["", "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 3)

        refute_predicate result, :success?
        assert_nil result.html
        assert_equal 30, timeout_value
        assert_match(/empty html output/i, result.error_message)
      end
    end

    test "returns error when unexpected exception happens" do
      command_args = nil
      timeout_value = nil

      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(command:, timeout_seconds:) {
        command_args = command
        timeout_value = timeout_seconds
        raise StandardError, "kaboom"
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 7)

        refute_predicate result, :success?
        assert_nil result.html
        assert_equal "/tmp/book.pdf", command_args[2]
        assert_equal 30, timeout_value
        assert_match(/kaboom/, result.error_message)
      end
    end

    test "returns error for non numeric page number" do
      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(**) { raise "execute_command should not run for invalid page number" }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: "abc")

        refute_predicate result, :success?
        assert_nil result.html
        assert_match(/page number must be an integer greater than or equal to 1/i, result.error_message)
      end
    end

    test "returns error for non positive page number" do
      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(**) { raise "execute_command should not run for invalid page number" }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 0)

        refute_predicate result, :success?
        assert_nil result.html
        assert_match(/page number must be an integer greater than or equal to 1/i, result.error_message)
      end
    end

    private

    def option_value(command, flag)
      index = command.index(flag)
      return nil unless index

      command[index + 1]
    end
  end
end
