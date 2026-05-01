Rails.application.routes.draw do
  mount BookPlugin::Engine => "/book_plugin"
end
