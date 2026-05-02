# frozen_string_literal: true

require "test_helper"
require "fileutils"

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
      layout_json = {
        "layout" => [
          { "type" => "text", "text" => "Hi", "bbox" => [0, 0, 10, 12], "font_size" => 10 }
        ],
        "width" => 100,
        "height" => 200
      }.to_json

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        timeout_value = timeout_seconds
        command_args = command
        [layout_json, "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 5)

        assert_predicate result, :success?
        assert_includes result.html, "Hi"
        assert_includes result.html, "<html>"
        assert_empty result.images
        assert_nil result.error_message
        assert_equal 30, timeout_value
        assert_equal "python3", command_args[0]
        assert_match(%r{/pdf_layout_extract\.py\z}, command_args[1])
        assert_equal "/tmp/book.pdf", command_args[2]
        assert_equal "4", option_value(command_args, "--page")
        idx = command_args.index("--output-dir")
        assert idx, "expected --output-dir in command"
        assert_match(%r{book-plugin-extract}, command_args[idx + 1])
        refute_includes command_args, "--out"
        refute_includes command_args, "--load-js"
      end
    end

    test "returns image payloads when layout includes images under workdir" do
      status = StatusDouble.new(true, 0, false, nil, true)
      command_args = nil

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        command_args = command
        workdir = command[command.index("--output-dir") + 1]
        FileUtils.mkdir_p(workdir)
        img_path = File.join(workdir, "img_0_0.png")
        File.binwrite(img_path, "fakepng")
        payload = {
          "layout" => [
            {
              "type" => "image",
              "file" => img_path,
              "bbox" => [0, 0, 10, 10]
            }
          ],
          "width" => 100,
          "height" => 200
        }
        [payload.to_json, "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 1, load_js: false)

        assert_predicate result, :success?
        assert_includes command_args, "--output-dir"
        assert_equal "0", option_value(command_args, "--page")
        assert_equal 1, result.images.size
        assert_equal "img_0_0.png", result.images.first.fetch(:filename)
        assert_equal "fakepng", result.images.first.fetch(:data)
      end
    end

    test "omits script when load_js is false" do
      status = StatusDouble.new(true, 0, false, nil, true)
      layout_json = {
        "layout" => [
          { "type" => "text", "text" => "Hi", "bbox" => [0, 0, 10, 12], "font_size" => 10 }
        ],
        "width" => 100,
        "height" => 200
      }.to_json

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        [layout_json, "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 5, load_js: false)

        assert_predicate result, :success?
        refute_includes result.html, "<script>"
        refute_includes result.html, "postMessage"
      end
    end

    test "includes script when load_js is true" do
      status = StatusDouble.new(true, 0, false, nil, true)
      layout_json = {
        "layout" => [
          { "type" => "text", "text" => "Hi", "bbox" => [0, 0, 10, 12], "font_size" => 10 }
        ],
        "width" => 100,
        "height" => 200
      }.to_json

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        [layout_json, "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 5, load_js: true)

        assert_predicate result, :success?
        assert_includes result.html, "<script>"
        assert_includes result.html, "postMessage"
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
        assert_empty result.images
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
        assert_empty result.images
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
        assert_empty result.images
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

      with_singleton_stub(PdfHtmlExtractor, :execute_command, lambda { |command:, timeout_seconds:|
        timeout_value = timeout_seconds
        ["", "", status, false]
      }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 3)

        refute_predicate result, :success?
        assert_nil result.html
        assert_empty result.images
        assert_equal 30, timeout_value
        assert_match(/invalid json output/i, result.error_message)
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
        assert_empty result.images
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
        assert_empty result.images
        assert_match(/page number must be an integer greater than or equal to 1/i, result.error_message)
      end
    end

    test "returns error for non positive page number" do
      with_singleton_stub(PdfHtmlExtractor, :execute_command, ->(**) { raise "execute_command should not run for invalid page number" }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 0)

        refute_predicate result, :success?
        assert_nil result.html
        assert_empty result.images
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
