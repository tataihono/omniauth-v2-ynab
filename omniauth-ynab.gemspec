lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "omniauth-ynab/version"

Gem::Specification.new do |gem|
  gem.add_dependency "oauth2",   "~> 2.0"
  gem.add_dependency "omniauth", "~> 2.0"

  gem.authors       = ["tataihono"]
  gem.email         = ["tataihono.nikora@gmail.com"]
  gem.description   = "A YNAB OAuth2 strategy for OmniAuth."
  gem.summary       = gem.description
  gem.homepage      = "https://github.com/tataihono/omniauth-ynab"
  gem.licenses      = %w[MIT]
  gem.metadata      = {"rubygems_mfa_required" => "true"}

  gem.required_ruby_version = ">= 3.1"

  gem.executables   = `git ls-files -- bin/*`.split("\n").collect { |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.name          = "omniauth-ynab"
  gem.require_paths = %w[lib]
  gem.version       = OmniAuth::YNAB::VERSION
end
