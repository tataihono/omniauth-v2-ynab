# omniauth-v2-ynab — Claude guidance

## What this repo is

A single-strategy OmniAuth gem for YNAB OAuth2. It is a **direct implementation** of the OmniAuth strategy interface — it does not inherit from `omniauth-oauth2`. Everything lives in one strategy file.

## Key files

| File | Purpose |
|---|---|
| `lib/omniauth/strategies/ynab.rb` | The strategy — start here for any auth-flow changes. |
| `lib/omniauth-ynab/version.rb` | Gem version constant. |
| `omniauth-v2-ynab.gemspec` | Dependencies. Runtime: `omniauth ~> 2.0`, `oauth2 ~> 2.0`. |
| `spec/omniauth/strategies/ynab_spec.rb` | Full RSpec suite. |
| `spec/helper.rb` | RSpec config — loads `omniauth-ynab`, sets up Rack::Test and WebMock. |
| `.rubocop.yml` | RuboCop 1.x config. Target Ruby: 3.1. |
| `.github/workflows/ci.yml` | CI — runs `bundle exec rake` (spec + rubocop) on Ruby 3.1–3.4 + head. |
| `.github/workflows/release.yml` | Release — triggers after CI passes on main. Auto-bumps minor version unless already bumped, tags, creates GitHub Release, pushes to RubyGems. |

## Commands

```sh
bundle exec rspec          # tests only
bundle exec rubocop        # lint only
bundle exec rake           # both (matches CI)
```

## Architecture notes

- The strategy includes `OmniAuth::Strategy` directly and implements `request_phase`, `callback_phase`, `authorize_params`, `token_params`, and `build_access_token` by hand.
- CSRF state is stored in the Rack session under `omniauth.state` and validated in `callback_phase`.
- PKCE is opt-in (`pkce: true`). The verifier is stored in the session under `omniauth.pkce.verifier` between request and callback phase.
- `deep_symbolize` is a local helper because `oauth2 2.x` requires symbolized keys in `OAuth2::Client` options.
- `omniauth-rails_csrf_protection` is a **runtime requirement** for Rails apps using omniauth 2.x — it is listed as a dev dependency in the gemspec and should be called out in app-level Gemfiles.

## Dependency constraints

- `omniauth ~> 2.0` — omniauth 2.x changed default allowed request methods to POST only; CSRF is handled externally by `omniauth-rails_csrf_protection`.
- `oauth2 ~> 2.0` — `get_token` params are now fully merged in the second positional argument; the third argument is `access_token_opts`.
- Do not re-add `simplecov`, `coveralls`, or `omniauth-oauth2` — these were in the original but are not used.

## Testing conventions

- Tests use `OmniAuth.config.test_mode = true` in `before`/`after` blocks — do not remove these.
- `CallbackError` specs test exact string output from `#message`, not regex — keep assertions strict.
- New auth-flow behaviour needs both a positive and a failure-path test.

## Releasing

Releases are fully automated. Push to `main` → CI runs → on success, the release workflow:
- Compares `VERSION` in `lib/omniauth-ynab/version.rb` against the latest git tag
- If already bumped (version > tag): tags, builds, publishes to RubyGems, creates GitHub Release
- If not bumped (version == tag): auto-bumps the minor version, then does the above

To release a specific version (e.g. a major bump), just update `version.rb` manually before pushing. The release workflow will detect the higher version and publish it without an additional bump.

The `RUBYGEMS_API_KEY` secret must be set in the repository settings for gem pushes to work.

## Versioning

Follow semver. Published as `omniauth-v2-ynab` on RubyGems to distinguish from the unmaintained `omniauth-ynab` gem. The Ruby constant (`OmniAuth::Strategies::YNAB`) is unchanged.
