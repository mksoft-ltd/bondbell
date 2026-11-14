# Converge Bondbell's Google Play one-time products on docs/IAP_PRODUCTS.md:
#
#   com.froggyeye.bondbell.pro         GBP 4.99  (Pro unlock, non-consumable in app)
#   com.froggyeye.bondbell.tip.small   GBP 1.99  (consumed by the app)
#   com.froggyeye.bondbell.tip.medium  GBP 4.99  (consumed by the app)
#   com.froggyeye.bondbell.tip.large   GBP 9.99  (consumed by the app)
#
# Play has no consumable flag: all four are managed one-time products and
# "consumable" is the app calling consumePurchase on the tip tokens.
#
# API details (store-publisher memory, house-facts §18):
#   * legacy `inappproducts` is retired; this uses monetization.onetimeproducts.
#   * PATCH uses lowercase `onetimeproducts`, reads/batch use `oneTimeProducts`.
#   * convertRegionPrices takes a TAX-EXCLUSIVE price (shelf / 1.2 for UK VAT)
#     and returns tax-inclusive prices; the GB row is asserted before writing.
#   * the regions version is taken from the convert response, so conversion
#     and write cannot disagree (BG moved to EUR in 2026).
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/play_iap.rb
#
# PLAY_IAP_DRY_RUN=1 stops after the price conversion and assertion.
require_relative "play"

OPTION_ID = "buy"
DRY_RUN = %w[1 true yes].include?(ENV["PLAY_IAP_DRY_RUN"].to_s.downcase)

TIP_DESC = "An optional tip to say thank you to the developer. Tips are a thank-you only: they unlock no features, content or results."

def gbp(units, nanos) = { "currencyCode" => "GBP", "units" => units.to_s, "nanos" => nanos }

PRODUCTS = [
  { product_id: "com.froggyeye.bondbell.pro", title: "Bondbell Pro",
    description: "One-time unlock, no subscription. Adds unlimited holders, earlier draws NS&I still lists, unclaimed search for all saved bonds at once, and history and stats.",
    base_units: 4, base_nanos: 158_333_333, target_gb: gbp(4, 990_000_000) },
  { product_id: "com.froggyeye.bondbell.tip.small", title: "Small tip", description: TIP_DESC,
    base_units: 1, base_nanos: 658_333_333, target_gb: gbp(1, 990_000_000) },
  { product_id: "com.froggyeye.bondbell.tip.medium", title: "Medium tip", description: TIP_DESC,
    base_units: 4, base_nanos: 158_333_333, target_gb: gbp(4, 990_000_000) },
  { product_id: "com.froggyeye.bondbell.tip.large", title: "Large tip", description: TIP_DESC,
    base_units: 8, base_nanos: 325_000_000, target_gb: gbp(9, 990_000_000) }
]

def money(p)
  return "-" unless p
  "#{p['currencyCode']} #{p['units']}.#{format('%02d', p['nanos'].to_i / 10_000_000)}"
end

def h1(t) = puts("\n== #{t} ==")

puts "DRY RUN — preflight and price conversion only, no writes" if DRY_RUN

# PRECONDITION: Play refuses to create any product until an artifact declaring
# com.android.vending.BILLING exists on a track. The error names a permission
# ("To fix, request billing permission") but it is about the app's artifact,
# not the service account — no Play Console permission grant can satisfy it.
# Check it up front so the failure explains itself.
h1 "preflight: billing artifact"
begin
  Play.inspect_edit do |edit|
    bundles = Play.service.list_edit_bundles(Play::PACKAGE, edit.id).bundles || []
    apks = Play.service.list_edit_apks(Play::PACKAGE, edit.id).apks || []
    puts "  bundles: #{bundles.size}   apks: #{apks.size}"
    if bundles.empty? && apks.empty?
      message = <<~MSG
        No AAB or APK has ever been uploaded to #{Play::PACKAGE}.

        Play will reject every product creation with
          "Can't create product. To fix, request billing permission."
        until an artifact carrying com.android.vending.BILLING is on a track
        (the Play Billing library merges that permission in at build time, so
        it will not appear in android/app/src/main/AndroidManifest.xml).

        Upload the release AAB to any track, then re-run this script.
      MSG
      abort message unless DRY_RUN
      puts message.lines.map { |l| "  #{l}" }.join
    end
  end
rescue SystemExit
  raise
rescue => e
  puts "  preflight probe failed (#{e.class}) — continuing: #{e.message[0, 200]}"
end

PRODUCTS.each do |spec|
  pid = spec[:product_id]
  h1 pid

  # Listing descriptions are capped at 200 characters — far tighter than the
  # store listing's own limits and undocumented in the console.
  if spec[:description].length > 200
    abort "  description is #{spec[:description].length} chars, cap is 200"
  end
  puts "  description: #{spec[:description].length}/200 chars"

  puts "-- converting regional prices from a GBP base"
  code, conv = Play.raw("POST", "/pricing:convertRegionPrices", {
    price: { currencyCode: "GBP", units: spec[:base_units].to_s, nanos: spec[:base_nanos] }
  })
  Play.expect!(code, conv, 200, context: "convertRegionPrices for #{pid}")
  converted = conv["convertedRegionPrices"] || {}
  regions_version = conv.dig("regionVersion", "version") or abort "   convert response has no regionVersion"
  puts "   regionsVersion: #{regions_version}"
  abort "   convertRegionPrices returned no regions" if converted.empty?
  puts "   regions: #{converted.size}   GB: #{money(converted.dig('GB', 'price'))}   US: #{money(converted.dig('US', 'price'))}"

  # Assert the base region before writing anything — this is the figure the
  # brief specified, and a silent VAT slip here ships the wrong shelf price.
  gb = converted.dig("GB", "price")
  t = spec[:target_gb]
  unless gb && gb["currencyCode"] == t["currencyCode"] &&
         gb["units"].to_s == t["units"] && gb["nanos"].to_i == t["nanos"]
    abort "   GB price is #{money(gb)} (#{gb.inspect}), expected #{money(t)} — refusing to write"
  end
  puts "   GB asserted at #{money(gb)}"

  if DRY_RUN
    puts "-- dry run: skipping the upsert and activation"
    next
  end

  regional = converted.map do |region_code, entry|
    { regionCode: region_code, price: entry["price"], availability: "AVAILABLE" }
  end

  body = {
    packageName: Play::PACKAGE,
    productId: pid,
    regionsVersion: { version: regions_version },
    listings: [
      { languageCode: "en-GB", title: spec[:title], description: spec[:description] }
    ],
    purchaseOptions: [
      {
        purchaseOptionId: OPTION_ID,
        # legacyCompatible is required for the classic Play Billing flow the
        # Flutter in_app_purchase plugin uses; without it the plugin never
        # resolves the product and the paywall shows nothing to buy.
        buyOption: { legacyCompatible: true },
        regionalPricingAndAvailabilityConfigs: regional,
        newRegionsConfig: {
          availability: "AVAILABLE",
          usdPrice: conv.dig("convertedOtherRegionsPrice", "usdPrice"),
          eurPrice: conv.dig("convertedOtherRegionsPrice", "eurPrice")
        }
      }
    ]
  }

  puts "-- upserting"
  code, res = Play.raw("PATCH", "/onetimeproducts/#{pid}", body, {
    "allowMissing" => "true",
    "updateMask" => "listings,purchaseOptions",
    "regionsVersion.version" => regions_version
  })
  if code == 404
    # Some accounts expose no PATCH route at all and only accept the batch
    # writer. Probe rather than trusting a remembered verb.
    puts "   PATCH 404'd — falling back to oneTimeProducts:batchUpdate"
    code, res = Play.raw("POST", "/oneTimeProducts:batchUpdate", {
      requests: [
        { oneTimeProduct: body, updateMask: "listings,purchaseOptions",
          allowMissing: true, regionsVersion: { version: regions_version } }
      ]
    })
    Play.expect!(code, res, 200, context: "batchUpdate for #{pid}")
    res = (res["oneTimeProducts"] || []).first || {}
  else
    Play.expect!(code, res, 200, context: "upserting #{pid}")
  end
  puts "   upserted"

  state = res.dig("purchaseOptions", 0, "state")
  puts "   purchase option state: #{state}"

  # A freshly upserted purchase option is DRAFT. An inactive option cannot be
  # bought or even tested, so activate it explicitly. Each entry in `requests`
  # is a one-of wrapper: the identifying fields belong on the INNER request.
  if state != "ACTIVE"
    puts "-- activating the purchase option"
    code, act = Play.raw("POST", "/oneTimeProducts/#{pid}/purchaseOptions:batchUpdateStates", {
      requests: [
        {
          activatePurchaseOptionRequest: {
            packageName: Play::PACKAGE,
            productId: pid,
            purchaseOptionId: OPTION_ID
          }
        }
      ]
    })
    Play.expect!(code, act, 200, context: "activating #{OPTION_ID} on #{pid}")
    puts "   activated"
  end
end

if DRY_RUN
  puts "\nDry run complete: every GB shelf price asserted, nothing written."
  exit 0
end

# ---------------------------------------------------------------- read-back
h1 "read-back"
ok = true
PRODUCTS.each do |spec|
  pid = spec[:product_id]
  code, final = Play.raw("GET", "/oneTimeProducts/#{pid}")
  unless code == 200
    puts "\n  #{pid}: read failed HTTP #{code} #{final.inspect[0, 200]}"
    ok = false
    next
  end
  opt = (final["purchaseOptions"] || []).first || {}
  regions = opt["regionalPricingAndAvailabilityConfigs"] || []
  puts "\n  #{pid}"
  puts "    packageName:      #{final['packageName']}"
  (final["listings"] || []).each do |l|
    puts "    listing[#{l['languageCode']}]: #{l['title'].inspect}"
    puts "      #{l['description'].inspect}"
  end
  puts "    option:           #{opt['purchaseOptionId']} state=#{opt['state']} legacyCompatible=#{opt.dig('buyOption', 'legacyCompatible')}"
  puts "    regions priced:   #{regions.size}"
  %w[GB US AU CA].each do |cc|
    r = regions.find { |x| x["regionCode"] == cc }
    puts "      #{cc}: #{money(r && r['price'])} #{r && r['availability']}"
  end
  final_gb = regions.find { |x| x["regionCode"] == "GB" }&.dig("price")
  if money(final_gb) == money(spec[:target_gb]) && opt["state"] == "ACTIVE"
    puts "    OK — ACTIVE at #{money(final_gb)} in GB"
  else
    puts "    MISMATCH — GB #{money(final_gb)} state #{opt['state']}"
    ok = false
  end
end
abort "\nOne or more products did not read back as expected." unless ok
puts "\nAll #{PRODUCTS.size} products are ACTIVE and priced."
