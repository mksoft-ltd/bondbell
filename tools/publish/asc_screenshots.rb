# Upload Bondbell's framed App Store screenshots (version 1.0.0, en-GB) via the
# raw API and verify them server-side by md5, count and order.
#
# Not deliver: its read-back races ASC processing and re-uploads "missing"
# shots, leaving doubled sets under a success line (store-publisher memory).
#
#   ios/fastlane/screenshots/en-GB/<n>_iphone69.png -> APP_IPHONE_67 (6.9", 1320x2868)
#   ios/fastlane/screenshots/en-GB/<n>_ipad13.png   -> APP_IPAD_PRO_3GEN_129 (13", 2064x2752)
#
#   --verify   read-back only
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/asc_screenshots.rb [--verify]
require_relative "asc"
require "digest"

APP_ID = "6834613888"
VERSION = "1.0.0"
LOCALE = "en-GB"
DIR = File.expand_path("../../ios/fastlane/screenshots/#{LOCALE}", __dir__)
SETS = { "iphone69" => "APP_IPHONE_67", "ipad13" => "APP_IPAD_PRO_3GEN_129" }
VERIFY_ONLY = ARGV.include?("--verify")

def h1(t) = puts("\n== #{t} ==")

code, body = ASC.get("/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=#{VERSION}")
ASC.expect!(code, body, 200, context: "finding version")
vid = body["data"].first&.dig("id") or abort "no IOS version #{VERSION}"
code, body = ASC.get("/v1/appStoreVersions/#{vid}/appStoreVersionLocalizations")
ASC.expect!(code, body, 200, context: "listing localizations")
loc = body["data"].find { |l| l.dig("attributes", "locale") == LOCALE } or abort "no #{LOCALE} localization"

def sets_for(loc_id)
  code, body = ASC.get("/v1/appStoreVersionLocalizations/#{loc_id}/appScreenshotSets?limit=50")
  ASC.expect!(code, body, 200, context: "listing screenshot sets")
  body["data"].to_h { |s| [s.dig("attributes", "screenshotDisplayType"), s["id"]] }
end

def shots_in(set_id)
  code, body = ASC.get("/v1/appScreenshotSets/#{set_id}/appScreenshots?limit=50")
  ASC.expect!(code, body, 200, context: "listing screenshots")
  body["data"]
end

unless VERIFY_ONLY
  SETS.each do |suffix, type|
    files = Dir["#{DIR}/*_#{suffix}.png"].sort_by { |f| File.basename(f).to_i }
    abort "no #{suffix} PNGs" if files.empty?
    h1 "#{type}: #{files.size} files"
    set_id = sets_for(loc["id"])[type]
    if set_id
      old = shots_in(set_id)
      old.each { |s| c, r = ASC.delete("/v1/appScreenshots/#{s['id']}"); ASC.expect!(c, r, 204, context: "deleting old shot") }
      puts "  reusing set #{set_id}, deleted #{old.size} existing"
    else
      c, r = ASC.post("/v1/appScreenshotSets", { data: { type: "appScreenshotSets",
        attributes: { screenshotDisplayType: type },
        relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc["id"] } } } } })
      ASC.expect!(c, r, 201, context: "creating set #{type}")
      set_id = r.dig("data", "id")
      puts "  created set #{set_id}"
    end
    ids = []
    files.each do |path|
      bytes = File.binread(path)
      c, r = ASC.post("/v1/appScreenshots", { data: { type: "appScreenshots",
        attributes: { fileName: File.basename(path), fileSize: bytes.bytesize },
        relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } } } } })
      ASC.expect!(c, r, 201, context: "reserving #{File.basename(path)}")
      sid = r.dig("data", "id")
      r.dig("data", "attributes", "uploadOperations").each do |op|
        uri = URI(op["url"])
        req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
        (op["requestHeaders"] || []).each { |hh| req[hh["name"]] = hh["value"] }
        req.body = bytes.byteslice(op["offset"], op["length"])
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) { |h| h.request(req) }
        abort "  PUT failed #{res.code}" unless res.code.to_i.between?(200, 299)
      end
      c, r = ASC.patch("/v1/appScreenshots/#{sid}", { data: { type: "appScreenshots", id: sid,
        attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } } })
      ASC.expect!(c, r, 200, context: "committing #{File.basename(path)}")
      ids << sid
      puts "  #{File.basename(path)} -> #{sid}"
    end
    c, r = ASC.patch("/v1/appScreenshotSets/#{set_id}/relationships/appScreenshots",
                     { data: ids.map { |i| { type: "appScreenshots", id: i } } })
    ASC.expect!(c, r, 204, context: "ordering #{type}")
  end
end

h1 "read-back (waiting for processing)"
ok = true
SETS.each do |suffix, type|
  local = Dir["#{DIR}/*_#{suffix}.png"].sort_by { |f| File.basename(f).to_i }.map { |f| Digest::MD5.file(f).hexdigest }
  set_id = sets_for(loc["id"])[type]
  unless set_id
    puts "  #{type}: NO SET"
    ok = false
    next
  end
  remote = nil
  30.times do
    remote = shots_in(set_id)
    break if remote.all? { |s| %w[COMPLETE FAILED].include?(s.dig("attributes", "assetDeliveryState", "state")) }
    sleep 5
  end
  states = remote.map { |s| s.dig("attributes", "assetDeliveryState", "state") }
  sizes = remote.map { |s| a = s.dig("attributes", "imageAsset"); a ? "#{a['width']}x#{a['height']}" : "?" }.uniq
  md5s = remote.map { |s| s.dig("attributes", "sourceFileChecksum") }
  good = md5s == local && states.all?("COMPLETE")
  ok &&= good
  puts "  #{good ? 'ok      ' : 'MISMATCH'} #{type}: #{remote.size} remote / #{local.size} local, order #{md5s == local ? 'matches' : 'DIFFERS'}, states #{states.tally}, sizes #{sizes.join(',')}"
  remote.each { |s| e = s.dig("attributes", "assetDeliveryState", "errors"); puts "    error: #{e}" if e && !e.empty? }
end
abort "\nScreenshot sets do not match." unless ok
puts "\nBoth App Store screenshot sets match the repo exactly, in order."
