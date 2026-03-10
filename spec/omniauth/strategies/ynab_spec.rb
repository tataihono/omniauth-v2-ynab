require "helper"

describe OmniAuth::Strategies::YNAB do
  def app
    lambda do |_env|
      [200, {}, ["Hello."]]
    end
  end

  let(:fresh_strategy) { Class.new(OmniAuth::Strategies::YNAB) }

  before do
    OmniAuth.config.test_mode = true
  end

  after do
    OmniAuth.config.test_mode = false
  end

  describe "Subclassing Behavior" do
    subject { fresh_strategy }

    it "performs the OmniAuth::Strategy included hook" do
      expect(OmniAuth.strategies).to include(OmniAuth::Strategies::YNAB)
      expect(OmniAuth.strategies).to include(subject)
    end
  end

  describe "#client" do
    subject { fresh_strategy }

    it "is initialized with symbolized client_options" do
      instance = subject.new(app, client_options: {"authorize_url" => "https://example.com"})
      expect(instance.client.options[:authorize_url]).to eq("https://example.com")
    end

    it "deep-symbolizes nested client_options" do
      instance = subject.new(app, client_options: {"ssl" => {"ca_path" => "/etc/ssl/certs"}})
      # deep_symbolize converts string keys to symbols; the value lands in client.options[:ssl]
      expect(instance.client.options[:ssl]).to eq(ca_path: "/etc/ssl/certs")
    end
  end

  describe "#authorize_params" do
    subject { fresh_strategy }

    it "includes any authorize params passed in the :authorize_params option" do
      instance = subject.new("abc", "def", authorize_params: {foo: "bar", baz: "zip"})
      expect(instance.authorize_params["foo"]).to eq("bar")
      expect(instance.authorize_params["baz"]).to eq("zip")
    end

    it "includes top-level options that are marked as :authorize_options" do
      instance = subject.new("abc", "def", authorize_options: %i[scope foo], scope: "bar", foo: "baz")
      expect(instance.authorize_params["scope"]).to eq("bar")
      expect(instance.authorize_params["foo"]).to eq("baz")
    end

    it "includes a random state parameter and stores it in the session" do
      instance = subject.new("abc", "def")
      params = instance.authorize_params
      expect(params.keys).to include("state")
      expect(instance.session["omniauth.state"]).to eq(params["state"])
      expect(instance.session["omniauth.state"]).not_to be_empty
    end

    context "when pkce is enabled" do
      it "adds code_challenge and code_challenge_method to the params" do
        instance = subject.new("abc", "def", pkce: true)
        params = instance.authorize_params
        expect(params[:code_challenge]).not_to be_nil
        expect(params[:code_challenge_method]).to eq("S256")
      end

      it "stores the pkce verifier in the session" do
        instance = subject.new("abc", "def", pkce: true)
        instance.authorize_params
        expect(instance.session["omniauth.pkce.verifier"]).not_to be_nil
      end
    end
  end

  describe "#token_params" do
    subject { fresh_strategy }

    it "includes any token params passed in the :token_params option" do
      instance = subject.new("abc", "def", token_params: {foo: "bar", baz: "zip"})
      expect(instance.token_params).to eq("foo" => "bar", "baz" => "zip")
    end

    it "includes top-level options that are marked as :token_options" do
      instance = subject.new("abc", "def", token_options: %i[scope foo], scope: "bar", foo: "baz")
      expect(instance.token_params).to eq("scope" => "bar", "foo" => "baz")
    end
  end

  describe "#callback_phase" do
    subject { fresh_strategy }

    it "calls fail! with the error reason when the request contains an error" do
      instance = subject.new("abc", "def")
      allow(instance).to receive(:request) do
        double("Request", params: {"error_reason" => "user_denied", "error" => "access_denied"})
      end
      expect(instance).to receive(:fail!).with("user_denied", anything)
      instance.callback_phase
    end

    it "calls fail! with :csrf_detected when state is missing" do
      instance = subject.new("abc", "def")
      allow(instance).to receive(:request) do
        double("Request", params: {"code" => "abc123", "state" => ""})
      end
      expect(instance).to receive(:fail!).with(:csrf_detected, anything)
      instance.callback_phase
    end

    it "calls fail! with :csrf_detected when state does not match the session" do
      instance = subject.new("abc", "def")
      instance.session["omniauth.state"] = "correct_state"
      allow(instance).to receive(:request) do
        double("Request", params: {"code" => "abc123", "state" => "wrong_state"})
      end
      expect(instance).to receive(:fail!).with(:csrf_detected, anything)
      instance.callback_phase
    end
  end
end

describe OmniAuth::Strategies::YNAB::CallbackError do
  describe "#message" do
    it "joins all non-nil attributes with ' | '" do
      instance = described_class.new("error", "description", "uri")
      expect(instance.message).to eq("error | description | uri")
    end

    it "omits nil attributes" do
      instance = described_class.new(nil, :symbol)
      expect(instance.message).to eq("symbol")
    end
  end
end
