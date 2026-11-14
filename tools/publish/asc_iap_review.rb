# Attach App Store review material to Bondbell's four IAPs: the review note
# from docs/IAP_PRODUCTS.md and the review screenshot from store_assets/iap_review/
# (captured from a normal, non-SCREENSHOT_MODE debug build on an iPhone 6.9"
# simulator against the real App Store sandbox). With both, an IAP leaves
# MISSING_METADATA for READY_TO_SUBMIT. Idempotent. Nothing is submitted:
# adding the first IAPs to the version's review submission stays a console
# step from each IAP's own page (house-facts §15).
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/asc_iap_review.rb
require_relative "asc"
require "digest"

APP_ID = "6834613888"
REPO = File.expand_path("../..", __dir__)

PRO_NOTE = <<~NOTE.strip
  Non-consumable unlock, no subscription. Unlocks: unlimited holders (free: one),
  checking any earlier month NS&I lists (free: latest draw), unclaimed-prize search
  across all saved bonds at once (free: one number at a time), and the History tab.
  Reach it from Settings > "See what Pro adds". To try every Pro feature without
  buying, use sample mode ("Try with sample numbers" in onboarding, or Settings >
  "Sample mode"); the full walkthrough is in the App Review notes. "Restore purchases" is
  on the Pro screen and in Settings.
NOTE
TIP_NOTE = <<~NOTE.strip
  Optional consumable tip. It unlocks nothing and changes nothing in the app; the app
  says so next to the buttons ("Tips don't unlock anything"). Shown in the Tip jar card
  in Settings, and once as a quiet card under a real result that lists prizes. It is
  never shown on a no-prize result or in sample mode, so it cannot read as paying to
  change a result.
NOTE

TIP = { note: TIP_NOTE, shot: "store_assets/iap_review/tips.png" }
PRODUCTS = {
  "com.froggyeye.bondbell.pro" => { note: PRO_NOTE, shot: "store_assets/iap_review/pro.png" },
  "com.froggyeye.bondbell.tip.small" => TIP,
  "com.froggyeye.bondbell.tip.medium" => TIP,
  "com.froggyeye.bondbell.tip.large" => TIP
}

def h1(t) = puts("\n== #{t} ==")

def upload_parts(ops, bytes)
  ops.each do |op|
    uri = URI(op["url"])
    req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
    (op["requestHeaders"] || []).each { |h| req[h["name"]] = h["value"] }
    req.body = bytes.byteslice(op["offset"], op["length"])
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                          open_timeout: 15, read_timeout: 120, write_timeout: 120) { |h| h.request(req) }
    abort "  upload part failed: HTTP #{res.code} #{res.body}" unless res.code.to_i.between?(200, 299)
  end
end

def screenshot_of(iap_id)
  code, body = ASC.get("/v2/inAppPurchases/#{iap_id}/appStoreReviewScreenshot")
  code == 200 ? body["data"] : nil
end

code, body = ASC.get("/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")
ASC.expect!(code, body, 200, context: "listing IAPs")
by_pid = body["data"].each_with_object({}) { |p, h| h[p.dig("attributes", "productId")] = p }

PRODUCTS.each do |pid, spec|
  iap = by_pid[pid] or abort "#{pid} does not exist on App Store Connect — run asc_iap.rb first"
  iap_id = iap["id"]
  h1 "#{pid} (#{iap_id})"

  # ------------------------------------------------------------ review note
  if iap.dig("attributes", "reviewNote").to_s == spec[:note]
    puts "  review note already set"
  else
    code, res = ASC.patch("/v2/inAppPurchases/#{iap_id}",
                          { data: { type: "inAppPurchases", id: iap_id, attributes: { reviewNote: spec[:note] } } })
    ASC.expect!(code, res, 200, context: "setting the review note for #{pid}")
    puts "  review note written (#{spec[:note].length} chars)"
  end

  # ------------------------------------------------------- review screenshot
  path = File.join(REPO, spec[:shot])
  bytes = File.binread(path)
  md5 = Digest::MD5.hexdigest(bytes)
  existing = screenshot_of(iap_id)
  if existing
    a = existing["attributes"]
    done = a.dig("assetDeliveryState", "state") == "COMPLETE"
    if done && a["sourceFileChecksum"] == md5
      # ASC renames the file to "SOURCE" once processed, so match on checksum.
      puts "  screenshot already uploaded (md5 #{md5}, COMPLETE)"
      next
    end
    puts "  replacing screenshot #{a['fileName']} (state #{a.dig('assetDeliveryState', 'state')})"
    code, res = ASC.delete("/v1/inAppPurchaseAppStoreReviewScreenshots/#{existing['id']}")
    ASC.expect!(code, res, 204, context: "deleting the old screenshot for #{pid}")
  end

  code, res = ASC.post("/v1/inAppPurchaseAppStoreReviewScreenshots", {
    data: {
      type: "inAppPurchaseAppStoreReviewScreenshots",
      attributes: { fileName: File.basename(path), fileSize: bytes.bytesize },
      relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap_id } } }
    }
  })
  ASC.expect!(code, res, 201, context: "reserving the screenshot for #{pid}")
  shot_id = res.dig("data", "id")
  upload_parts(res.dig("data", "attributes", "uploadOperations"), bytes)
  code, res = ASC.patch("/v1/inAppPurchaseAppStoreReviewScreenshots/#{shot_id}", {
    data: { type: "inAppPurchaseAppStoreReviewScreenshots", id: shot_id,
            attributes: { uploaded: true, sourceFileChecksum: md5 } }
  })
  ASC.expect!(code, res, 200, context: "committing the screenshot for #{pid}")
  puts "  screenshot uploaded (#{File.basename(path)}, #{bytes.bytesize} bytes, md5 #{md5})"
end

# ---------------------------------------------------------------- read-back
# Asset processing is asynchronous; wait for COMPLETE, then read the state.
h1 "read-back"
ok = true
PRODUCTS.each do |pid, spec|
  iap_id = by_pid[pid]["id"]
  shot = nil
  20.times do
    shot = screenshot_of(iap_id)
    break if shot && %w[COMPLETE FAILED].include?(shot.dig("attributes", "assetDeliveryState", "state"))
    sleep 6
  end
  code, iap = ASC.get("/v2/inAppPurchases/#{iap_id}")
  ASC.expect!(code, iap, 200, context: "re-reading #{pid}")
  a = iap.dig("data", "attributes")
  sa = shot&.dig("attributes") || {}
  note_ok = a["reviewNote"].to_s == spec[:note]
  md5_ok = sa["sourceFileChecksum"] == Digest::MD5.hexdigest(File.binread(File.join(REPO, spec[:shot])))
  puts "  #{pid}: state=#{a['state']} note=#{note_ok ? 'ok' : 'MISMATCH'} " \
       "screenshot=#{shot ? (md5_ok ? 'md5 matches' : 'md5 MISMATCH') : '(none)'} #{sa.dig('assetDeliveryState', 'state') || ''} " \
       "#{sa['imageAsset'] ? "#{sa['imageAsset']['width']}x#{sa['imageAsset']['height']}" : ''}"
  ok &&= note_ok && md5_ok && sa.dig("assetDeliveryState", "state") == "COMPLETE" && a["state"] != "MISSING_METADATA"
end
abort "\nOne or more IAPs are not complete." unless ok
puts "\nAll #{PRODUCTS.size} IAPs have a review note and screenshot and have left MISSING_METADATA."
