Rails.application.routes.draw do
  mount BookPlugin::Engine => "/books"
end
