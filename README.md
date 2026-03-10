# omniauth-ynab

[![Gem Version](https://img.shields.io/gem/v/omniauth-ynab.svg)](https://rubygems.org/gems/omniauth-ynab)
[![CI](https://github.com/tataihono/omniauth-ynab/actions/workflows/ci.yml/badge.svg)](https://github.com/tataihono/omniauth-ynab/actions/workflows/ci.yml)

OmniAuth strategy for [YNAB (You Need A Budget)](https://www.youneedabudget.com/) OAuth2.

Compatible with **omniauth 2.x**, **oauth2 2.x**, and **omniauth-rails_csrf_protection 1.x**.

---

## Installation

Add to your `Gemfile`:

```ruby
gem "omniauth-ynab"
gem "omniauth-rails_csrf_protection" # required for Rails with omniauth 2.x
```

Then run:

```sh
bundle install
```

---

## Usage

### Register a YNAB application

Create an OAuth application at [app.youneedabudget.com/oauth/applications](https://app.youneedabudget.com/oauth/applications). Set the redirect URI to match your callback URL (e.g. `https://yourapp.com/auth/ynab/callback`).

### Rails

In `config/initializers/omniauth.rb`:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :ynab, ENV["YNAB_CLIENT_ID"], ENV["YNAB_CLIENT_SECRET"]
end
```

Add routes:

```ruby
# config/routes.rb
get  "/auth/:provider/callback", to: "sessions#create"
get  "/auth/failure",            to: "sessions#failure"
```

Trigger the flow from a view using a CSRF-protected link (provided by `omniauth-rails_csrf_protection`):

```erb
<%= link_to "Connect YNAB", "/auth/ynab", method: :post %>
```

Handle the callback in your controller:

```ruby
class SessionsController < ApplicationController
  def create
    auth = request.env["omniauth.auth"]
    token      = auth.credentials.token
    expires_at = auth.credentials.expires_at
    # store token and create/find the user ...
  end

  def failure
    # request.env["omniauth.error"] contains the error
  end
end
```

### Rack (non-Rails)

```ruby
use OmniAuth::Builder do
  provider :ynab, ENV["YNAB_CLIENT_ID"], ENV["YNAB_CLIENT_SECRET"]
end
```

---

## Configuration options

All options are passed as keyword arguments to `provider`.

| Option | Default | Description |
|---|---|---|
| `client_options` | `{site: "https://app.youneedabudget.com"}` | Override any `OAuth2::Client` option, e.g. `authorize_url`. |
| `authorize_params` | `{}` | Extra params appended to the authorization redirect URL. |
| `authorize_options` | `[:scope]` | Top-level option keys that should be forwarded as authorize params. |
| `token_params` | `{}` | Extra params sent in the token exchange request. |
| `token_options` | `[]` | Top-level option keys forwarded as token params. |
| `provider_ignores_state` | `false` | Skip CSRF state validation (not recommended). |
| `pkce` | `false` | Enable PKCE (S256 code challenge). Recommended for public clients. |

### PKCE

```ruby
provider :ynab, ENV["YNAB_CLIENT_ID"], ENV["YNAB_CLIENT_SECRET"], pkce: true
```

### Overriding the YNAB endpoint (e.g. for testing)

```ruby
provider :ynab, "id", "secret",
  client_options: {site: "https://staging.example.com"}
```

---

## Credentials

After a successful callback, `request.env["omniauth.auth"].credentials` contains:

| Key | Description |
|---|---|
| `token` | The OAuth2 access token. |
| `refresh_token` | Present if the token is expiring and a refresh token was issued. |
| `expires_at` | Unix timestamp of expiry (if applicable). |
| `expires` | Boolean — whether the token expires. |

---

## Development

### Prerequisites

- Ruby 3.1+
- Bundler 2.x

### Setup

```sh
git clone https://github.com/tataihono/omniauth-ynab.git
cd omniauth-ynab
bundle install
```

### Running tests

```sh
bundle exec rspec
```

### Linting

```sh
bundle exec rubocop
```

### Run both (same as CI)

```sh
bundle exec rake
```

---

## Contributing

1. Fork the repo and create a branch from `main`.
2. Add tests for any new behaviour.
3. Ensure `bundle exec rake` passes.
4. Open a pull request.

---

## License

MIT. See [LICENSE.md](LICENSE.md) for details.

Original gem by [Mike Berkman](https://github.com/berkman/omniauth-ynab).
