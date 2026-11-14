# App Store setup for Bondbell 1.0.0, raw API (no deliver), then a read-back of
# every field against ios/fastlane/metadata.
#
# --write sets:
#   * listing text: appInfoLocalization (name, subtitle, privacy URL) and
#     appStoreVersionLocalization (description, keywords, promo, support and
#     marketing URLs). What's New is NOT written: a first version has none
#     (release_notes.txt stays in the repo for 1.0.1+).
#   * copyright, categories (primary/secondary from the metadata files)
#   * App Review details (contact, notes, no demo account)
#   * age rating declaration per docs/AGE_RATING.md (all None / No -> 4+)
#   * content rights: USES_THIRD_PARTY_CONTENT (the app downloads and shows
#     NS&I's published prize files)
#   * price Free (base GBR) and availability in every territory
# Release type is left as the record has it (AFTER_APPROVAL). Nothing attaches
# a build or submits anything.
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/asc_app_setup.rb [--write]
require_relative "asc"

APP_ID = "6834613888"
VERSION = "1.0.0"
CONTENT_RIGHTS = "USES_THIRD_PARTY_CONTENT"
LOCALE = "en-GB"
REPO = File.expand_path("../..", __dir__)
META = "#{REPO}/ios/fastlane/metadata"
WRITE = ARGV.include?("--write")

# Enums take NONE; booleans take false (memory: asc-age-rating-attribute-types).
AGE_ENUMS = %w[
  alcoholTobaccoOrDrugUseOrReferences contests gamblingSimulated gunsOrOtherWeapons
  horrorOrFearThemes matureOrSuggestiveThemes medicalOrTreatmentInformation
  profanityOrCrudeHumor sexualContentGraphicAndNudity sexualContentOrNudity
  violenceCartoonOrFantasy violenceRealistic violenceRealisticProlongedGraphicOrSadistic
]
AGE_BOOLS = %w[
  advertising ageAssurance gambling healthOrWellnessTopics lootBox messagingAndChat
  parentalControls socialMedia unrestrictedWebAccess userGeneratedContent
]
AGE_NULLABLE = %w[kidsAgeBand developerAgeRatingInfoUrl gracRatingClassificationNumber socialMediaAgeRestricted]

def h1(t) = puts("\n== #{t} ==")

def all_pages(path)
  out = []
  while path
    code, body = ASC.get(path)
    ASC.expect!(code, body, 200, context: "GET #{path}")
    out.concat(body["data"] || [])
    path = body.dig("links", "next")
  end
  out
end

# The live app price, resolved to its customerPrice. The schedule GET answers a
# 200 stub even when unset (memory: asc-price-schedule-stub-false-positive),
# so read the manual prices themselves.
def live_app_price
  code, body = ASC.get("/v1/appPriceSchedules/#{APP_ID}/manualPrices?include=appPricePoint,territory&limit=10")
  return nil unless code == 200 && body["data"]&.any?

  pt = (body["included"] || []).find { |i| i["type"] == "appPricePoints" }
  { count: body["data"].size, price: pt&.dig("attributes", "customerPrice"),
    territory: body["data"].first.dig("relationships", "territory", "data", "id") }
end

def available_territories
  code, body = ASC.get("/v1/apps/#{APP_ID}/appAvailabilityV2")
  return nil unless code == 200

  aid = body.dig("data", "id")
  terrs = all_pages("/v2/appAvailabilities/#{aid}/territoryAvailabilities?limit=200")
  { new: body.dig("data", "attributes", "availableInNewTerritories"),
    available: terrs.count { |t| t.dig("attributes", "available") }, total: terrs.size }
end

def file(rel) = File.read("#{META}/#{rel}").strip

$ok = true
def check(label, live, want)
  same = live.to_s.strip == want.to_s.strip
  $ok &&= same
  shown = live.to_s.length > 70 ? "#{live.to_s[0, 67].inspect}... (#{live.to_s.length} chars)" : live.inspect
  puts "  #{same ? 'ok      ' : 'MISMATCH'} #{label}: #{shown}"
end

# ------------------------------------------------------------------ lookups
code, body = ASC.get("/v1/apps/#{APP_ID}/appInfos")
ASC.expect!(code, body, 200, context: "listing appInfos")
info = body["data"].find { |i| i.dig("attributes", "state") != "READY_FOR_DISTRIBUTION" } or abort "no editable appInfo"
info_id = info["id"]

code, body = ASC.get("/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=#{VERSION}")
ASC.expect!(code, body, 200, context: "finding version 1.0")
version = body["data"].first or abort "no IOS version #{VERSION}"
vid = version["id"]

# ------------------------------------------------------------------- writes
if WRITE
  h1 "listing text"
  code, body = ASC.get("/v1/appInfos/#{info_id}/appInfoLocalizations")
  ASC.expect!(code, body, 200, context: "listing appInfoLocalizations")
  il = body["data"].find { |l| l.dig("attributes", "locale") == LOCALE } or abort "no #{LOCALE} appInfoLocalization"
  code, res = ASC.patch("/v1/appInfoLocalizations/#{il['id']}", { data: { type: "appInfoLocalizations", id: il["id"],
    attributes: { name: file("#{LOCALE}/name.txt"), subtitle: file("#{LOCALE}/subtitle.txt"),
                  privacyPolicyUrl: file("#{LOCALE}/privacy_url.txt") } } })
  ASC.expect!(code, res, 200, context: "patching appInfoLocalization")
  puts "  appInfoLocalization written"

  code, body = ASC.get("/v1/appStoreVersions/#{vid}/appStoreVersionLocalizations")
  ASC.expect!(code, body, 200, context: "listing version localizations")
  vl = body["data"].find { |l| l.dig("attributes", "locale") == LOCALE }
  vattrs = { description: file("#{LOCALE}/description.txt"), keywords: file("#{LOCALE}/keywords.txt"),
             promotionalText: file("#{LOCALE}/promotional_text.txt"),
             marketingUrl: file("#{LOCALE}/marketing_url.txt"), supportUrl: file("#{LOCALE}/support_url.txt") }
  if vl
    code, res = ASC.patch("/v1/appStoreVersionLocalizations/#{vl['id']}",
                          { data: { type: "appStoreVersionLocalizations", id: vl["id"], attributes: vattrs } })
    ASC.expect!(code, res, 200, context: "patching version localization")
  else
    code, res = ASC.post("/v1/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations",
      attributes: vattrs.merge(locale: LOCALE),
      relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: vid } } } } })
    ASC.expect!(code, res, 201, context: "creating version localization")
  end
  puts "  appStoreVersionLocalization written (no whatsNew on a first version)"

  code, res = ASC.patch("/v1/appStoreVersions/#{vid}",
                        { data: { type: "appStoreVersions", id: vid, attributes: { copyright: file("copyright.txt") } } })
  ASC.expect!(code, res, 200, context: "setting copyright")
  puts "  copyright written"

  h1 "categories"
  code, res = ASC.patch("/v1/appInfos/#{info_id}", { data: { type: "appInfos", id: info_id, relationships: {
    primaryCategory: { data: { type: "appCategories", id: file("primary_category.txt") } },
    secondaryCategory: { data: { type: "appCategories", id: file("secondary_category.txt") } } } } })
  ASC.expect!(code, res, 200, context: "setting categories")
  puts "  #{file('primary_category.txt')} / #{file('secondary_category.txt')}"

  h1 "review details"
  rattrs = { contactFirstName: file("review_information/first_name.txt"),
             contactLastName: file("review_information/last_name.txt"),
             contactPhone: file("review_information/phone_number.txt"),
             contactEmail: file("review_information/email_address.txt"),
             notes: file("review_information/notes.txt"), demoAccountRequired: false }
  code, body = ASC.get("/v1/appStoreVersions/#{vid}/appStoreReviewDetail")
  if code == 200 && body["data"]
    rid = body["data"]["id"]
    code, res = ASC.patch("/v1/appStoreReviewDetails/#{rid}", { data: { type: "appStoreReviewDetails", id: rid, attributes: rattrs } })
    ASC.expect!(code, res, 200, context: "patching review details")
  else
    code, res = ASC.post("/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: rattrs,
      relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: vid } } } } })
    ASC.expect!(code, res, 201, context: "creating review details")
  end
  puts "  written (notes #{rattrs[:notes].length} chars)"
end

if WRITE
  h1 "age rating declaration"
  attrs = AGE_ENUMS.to_h { |k| [k, "NONE"] }.merge(AGE_BOOLS.to_h { |k| [k, false] })
  attrs["ageRatingOverrideV2"] = "NONE"
  code, res = ASC.patch("/v1/ageRatingDeclarations/#{info_id}",
                        { data: { type: "ageRatingDeclarations", id: info_id, attributes: attrs } })
  ASC.expect!(code, res, 200, context: "patching the age rating declaration")
  puts "  written (#{attrs.size} attributes)"

  h1 "content rights"
  code, res = ASC.patch("/v1/apps/#{APP_ID}",
                        { data: { type: "apps", id: APP_ID, attributes: { contentRightsDeclaration: CONTENT_RIGHTS } } })
  ASC.expect!(code, res, 200, context: "setting content rights")
  puts "  #{CONTENT_RIGHTS}"


  h1 "price (Free)"
  live = live_app_price
  if live && live[:price].to_f.zero?
    puts "  already Free"
  else
    free = all_pages("/v1/apps/#{APP_ID}/appPricePoints?filter[territory]=GBR&limit=200")
           .find { |pt| pt.dig("attributes", "customerPrice").to_f.zero? } or abort "no free price point"
    code, res = ASC.post("/v1/appPriceSchedules", {
      data: { type: "appPriceSchedules",
              relationships: { app: { data: { type: "apps", id: APP_ID } },
                               baseTerritory: { data: { type: "territories", id: "GBR" } },
                               manualPrices: { data: [{ type: "appPrices", id: "${price-free}" }] } } },
      included: [{ type: "appPrices", id: "${price-free}", attributes: { startDate: nil },
                   relationships: { appPricePoint: { data: { type: "appPricePoints", id: free["id"] } } } }]
    })
    ASC.expect!(code, res, 201, context: "setting the app price")
    puts "  written"
  end

  h1 "availability (every territory)"
  live = available_territories
  if live
    puts "  already set: #{live[:available]}/#{live[:total]} available (changing it on an existing record is console-only)"
  else
    terrs = all_pages("/v1/territories?limit=200").map { |t| t["id"] }
    code, res = ASC.post("/v2/appAvailabilities", {
      data: { type: "appAvailabilities", attributes: { availableInNewTerritories: true },
              relationships: { app: { data: { type: "apps", id: APP_ID } },
                               territoryAvailabilities: { data: terrs.map { |t| { type: "territoryAvailabilities", id: "${#{t}}" } } } } },
      included: terrs.map { |t| { type: "territoryAvailabilities", id: "${#{t}}", attributes: { available: true },
                                  relationships: { territory: { data: { type: "territories", id: t } } } } }
    })
    ASC.expect!(code, res, 201, context: "setting availability")
    puts "  written for #{terrs.size} territories"
  end
end

# ---------------------------------------------------------------- read-back
h1 "age rating (appInfo #{info_id})"
code, body = ASC.get("/v1/ageRatingDeclarations/#{info_id}")
code, body = ASC.get("/v1/appInfos/#{info_id}/ageRatingDeclaration") unless code == 200
ASC.expect!(code, body, 200, context: "reading the age rating declaration")
a = body.dig("data", "attributes")
nulls = a.select { |k, v| v.nil? && !AGE_NULLABLE.include?(k) }.keys
not_none = a.select { |k, v| AGE_ENUMS.include?(k) && v != "NONE" }.keys +
           a.select { |k, v| AGE_BOOLS.include?(k) && v != false }.keys
puts "  unanswered: #{nulls.empty? ? 'none' : nulls.join(', ')}"
puts "  not None/No: #{not_none.empty? ? 'none' : not_none.join(', ')}"
$ok &&= nulls.empty? && not_none.empty?
code, body = ASC.get("/v1/appInfos/#{info_id}")
puts "  computed appStoreAgeRating: #{body.dig('data', 'attributes', 'appStoreAgeRating').inspect}"

h1 "app"
code, body = ASC.get("/v1/apps/#{APP_ID}")
check("contentRightsDeclaration", body.dig("data", "attributes", "contentRightsDeclaration"), CONTENT_RIGHTS)

h1 "price and availability"
price = live_app_price
puts "  price: #{price ? "#{price[:territory]} #{price[:price]} (#{price[:count]} manual price)" : 'NOT SET'}"
$ok &&= price && price[:price].to_f.zero?
avail = available_territories
puts "  availability: #{avail ? "#{avail[:available]}/#{avail[:total]} territories, availableInNewTerritories=#{avail[:new]}" : 'NOT SET'}"
$ok &&= avail && avail[:available] == avail[:total] && avail[:total] >= 175

h1 "appInfo categories and localization"
code, body = ASC.get("/v1/appInfos/#{info_id}?include=primaryCategory,secondaryCategory")
ASC.expect!(code, body, 200, context: "reading appInfo")
check("primary category", body.dig("data", "relationships", "primaryCategory", "data", "id"), file("primary_category.txt"))
check("secondary category", body.dig("data", "relationships", "secondaryCategory", "data", "id"), file("secondary_category.txt"))
code, body = ASC.get("/v1/appInfos/#{info_id}/appInfoLocalizations")
il = body["data"].find { |l| l.dig("attributes", "locale") == LOCALE }.fetch("attributes")
check("name", il["name"], file("#{LOCALE}/name.txt"))
check("subtitle", il["subtitle"], file("#{LOCALE}/subtitle.txt"))
check("privacyPolicyUrl", il["privacyPolicyUrl"], file("#{LOCALE}/privacy_url.txt"))

h1 "version #{VERSION} (#{vid})"
code, body = ASC.get("/v1/appStoreVersions/#{vid}")
va = body.dig("data", "attributes")
puts "  state: #{va['appStoreState']}  platform: #{va['platform']}"
puts "  releaseType: #{va['releaseType']}"
check("copyright", va["copyright"], file("copyright.txt"))
code, body = ASC.get("/v1/appStoreVersions/#{vid}/build")
puts "  build attached: #{body&.dig('data') ? body.dig('data', 'attributes', 'version') : 'none'}"
code, body = ASC.get("/v1/appStoreVersions/#{vid}/appStoreVersionLocalizations")
vl = body["data"].find { |l| l.dig("attributes", "locale") == LOCALE }.fetch("attributes")
check("description", vl["description"], file("#{LOCALE}/description.txt"))
check("keywords", vl["keywords"], file("#{LOCALE}/keywords.txt"))
check("promotionalText", vl["promotionalText"], file("#{LOCALE}/promotional_text.txt"))
check("marketingUrl", vl["marketingUrl"], file("#{LOCALE}/marketing_url.txt"))
check("supportUrl", vl["supportUrl"], file("#{LOCALE}/support_url.txt"))
puts "  whatsNew: #{vl['whatsNew'].inspect} (not editable on a first version)"

h1 "review details"
code, body = ASC.get("/v1/appStoreVersions/#{vid}/appStoreReviewDetail")
ASC.expect!(code, body, 200, context: "reading review details")
rd = body.dig("data", "attributes")
check("contactFirstName", rd["contactFirstName"], file("review_information/first_name.txt"))
check("contactLastName", rd["contactLastName"], file("review_information/last_name.txt"))
check("contactPhone", rd["contactPhone"], file("review_information/phone_number.txt"))
check("contactEmail", rd["contactEmail"], file("review_information/email_address.txt"))
check("notes", rd["notes"], file("review_information/notes.txt"))
check("demoAccountRequired", rd["demoAccountRequired"], "false")
puts "  notes length: #{rd['notes'].to_s.length}/4000"
puts "  WARNING: notes still carry the VIDEO_URL placeholder (checklist D7)" if rd["notes"].to_s.include?("VIDEO_URL")

abort "\nOne or more fields do not match." unless $ok
puts "\nEvery field matches the metadata files."
