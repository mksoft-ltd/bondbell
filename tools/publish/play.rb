# Shared Google Play Android Publisher client for this repo's publish scripts.
#
# Run with fastlane's bundled gems, which already carry googleauth and the
# androidpublisher API client:
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/<script>.rb
require "googleauth"
require "google/apis/androidpublisher_v3"
require "json"
require "net/http"
require "uri"

module Play
  PACKAGE = "com.froggyeye.bondbell"
  SCOPE = "https://www.googleapis.com/auth/androidpublisher"

  module_function

  def service
    @service ||= begin
      svc = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
      svc.authorization = credentials
      svc
    end
  end

  def credentials
    @credentials ||= Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(File.expand_path(ENV.fetch("PLAY_JSON_KEY").sub(/\A~/, Dir.home))),
      scope: SCOPE
    )
  end

  def access_token
    credentials.fetch_access_token!["access_token"]
  end

  # Read-only inspection: opens an edit, yields it, then DELETES it. An edit
  # that is never committed leaves the live listing untouched, so this is the
  # safe way to look without changing anything.
  def inspect_edit
    edit = service.insert_edit(PACKAGE)
    yield edit
  ensure
    service.delete_edit(PACKAGE, edit.id) if edit
  end

  # The monetization endpoints are not in the bundled client, so they are
  # called over plain HTTP. See tools/publish/play_iap.rb.
  def raw(method, path, body = nil, query = {})
    url = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{PACKAGE}#{path}"
    url += "?" + URI.encode_www_form(query) unless query.empty?
    uri = URI(url)
    klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put,
              "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete }.fetch(method)
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{access_token}"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body) if body
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    parsed = res.body.to_s.empty? ? nil : (JSON.parse(res.body) rescue res.body)
    [res.code.to_i, parsed]
  end

  def expect!(code, body, *expect, context:)
    return body if expect.include?(code)

    detail = if body.is_a?(Hash) && body["error"]
               "#{body.dig('error', 'status')}: #{body.dig('error', 'message')}"
             else
               body.inspect
             end
    abort "FAILED #{context}\n  HTTP #{code}\n  #{detail}"
  end
end
