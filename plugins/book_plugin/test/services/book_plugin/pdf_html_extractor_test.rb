require "test_helper"

module BookPlugin
  class PdfHtmlExtractorTest < ActiveSupport::TestCase
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
      status = Struct.new(:exitstatus).new(0)
      command_args = nil

      with_singleton_stub(PdfHtmlExtractor, :with_timeout, ->(_seconds, &block) { block.call }) do
        with_singleton_stub(PdfHtmlExtractor, :run_command, lambda { |*args|
          command_args = args
          out_path = args[args.index("--out") + 1]
          File.write(out_path, "<article>Extracted</article>")
          ["", "", status]
        }) do
          result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 5)

          assert_predicate result, :success?
          assert_equal "<article>Extracted</article>", result.html
          assert_nil result.error_message
          assert_equal "python3", command_args[0]
          assert_equal "/tmp/book.pdf", command_args[2]
          assert_equal "4", command_args[4]
          assert_equal "--out", command_args[5]
          refute_includes command_args, "--scale"
          refute_includes command_args, "--output-dir"
        end
      end
    end

    test "returns error when extractor exits non zero" do
      status = Struct.new(:exitstatus).new(1)

      with_singleton_stub(PdfHtmlExtractor, :with_timeout, ->(_seconds, &block) { block.call }) do
        with_singleton_stub(PdfHtmlExtractor, :run_command, ->(*_args) { ["", "boom", status] }) do
          result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 2)

          refute_predicate result, :success?
          assert_nil result.html
          assert_match(/exit code 1/, result.error_message)
          assert_match(/boom/, result.error_message)
        end
      end
    end

    test "returns timeout error when extraction exceeds timeout" do
      with_singleton_stub(PdfHtmlExtractor, :with_timeout, ->(_seconds, &_block) { raise Timeout::Error, "execution expired" }) do
        result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 1)

        refute_predicate result, :success?
        assert_nil result.html
        assert_match(/timed out/i, result.error_message)
      end
    end

    test "returns error when extractor output is empty" do
      status = Struct.new(:exitstatus).new(0)

      with_singleton_stub(PdfHtmlExtractor, :with_timeout, ->(_seconds, &block) { block.call }) do
        with_singleton_stub(PdfHtmlExtractor, :run_command, lambda { |*args|
          out_path = args[args.index("--out") + 1]
          File.write(out_path, " \n")
          ["", "", status]
        }) do
          result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 3)

          refute_predicate result, :success?
          assert_nil result.html
          assert_match(/empty html output/i, result.error_message)
        end
      end
    end

    test "returns error when unexpected exception happens" do
      with_singleton_stub(PdfHtmlExtractor, :with_timeout, ->(_seconds, &block) { block.call }) do
        with_singleton_stub(PdfHtmlExtractor, :run_command, ->(*_args) { raise StandardError, "kaboom" }) do
          result = PdfHtmlExtractor.call(pdf_path: "/tmp/book.pdf", page_number: 7)

          refute_predicate result, :success?
          assert_nil result.html
          assert_match(/kaboom/, result.error_message)
        end
      end
    end
  end
end
