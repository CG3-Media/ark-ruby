# Ark Ruby Client

Automatically capture and report errors from your Ruby/Rails applications to [Ark](https://github.com/CG3-Media/ark).

## Installation

Add to your Gemfile:

```ruby
gem "ark-ruby", github: "CG3-Media/ark-ruby"
```

Then run:

```bash
bundle install
```

## Configuration

### Rails

The gem auto-configures with Rails. Just set your environment variables:

```bash
export ARK_API_KEY="your-project-api-key"
export ARK_API_URL="http://localhost:3000"  # Your Ark server URL
```

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

### Adding Context

Add user and request context to all errors:

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

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `api_key` | `ENV["ARK_API_KEY"]` | Your project's API key |
| `api_url` | `http://localhost:3000` | Your Ark server URL |
| `environment` | `Rails.env` | Environment name |
| `enabled` | `true` | Enable/disable error reporting |
| `async` | `true` | Send errors in background thread |
| `excluded_exceptions` | `[ActiveRecord::RecordNotFound, ...]` | Exceptions to ignore |
| `before_send` | `nil` | Callback to modify/filter events |

## Development

```bash
cd gems/ark-ruby
bundle install
bundle exec rspec
```

## License

MIT
