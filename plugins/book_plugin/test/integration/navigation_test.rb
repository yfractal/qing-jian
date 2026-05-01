require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "book pages render inside host app shell" do
    get "/books"
    assert_response :success
    assert_select "main.remember-page"
  end
end
