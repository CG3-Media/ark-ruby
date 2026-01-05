# Ark Ruby Client

Automatically capture and report errors from your Ruby/Rails applications to [Ark](https://github.com/CG3-Media/ark).

## Installation

Add to your Gemfile:

```ruby
gem "ark-ruby", github: "CG3-Media/ark-ruby", require: "ark"
```

Then run:

```bash
bundle install
```

## Configuration

### Rails (YAML)

Create `config/ark.yml` with environment-specific config (like `database.yml`):

```yaml
---
default:
  url: 'https://ark.yourserver.com'

production:
  api:
    key: 'your-production-api-key'
    url: 'https://ark.yourserver.com'
    env: production

staging:
  api:
    key: 'your-staging-api-key'
    url: 'https://ark.yourserver.com'
    env: staging

# Environments without a section (like development/test) won't report errors
```

The gem auto-loads this file on Rails startup and uses the config matching `Rails.env`. **If no config exists for the current environment, errors won't be reported** - so you only need to define the environments where you want error tracking enabled.

### Rails (Environment Variables)

Alternatively, set environment variables:

```bash
export ARK_API_KEY="your-project-api-key"
export ARK_API_URL="https://ark.yourserver.com"
```

### Rails (Initializer)

Or configure in an initializer:

```ruby
# config/initializers/ark.rb
Ark.configure do |config|
  config.api_key = ENV["ARK_API_KEY"]
  config.api_url = ENV["ARK_API_URL"] || "http://localhost:3000"
  config.environment = Rails.env

  # Optional: exclude certain exceptions
  config.excluded_exceptions += ["MyCustomException"]

  # Optional: modify events before sending
  config.before_send = ->(event) {
    # Return nil to skip sending
    # Or modify and return the event
    event
  }
end
```

### Rack / Sinatra

```ruby
require "ark"

Ark.configure do |config|
  config.api_key = ENV["ARK_API_KEY"]
  config.api_url = ENV["ARK_API_URL"]
end

use Ark::RackMiddleware
```

## Usage

### Automatic Error Capture

Once installed, Ark automatically captures:

- **Unhandled exceptions** in your Rails controllers
- **Background job failures** (ActiveJob, Sidekiq)
- **Rack-level errors**

### Manual Error Capture

```ruby
# Capture an exception
begin
  do_something_risky
rescue => e
  Ark.capture_exception(e, context: { user_id: current_user.id })
  raise
end

# Capture a message
Ark.capture_message("Something unexpected happened", context: {
  user_id: current_user.id,
  action: "checkout"
})
```

## Performance Tracking

Ark can automatically track request performance metrics from your Rails app.

### Automatic Tracking

Transaction tracking is **enabled by default**. Every request's timing is automatically captured:

- Endpoint (controller#action)
- Total duration
- Database time
- View render time
- HTTP status code

Data is buffered and sent in batches to minimize overhead.

### Configuration

```ruby
# config/initializers/ark.rb
Ark.configure do |config|
  # Disable transaction tracking entirely
  config.transactions_enabled = false

  # Only track requests slower than 100ms (default: 0 = track all)
  config.transaction_threshold_ms = 100

  # Buffer size before sending (default: 50)
  config.transaction_buffer_size = 50

  # Max seconds between flushes (default: 60)
  config.transaction_flush_interval = 60
end
```

Or in `config/ark.yml`:

```yaml
production:
  api:
    key: 'your-api-key'
  transactions:
    enabled: true
    threshold_ms: 100  # Only track slow requests
```

### Safety Features

Transaction tracking is designed to never impact your application:

- **Buffered sending**: Transactions are batched, not sent individually
- **Async delivery**: Network calls happen in background threads
- **Circuit breaker**: Stops trying if Ark is down (auto-retries after 60s)
- **Capped memory**: Buffer limited to 500 transactions
- **Thread limits**: Max 3 concurrent flush threads
- **Silent failures**: Errors are swallowed, only logged in debug mode

### Adding Context

```ruby
# In ApplicationController
class ApplicationController < ActionController::Base
  before_action :set_ark_context

  private

  def set_ark_context
    Ark.configuration.before_send = ->(event) {
      event[:event][:context][:user] = {
        id: current_user&.id,
        email: current_user&.email
      }
      event
    }
  end
end
```

## Release Tracking

Ark automatically detects your application's release/revision to help you track which version of your code is causing errors.

**Auto-detection priority:**

1. **Environment variables** (checked in order):
   - `HEROKU_SLUG_COMMIT` (Heroku)
   - `RENDER_GIT_COMMIT` (Render)
   - `RAILWAY_GIT_COMMIT_SHA` (Railway)
   - `REVISION` (generic)
   - `GIT_COMMIT` (generic)

2. **REVISION file** - Created by Capistrano during deployment

3. **Git** - Falls back to `git rev-parse HEAD`

**Manual configuration:**

```ruby
Ark.configure do |config|
  config.release = "v1.2.3"  # Or a git SHA
end
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `api_key` | `ENV["ARK_API_KEY"]` | Your project's API key |
| `api_url` | `http://localhost:3000` | Your Ark server URL |
| `environment` | `Rails.env` | Environment name |
| `release` | Auto-detected | Release/version identifier |
| `enabled` | `true` | Enable/disable error reporting |
| `async` | `true` | Send errors in background thread |
| `excluded_exceptions` | `[ActiveRecord::RecordNotFound, ...]` | Exceptions to ignore |
| `before_send` | `nil` | Callback to modify/filter events |
| `transactions_enabled` | `true` | Enable/disable performance tracking |
| `transaction_threshold_ms` | `0` | Min duration to track (0 = all) |
| `transaction_buffer_size` | `50` | Batch size before sending |
| `transaction_flush_interval` | `60` | Max seconds between flushes |

## Development

```bash
cd gems/ark-ruby
bundle install
bundle exec rspec
```

## License

MIT
