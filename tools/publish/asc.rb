# Shared App Store Connect REST client for this repo's publish scripts.
#
# Run with fastlane's bundled gems, which already carry `jwt`:
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/<script>.rb
#
# Several things fastlane cannot do with an App Store Connect API key are done
# here directly: creating the App Store provisioning profile, setting the price
# schedule, filling the age-rating declaration, and creating the in-app
# purchase with its review screenshot. Each has its own script; this file is
# only the transport.
require "jwt"
require "json"
require "net/http"
require "uri"
require "openssl"

module ASC
  BASE = "https://api.appstoreconnect.apple.com"

  module_function

  def token
    key_id = ENV.fetch("ASC_KEY_ID")
    issuer = ENV.fetch("ASC_ISSUER_ID")
    path = File.expand_path(ENV.fetch("ASC_KEY_PATH").sub(/\A~/, Dir.home))
    private_key = OpenSSL::PKey::EC.new(File.read(path))

    JWT.encode(
      { iss: issuer, aud: "appstoreconnect-v1", exp: Time.now.to_i + 20 * 60 },
      private_key,
      "ES256",
      { kid: key_id, typ: "JWT" }
    )
  end

  def request(method, path, body = nil)
    uri = URI(path.start_with?("http") ? path : "#{BASE}#{path}")
    klass = {
      "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post,
      "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete
    }.fetch(method)

    req = klass.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body) if body

    # Timeouts are not optional here. Net::HTTP's defaults let a stalled
    # connection sit for minutes, and on 23 Sep 2026 one `GET /builds` inside
    # the TestFlight poll loop blocked for about twelve and a half minutes: the
    # poll printed a single line, ate most of a 30-minute budget in one call,
    # and looked from the outside exactly like "the build is slow to register".
    # A hung read is indistinguishable from a slow store unless it is capped.
    #
    # A GET is safely repeatable, so it is retried; anything that writes is not
    # retried here, because a timeout does not prove the server did not act.
    attempts = 0
    begin
      attempts += 1
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                            open_timeout: 15, read_timeout: 60, write_timeout: 60) do |h|
        h.request(req)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, IOError, SystemCallError => e
      if method == "GET" && attempts < 3
        warn "  (#{e.class} on #{method} #{uri.path}, retry #{attempts}/2)"
        sleep 2 * attempts
        retry
      end
      raise
    end

    parsed = res.body.to_s.empty? ? nil : (JSON.parse(res.body) rescue res.body)
    [res.code.to_i, parsed]
  end

  def get(path)  = request("GET", path)
  def post(path, body) = request("POST", path, body)
  def patch(path, body) = request("PATCH", path, body)
  def delete(path) = request("DELETE", path)

  # Raise on anything that is not one of `expect`, printing the API's own error
  # detail — ASC's messages name the exact attribute that is wrong, and losing
  # them costs far more time than the extra lines here.
  def expect!(code, body, *expect, context:)
    return body if expect.include?(code)

    detail = if body.is_a?(Hash) && body["errors"]
               body["errors"].map { |e| "#{e['title']}: #{e['detail']}" }.join("\n  ")
             else
               body.inspect
             end
    abort "FAILED #{context}\n  HTTP #{code}\n  #{detail}"
  end
end
