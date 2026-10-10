require "helper"
require "rack/mock"
require "webmock/rspec"
require "action_controller"
require "omniauth/rails_csrf_protection/token_verifier"

RSpec.describe "real request validation and OAuth callback with synthetic session/provider" do
  include WebMock::API

  before do
    @prior_config = {:test_mode => OmniAuth.config.test_mode, :allowed_request_methods => OmniAuth.config.allowed_request_methods, :request_validation_phase => OmniAuth.config.request_validation_phase, :on_failure => OmniAuth.config.on_failure}
    @prior_forgery = ActionController::Base.allow_forgery_protection
    @prior_origin = ActionController::Base.forgery_protection_origin_check
    WebMock.disable_net_connect!
    OmniAuth.config.test_mode = false
    OmniAuth.config.allowed_request_methods = [:post]
    ActionController::Base.allow_forgery_protection = true
    ActionController::Base.forgery_protection_origin_check = true
    OmniAuth.config.request_validation_phase = OmniAuth::RailsCsrfProtection::TokenVerifier.new
    OmniAuth.config.on_failure = ->(env) { [403, {"content-type" => "text/plain"}, [env["omniauth.error.type"].to_s]] }
    @session = {}
    @app = OmniAuth::Strategies::YNAB.new(->(env) { [200, {"content-type" => "text/plain"}, [env["omniauth.auth"] ? env["omniauth.auth"].credentials.token : "passthrough"]] }, "synthetic-client", "synthetic-secret", :client_options => {:site => "https://synthetic-provider.example.invalid", :token_url => "/oauth/token", :authorize_url => "/oauth/authorize"})
    controller = ActionController::Base.new
    token_env = Rack::MockRequest.env_for("http://example.org/form")
    token_env["rack.session"] = @session
    controller.set_request!(ActionDispatch::Request.new(token_env))
    @token = controller.send(:form_authenticity_token)
    controller.send(:commit_csrf_token, controller.request)
  end
  after do
    @prior_config.each { |key, value| OmniAuth.config.public_send("#{key}=", value) }
    ActionController::Base.allow_forgery_protection = @prior_forgery
    ActionController::Base.forgery_protection_origin_check = @prior_origin
  end
  def request(path, method: "GET", params: {}, session: @session)
    env = Rack::MockRequest.env_for("http://example.org#{path}", :method => method, :params => params)
    env["rack.session"] = session
    env["HTTP_ORIGIN"] = @origin if @origin
    @app.call(env)
  end
  it "accepts authentic POST, issues state, exchanges code, and delivers auth token" do
    status, headers, = request("/auth/ynab", :method => "POST", :params => {:authenticity_token => @token})
    expect(status).to eq(302)
    expect(headers["location"]).to start_with("https://synthetic-provider.example.invalid/oauth/authorize")
    state = @session.fetch("omniauth.state")
    expect(state).to match(/\A[0-9a-f]{48}\z/)
    stub_request(:post, "https://synthetic-provider.example.invalid/oauth/token").with(:body => hash_including("code" => "synthetic-code", "grant_type" => "authorization_code")).to_return(:status => 200, :headers => {"Content-Type" => "application/json"}, :body => '{"access_token":"synthetic-token","token_type":"Bearer","expires_in":3600}')
    status, _, body = request("/auth/ynab/callback", :params => {:code => "synthetic-code", :state => state})
    expect(status).to eq(200)
    expect(body).to eq(["synthetic-token"])
    expect(@session).not_to have_key("omniauth.state")
    status, _, body = request("/auth/ynab/callback", :params => {:code => "synthetic-code", :state => state})
    expect(status).to eq(403)
    expect(body).to eq(["csrf_detected"])
    expect(a_request(:post, "https://synthetic-provider.example.invalid/oauth/token")).to have_been_made.once
  end
  it "rejects missing, invalid and another-session CSRF tokens before redirect" do
    [nil, "invalid", @token].each_with_index do |token, i|
      status, _, body = request("/auth/ynab", :method => "POST", :params => token ? {:authenticity_token => token} : {}, :session => i == 2 ? {} : @session)
      expect(status).to eq(403)
      expect(body).to eq(["ActionController::InvalidAuthenticityToken"])
    end
  end
  it "rejects cross-origin authentic POST and disallows GET initiation" do
    @origin = "https://attacker.example.invalid"
    status, _, body = request("/auth/ynab", :method => "POST", :params => {:authenticity_token => @token})
    expect(status).to eq(403)
    expect(body).to eq(["ActionController::InvalidAuthenticityToken"])
    status, _, body = request("/auth/ynab")
    expect(status).to eq(200)
    expect(body).to eq(["passthrough"])
  end
  it "rejects missing, mismatched and another-session OAuth state without token exchange" do
    request("/auth/ynab", :method => "POST", :params => {:authenticity_token => @token})
    state = @session.fetch("omniauth.state")
    [[{}, @session], [{:state => "wrong"}, @session], [{:state => state}, {}]].each do |params, session|
      status, _, body = request("/auth/ynab/callback", :params => params.merge(:code => "synthetic-code"), :session => session)
      expect(status).to eq(403)
      expect(body).to eq(["csrf_detected"])
    end
    expect(a_request(:post, "https://synthetic-provider.example.invalid/oauth/token")).not_to have_been_made
  end
end
