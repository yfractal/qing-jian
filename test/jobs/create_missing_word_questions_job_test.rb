# frozen_string_literal: true

require "test_helper"

class CreateMissingWordQuestionsJobTest < ActiveJob::TestCase
  test "perform invokes the batch runner" do
    called = false
    batcher = proc { called = true }

    CreateMissingWordQuestionsJob.perform_now(batcher: batcher)

    assert called
  end
end
