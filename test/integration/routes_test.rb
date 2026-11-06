require "test_helper"

class RoutesTest < ActionDispatch::IntegrationTest
  test "every route's controller exists" do
    missing = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      "#{route.verb} #{route.path.spec} -> #{controller}" if controller && !"#{controller.camelize}Controller".safe_constantize
    end

    assert_empty missing
  end
end
