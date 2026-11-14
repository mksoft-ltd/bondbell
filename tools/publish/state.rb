# Read-only probe of both stores' live state for Bondbell. Writes nothing
# (the Play edit it opens is deleted).
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/state.rb
require_relative "asc"
require_relative "play"

APP_ID = "6834613888"
BUNDLE_ID = "com.froggyeye.bondbell"
PRODUCTS = %w[
  com.froggyeye.bondbell.pro
  com.froggyeye.bondbell.tip.small
  com.froggyeye.bondbell.tip.medium
  com.froggyeye.bondbell.tip.large
]

puts "== ASC app record =="
code, body = ASC.get("/v1/apps?filter[bundleId]=#{BUNDLE_ID}&limit=10")
ASC.expect!(code, body, 200, context: "listing apps")
(body["data"] || []).each do |a|
  at = a["attributes"]
  puts "  id=#{a['id']} name=#{at['name'].inspect} sku=#{at['sku']} primaryLocale=#{at['primaryLocale']} contentRights=#{at['contentRightsDeclaration'].inspect}"
end

puts "\n== ASC versions =="
code, body = ASC.get("/v1/apps/#{APP_ID}/appStoreVersions?limit=20")
ASC.expect!(code, body, 200, context: "listing versions")
(body["data"] || []).each do |v|
  at = v["attributes"]
  puts "  id=#{v['id']} #{at['platform']} #{at['versionString']} state=#{at['appStoreState']} release=#{at['releaseType']}"
end

puts "\n== ASC builds =="
code, body = ASC.get("/v1/builds?filter[app]=#{APP_ID}&limit=50&sort=-uploadedDate")
ASC.expect!(code, body, 200, context: "listing builds")
puts "  (none)" if (body["data"] || []).empty?
(body["data"] || []).each do |b|
  at = b["attributes"]
  puts "  id=#{b['id']} version=#{at['version']} state=#{at['processingState']} uploaded=#{at['uploadedDate']}"
end

puts "\n== ASC appInfos =="
code, infos = ASC.get("/v1/apps/#{APP_ID}/appInfos")
ASC.expect!(code, infos, 200, context: "listing appInfos")
(infos["data"] || []).each do |i|
  c, locs = ASC.get("/v1/appInfos/#{i['id']}/appInfoLocalizations?limit=50")
  puts "  appInfo #{i['id']} state=#{i.dig('attributes', 'state')} rating=#{i.dig('attributes', 'appStoreAgeRating').inspect}: " +
       (c == 200 ? (locs["data"] || []).map { |l| "#{l.dig('attributes', 'locale')}=#{l.dig('attributes', 'name').inspect}" }.join(", ") : "HTTP #{c}")
end

puts "\n== ASC review submissions =="
code, body = ASC.get("/v1/reviewSubmissions?filter[app]=#{APP_ID}&limit=20")
puts "  HTTP #{code}: " + ((body["data"] || []).map { |s| "#{s['id']} #{s.dig('attributes', 'state')}" }.join(", ").then { |s| s.empty? ? "(none)" : s })

puts "\n== ASC in-app purchases =="
code, iaps = ASC.get("/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")
ASC.expect!(code, iaps, 200, context: "listing IAPs")
puts "  (none)" if (iaps["data"] || []).empty?
(iaps["data"] || []).each do |p|
  at = p["attributes"]
  puts "  id=#{p['id']} productId=#{at['productId']} type=#{at['inAppPurchaseType']} state=#{at['state']} name=#{at['name'].inspect}"
end

puts "\n== Play one-time products =="
code, list = Play.raw("GET", "/oneTimeProducts")
if code == 200
  prods = list["oneTimeProducts"] || []
  puts "  (none)" if prods.empty?
  prods.each { |p| puts "  productId=#{p['productId']} options=#{(p['purchaseOptions'] || []).map { |o| "#{o['purchaseOptionId']}:#{o['state']}" }.join(',')}" }
else
  puts "  HTTP #{code}: #{list.inspect[0, 400]}"
end

puts "\n== Play edit: tracks, bundles, listings, details =="
begin
  Play.inspect_edit do |edit|
    tracks = Play.service.list_edit_tracks(Play::PACKAGE, edit.id)
    (tracks.tracks || []).each do |t|
      rels = (t.releases || []).map { |r| "#{r.status}:#{(r.version_codes || []).join('/')}" }.join(" ")
      puts "  track #{t.track}: #{rels.empty? ? '(no releases)' : rels}"
    end
    bundles = Play.service.list_edit_bundles(Play::PACKAGE, edit.id).bundles || []
    puts "  bundles: #{bundles.empty? ? '(none)' : bundles.map { |b| "vc=#{b.version_code}" }.join(', ')}"
    listings = Play.service.list_edit_listings(Play::PACKAGE, edit.id)
    puts "  listing locales: #{(listings.listings || []).map(&:language).join(', ').then { |s| s.empty? ? '(none)' : s }}"
    d = Play.service.get_edit_detail(Play::PACKAGE, edit.id)
    puts "  details: email=#{d.contact_email.inspect} website=#{d.contact_website.inspect} lang=#{d.default_language.inspect}"
  end
rescue => e
  puts "  edit probe failed: #{e.class}: #{e.message[0, 300]}"
end
