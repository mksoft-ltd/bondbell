# Bondbell's Google Play store listing (en-GB only), raw API — no supply.
#
#   (no flag)   read-only: compare the live listing with the repo, delete the edit
#   --write     converge contact details + listing text, commit, read back
#   --images    also replace icon, feature graphic and phone screenshots
#               (and 7"/10" tablet sets if their folders hold PNGs)
#
# Sources: android/fastlane/metadata/android/en-GB/{title,short_description,
# full_description}.txt, images/ under the same folder. Release notes are not
# written here (they belong to the track release; house-facts §19).
#
# Not settable through any Play API (console only): app category, privacy
# policy URL, countries/regions, App content declarations.
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/play_listing.rb [--write] [--images]
require_relative "play"
require "digest"

LANG = "en-GB"
REPO = File.expand_path("../..", __dir__)
META = "#{REPO}/android/fastlane/metadata/android/#{LANG}"
WRITE = ARGV.include?("--write")
IMAGES = ARGV.include?("--images")

DETAILS = {
  "contactEmail" => "info@froggyeye.com",
  "contactWebsite" => "https://bondbell.froggyeye.com",
  "defaultLanguage" => LANG
}

def text(name) = File.read("#{META}/#{name}").strip

IMAGE_SETS = {
  "icon" => Dir["#{META}/images/icon.png"],
  "featureGraphic" => Dir["#{META}/images/featureGraphic.png"],
  "phoneScreenshots" => Dir["#{META}/images/phoneScreenshots/*.png"].sort,
  "sevenInchScreenshots" => Dir["#{META}/images/sevenInchScreenshots/*.png"].sort,
  "tenInchScreenshots" => Dir["#{META}/images/tenInchScreenshots/*.png"].sort
}

def h1(t) = puts("\n== #{t} ==")

$ok = true
def check(label, live, want)
  same = live.to_s.strip == want.to_s.strip
  $ok &&= same
  shown = live.to_s.length > 70 ? "#{live.to_s[0, 67].inspect}... (#{live.to_s.length} chars)" : live.inspect
  puts "  #{same ? 'ok      ' : 'MISMATCH'} #{label}: #{shown}"
end

def open_edit
  code, edit = Play.raw("POST", "/edits", {})
  Play.expect!(code, edit, 200, context: "opening an edit")
  edit["id"]
end

def upload_image(eid, type, path)
  uri = URI("https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/" \
            "#{Play::PACKAGE}/edits/#{eid}/listings/#{LANG}/#{type}?uploadType=media")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Bearer #{Play.access_token}"
  req["Content-Type"] = "image/png"
  req.body = File.binread(path)
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) { |h| h.request(req) }
  body = (JSON.parse(res.body) rescue res.body)
  Play.expect!(res.code.to_i, body, 200, context: "uploading #{type} #{File.basename(path)}")
end

if WRITE
  eid = open_edit
  h1 "write (edit #{eid})"
  code, ls = Play.raw("GET", "/edits/#{eid}/listings")
  Play.expect!(code, ls, 200, context: "listing locales")
  locales = (ls["listings"] || []).map { |l| l["language"] }
  puts "  locales before: #{locales.join(', ')}"
  abort "  unexpected locales #{locales.inspect}: refusing to write" unless (locales - [LANG]).empty?

  code, det = Play.raw("PATCH", "/edits/#{eid}/details", DETAILS)
  Play.expect!(code, det, 200, context: "patching details")
  puts "  details written"

  code, res = Play.raw("PUT", "/edits/#{eid}/listings/#{LANG}", {
    language: LANG, title: text("title.txt"),
    shortDescription: text("short_description.txt"), fullDescription: text("full_description.txt")
  })
  Play.expect!(code, res, 200, context: "writing listing text")
  puts "  listing text written"

  if IMAGES
    IMAGE_SETS.each do |type, files|
      next if files.empty?
      files.each { |f| abort "  missing #{f}" unless File.exist?(f) }
      code, res = Play.raw("DELETE", "/edits/#{eid}/listings/#{LANG}/#{type}")
      Play.expect!(code, res, 200, 204, context: "clearing #{type}")
      files.each { |f| upload_image(eid, type, f) }
      puts "  #{type}: #{files.size} uploaded"
    end
  end

  code, res = Play.raw("POST", "/edits/#{eid}:commit")
  # A commit can ECONNRESET after the server committed (house-facts §28):
  # the read-back below, on a fresh edit, is what decides.
  Play.expect!(code, res, 200, context: "committing edit #{eid}")
  puts "  COMMITTED"
end

eid = open_edit
begin
  h1 "contact details"
  code, det = Play.raw("GET", "/edits/#{eid}/details")
  Play.expect!(code, det, 200, context: "reading details")
  DETAILS.each { |k, v| check(k, det[k], v) }

  h1 "listing #{LANG}"
  code, listings = Play.raw("GET", "/edits/#{eid}/listings")
  Play.expect!(code, listings, 200, context: "listing locales")
  locs = (listings["listings"] || []).map { |l| l["language"] }
  puts "  locales: #{locs.join(', ')}"
  $ok &&= locs == [LANG]
  l = (listings["listings"] || []).find { |x| x["language"] == LANG } || {}
  check("title", l["title"], text("title.txt"))
  check("shortDescription", l["shortDescription"], text("short_description.txt"))
  check("fullDescription", l["fullDescription"], text("full_description.txt"))

  h1 "images"
  IMAGE_SETS.each do |type, files|
    code, res = Play.raw("GET", "/edits/#{eid}/listings/#{LANG}/#{type}")
    Play.expect!(code, res, 200, context: "listing #{type}")
    remote = (res["images"] || []).map { |i| i["sha256"] }
    local = files.map { |f| Digest::SHA256.file(f).hexdigest }
    same = remote == local
    $ok &&= same
    puts "  #{same ? 'ok      ' : 'MISMATCH'} #{type}: #{remote.size} remote / #{local.size} local#{same ? '' : ' (sha256 differ)'}"
  end

  h1 "tracks"
  code, tracks = Play.raw("GET", "/edits/#{eid}/tracks")
  Play.expect!(code, tracks, 200, context: "listing tracks")
  (tracks["tracks"] || []).each do |t|
    rel = (t["releases"] || []).map { |r| "#{r['status']}:#{(r['versionCodes'] || []).join('/')}" }
    puts "  #{t['track']}: #{rel.empty? ? '(no releases)' : rel.join(', ')}"
  end
ensure
  Play.raw("DELETE", "/edits/#{eid}") if eid
end

abort "\nThe Play listing does not match the repo." unless $ok
puts "\nThe Play listing matches the repo."
