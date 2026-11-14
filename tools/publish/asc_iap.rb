# Converge Bondbell's in-app purchases on App Store Connect to
# docs/IAP_PRODUCTS.md:
#
#   com.froggyeye.bondbell.pro         NON_CONSUMABLE  GBP 4.99
#   com.froggyeye.bondbell.tip.small   CONSUMABLE      GBP 1.99
#   com.froggyeye.bondbell.tip.medium  CONSUMABLE      GBP 4.99
#   com.froggyeye.bondbell.tip.large   CONSUMABLE      GBP 9.99
#
# Each product gets the v2 IAP resource (Family Sharing off), an en-GB
# localisation, a GBR-based price schedule (Apple equalises the rest) and
# availability in every territory. Re-running converges; nothing is submitted.
# Review notes and screenshots are tools/publish/asc_iap_review.rb.
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/asc_iap.rb
require_relative "asc"

APP_ID = "6834613888"
LOCALE = "en-GB"
BASE_TERRITORY = "GBR"
DESCRIPTION_CAP = 55

TIP_DESC = "Optional thank-you. Unlocks nothing."
PRODUCTS = [
  { product_id: "com.froggyeye.bondbell.pro", type: "NON_CONSUMABLE", reference_name: "Bondbell Pro",
    display_name: "Bondbell Pro", description: "Unlimited holders, earlier draws and stats", price: "4.99" },
  { product_id: "com.froggyeye.bondbell.tip.small", type: "CONSUMABLE", reference_name: "Tip small",
    display_name: "Small tip", description: TIP_DESC, price: "1.99" },
  { product_id: "com.froggyeye.bondbell.tip.medium", type: "CONSUMABLE", reference_name: "Tip medium",
    display_name: "Medium tip", description: TIP_DESC, price: "4.99" },
  { product_id: "com.froggyeye.bondbell.tip.large", type: "CONSUMABLE", reference_name: "Tip large",
    display_name: "Large tip", description: TIP_DESC, price: "9.99" }
]

def h1(t) = puts("\n== #{t} ==")
def h2(t) = puts("-- #{t}")

# Apple's IAP price points are paginated well past any single page size, so
# follow `links.next` rather than trusting one limit=200 request.
def all_price_points(iap_id, territory)
  path = "/v2/inAppPurchases/#{iap_id}/pricePoints?filter[territory]=#{territory}&limit=200"
  points = []
  while path
    code, body = ASC.get(path)
    ASC.expect!(code, body, 200, context: "listing price points for #{iap_id}")
    points.concat(body["data"] || [])
    path = body.dig("links", "next")
  end
  points
end

def territory_ids
  @territory_ids ||= begin
    ids = []
    path = "/v1/territories?limit=200"
    while path
      code, body = ASC.get(path)
      ASC.expect!(code, body, 200, context: "listing territories")
      ids.concat((body["data"] || []).map { |t| t["id"] })
      path = body.dig("links", "next")
    end
    ids
  end
end

# The live GBR customer prices on a product's schedule, newest read each time.
# A bare GET of the schedule answers 200 with a placeholder whose id is the IAP
# id even when nothing is priced, so always ask for the prices themselves.
def current_prices(iap_id)
  code, prices = ASC.get(
    "/v1/inAppPurchasePriceSchedules/#{iap_id}/manualPrices" \
    "?include=inAppPurchasePricePoint,territory&limit=50"
  )
  return [] unless code == 200

  inc = (prices["included"] || []).each_with_object({}) { |i, h| h[[i["type"], i["id"]]] = i }
  (prices["data"] || []).map do |pr|
    point = inc[["inAppPurchasePricePoints", pr.dig("relationships", "inAppPurchasePricePoint", "data", "id")]]
    {
      id: pr["id"],
      territory: pr.dig("relationships", "territory", "data", "id"),
      customer_price: point&.dig("attributes", "customerPrice"),
      proceeds: point&.dig("attributes", "proceeds"),
      start_date: pr.dig("attributes", "startDate")
    }
  end
end

# --------------------------------------------------------------- preflight
h1 "preflight: description lengths"
PRODUCTS.each do |spec|
  len = spec[:description].length
  flag = len > DESCRIPTION_CAP ? "OVER CAP" : "ok"
  puts "  #{spec[:product_id]}: #{len}/#{DESCRIPTION_CAP} #{flag}"
  abort "  refusing to write — #{spec[:product_id]} description is #{len} chars" if len > DESCRIPTION_CAP
end

# ----------------------------------------------------------------- existing
h1 "existing in-app purchases"
code, body = ASC.get("/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")
ASC.expect!(code, body, 200, context: "listing IAPs")
existing = (body["data"] || []).each_with_object({}) { |p, h| h[p.dig("attributes", "productId")] = p }
puts existing.empty? ? "  (none)" : existing.keys.map { |k| "  #{k}" }.join("\n")

PRODUCTS.each do |spec|
  pid = spec[:product_id]
  h1 pid

  # ------------------------------------------------------------ the product
  iap = existing[pid]
  if iap
    puts "  already exists (id=#{iap['id']}) — not recreating"
    live_type = iap.dig("attributes", "inAppPurchaseType")
    if live_type != spec[:type]
      # The type is immutable once created, so this is a stop, not a warning:
      # writing a price onto the wrong product type is worse than no price.
      abort "  type is #{live_type}, table says #{spec[:type]} — immutable, fix the table or the product"
    end
    if iap.dig("attributes", "name") != spec[:reference_name]
      code, res = ASC.patch("/v2/inAppPurchases/#{iap['id']}", {
        data: { type: "inAppPurchases", id: iap["id"],
                attributes: { name: spec[:reference_name] } }
      })
      ASC.expect!(code, res, 200, context: "renaming #{pid}")
      puts "  reference name -> #{spec[:reference_name].inspect}"
    end
  else
    code, res = ASC.post("/v2/inAppPurchases", {
      data: {
        type: "inAppPurchases",
        attributes: {
          name: spec[:reference_name],
          productId: pid,
          inAppPurchaseType: spec[:type],
          familySharable: false
        },
        relationships: { app: { data: { type: "apps", id: APP_ID } } }
      }
    })
    ASC.expect!(code, res, 201, context: "creating #{pid}")
    iap = res["data"]
    puts "  created id=#{iap['id']} type=#{iap.dig('attributes', 'inAppPurchaseType')}"
  end
  iap_id = iap["id"]

  # -------------------------------------------------------- the localisation
  h2 "localisation (#{LOCALE})"
  code, locs = ASC.get("/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations?limit=50")
  ASC.expect!(code, locs, 200, context: "listing localisations for #{pid}")
  loc = (locs["data"] || []).find { |l| l.dig("attributes", "locale") == LOCALE }
  if loc.nil?
    # The relationship key is `inAppPurchaseV2`; `inAppPurchase` is rejected.
    code, res = ASC.post("/v1/inAppPurchaseLocalizations", {
      data: {
        type: "inAppPurchaseLocalizations",
        attributes: { locale: LOCALE, name: spec[:display_name], description: spec[:description] },
        relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap_id } } }
      }
    })
    ASC.expect!(code, res, 201, context: "creating the #{LOCALE} localisation for #{pid}")
    puts "   created: #{spec[:display_name].inspect} / #{spec[:description].inspect} (#{spec[:description].length} chars)"
  elsif loc.dig("attributes", "name") != spec[:display_name] ||
        loc.dig("attributes", "description") != spec[:description]
    code, res = ASC.patch("/v1/inAppPurchaseLocalizations/#{loc['id']}", {
      data: { type: "inAppPurchaseLocalizations", id: loc["id"],
              attributes: { name: spec[:display_name], description: spec[:description] } }
    })
    ASC.expect!(code, res, 200, context: "updating the #{LOCALE} localisation for #{pid}")
    puts "   updated: #{spec[:display_name].inspect} / #{spec[:description].inspect} (#{spec[:description].length} chars)"
  else
    puts "   already matches: #{loc.dig('attributes', 'name').inspect}"
  end

  # ---------------------------------------------------------------- the price
  h2 "price schedule (#{BASE_TERRITORY} #{spec[:price]})"
  live = current_prices(iap_id)
  base = live.find { |p| p[:territory] == BASE_TERRITORY } || live.first
  if live.any?
    puts "   live: " + live.map { |p| "#{p[:territory]} #{p[:customer_price]}" }.join(", ")
  else
    puts "   live: (none)"
  end

  if base && base[:customer_price].to_f == spec[:price].to_f
    puts "   already at #{spec[:price]} — no write"
  else
    points = all_price_points(iap_id, BASE_TERRITORY)
    abort "   no #{BASE_TERRITORY} price points returned" if points.empty?
    wanted = spec[:price].to_f
    point = points.find { |p| p.dig("attributes", "customerPrice").to_f == wanted }
    if point
      puts "   exact price point #{point['id']} customerPrice=#{point.dig('attributes', 'customerPrice')}"
    else
      # The table asks for the closest available point. Say so loudly rather
      # than silently shipping a price nobody chose.
      point = points.min_by { |p| (p.dig("attributes", "customerPrice").to_f - wanted).abs }
      puts "   NO EXACT POINT at #{spec[:price]} — closest is " \
           "#{point.dig('attributes', 'customerPrice')} (point #{point['id']}, #{points.size} points)"
    end

    code, res = ASC.post("/v1/inAppPurchasePriceSchedules", {
      data: {
        type: "inAppPurchasePriceSchedules",
        relationships: {
          inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } },
          baseTerritory: { data: { type: "territories", id: BASE_TERRITORY } },
          manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${price1}" }] }
        }
      },
      included: [
        {
          type: "inAppPurchasePrices",
          id: "${price1}",
          attributes: { startDate: nil, endDate: nil },
          relationships: {
            inAppPurchasePricePoint: { data: { type: "inAppPurchasePricePoints", id: point["id"] } }
          }
        }
      ]
    })
    ASC.expect!(code, res, 201, context: "writing the price schedule for #{pid}")
    after = current_prices(iap_id)
    puts "   written; now: " + (after.empty? ? "(none)" : after.map { |p| "#{p[:territory]} #{p[:customer_price]}" }.join(", "))
  end

  # --------------------------------------------------------- the availability
  h2 "availability (all territories)"
  # The `iapAvailability` relationship 404s; the availability resource is a
  # singleton whose id is the IAP's own id.
  code, avail = ASC.get("/v1/inAppPurchaseAvailabilities/#{iap_id}?include=availableTerritories&limit[availableTerritories]=1")
  if code == 200
    total = avail.dig("data", "relationships", "availableTerritories", "meta", "paging", "total")
    puts "   already available in #{total} territories"
    if total.to_i < territory_ids.size
      puts "   NOTE: Apple lists #{territory_ids.size} territories — #{territory_ids.size - total.to_i} missing"
    end
  else
    terrs = territory_ids
    code, res = ASC.post("/v1/inAppPurchaseAvailabilities", {
      data: {
        type: "inAppPurchaseAvailabilities",
        attributes: { availableInNewTerritories: true },
        relationships: {
          inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } },
          availableTerritories: { data: terrs.map { |t| { type: "territories", id: t } } }
        }
      }
    })
    ASC.expect!(code, res, 201, context: "setting availability for #{pid}")
    puts "   set for #{terrs.size} territories, availableInNewTerritories=true"
  end
end

# ---------------------------------------------------------------- read-back
h1 "read-back"
code, body = ASC.get("/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")
ASC.expect!(code, body, 200, context: "re-listing IAPs")
wanted = PRODUCTS.each_with_object({}) { |s, h| h[s[:product_id]] = s }
ok = true

(body["data"] || []).each do |p|
  at = p["attributes"]
  spec = wanted[at["productId"]]
  puts "\n  #{at['productId']}#{spec ? '' : '   (not in the table)'}"
  puts "    id:        #{p['id']}"
  puts "    type:      #{at['inAppPurchaseType']}"
  puts "    state:     #{at['state']}"
  puts "    reference: #{at['name'].inspect}"

  c, locs = ASC.get("/v2/inAppPurchases/#{p['id']}/inAppPurchaseLocalizations?limit=50")
  (c == 200 ? locs["data"] : []).each do |l|
    a = l["attributes"]
    puts "    loc[#{a['locale']}]: name=#{a['name'].inspect} desc=#{a['description'].inspect} state=#{a['state']}"
  end

  c, sched = ASC.get("/v1/inAppPurchasePriceSchedules/#{p['id']}?include=baseTerritory")
  base_terr = c == 200 ? sched.dig("data", "relationships", "baseTerritory", "data", "id") : nil
  puts "    baseTerritory: #{base_terr || '(none)'}"

  prices = current_prices(p["id"])
  if prices.empty?
    puts "    price:     (none)"
  else
    prices.each do |pr|
      puts "    price:     #{pr[:territory]} #{pr[:customer_price]} (proceeds #{pr[:proceeds]}, startDate #{pr[:start_date].inspect})"
    end
  end

  c, avail = ASC.get("/v1/inAppPurchaseAvailabilities/#{p['id']}?include=availableTerritories&limit[availableTerritories]=1")
  if c == 200
    puts "    territories: #{avail.dig('data', 'relationships', 'availableTerritories', 'meta', 'paging', 'total')} " \
         "(newTerritories=#{avail.dig('data', 'attributes', 'availableInNewTerritories')})"
  else
    puts "    territories: read failed HTTP #{c}"
  end

  next unless spec

  gbr = prices.find { |pr| pr[:territory] == BASE_TERRITORY }
  if gbr && gbr[:customer_price].to_f == spec[:price].to_f && prices.size == 1
    puts "    OK — #{BASE_TERRITORY} #{spec[:price]}, single manual price"
  elsif gbr && gbr[:customer_price].to_f == spec[:price].to_f
    puts "    OK — #{BASE_TERRITORY} #{spec[:price]} (#{prices.size} manual prices on the schedule)"
  else
    puts "    MISMATCH — table says #{BASE_TERRITORY} #{spec[:price]}, live #{gbr ? gbr[:customer_price] : '(none)'}"
    ok = false
  end
end

missing = wanted.keys - (body["data"] || []).map { |p| p.dig("attributes", "productId") }
unless missing.empty?
  puts "\n  MISSING from App Store Connect: #{missing.join(', ')}"
  ok = false
end

abort "\nOne or more products did not read back as expected." unless ok
puts "\nAll #{PRODUCTS.size} products read back at the prices in the table."
