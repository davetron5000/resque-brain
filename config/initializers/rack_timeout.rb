# frozen_string_literal: true

Rack::Timeout.service_timeout = (ENV['RACK_SERVICE_TIMEOUT_SECONDS'] || 10).to_i
Rack::Timeout.wait_timeout    = (ENV['RACK_WAIT_TIMEOUT_SECONDS']    || 10).to_i
