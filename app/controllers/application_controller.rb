class ApplicationController < ActionController::Base
  before_action :authenticate
  protect_from_forgery with: :exception

  def authenticate
    raise "Set yer name and pass!" unless ENV['HTTP_BASIC_AUTH_NAME'] && ENV['HTTP_BASIC_AUTH_PASSWORD']
    authenticate_or_request_with_http_basic("Bitflyer-quick-order") { |u, p| (u == ENV['HTTP_BASIC_AUTH_NAME']) && (p == ENV['HTTP_BASIC_AUTH_PASSWORD']) }
  end

end
