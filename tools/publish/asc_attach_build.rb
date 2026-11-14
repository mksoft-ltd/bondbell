# Attach an uploaded, VALID build to App Store version 1.0.0 and read it back.
# Does not submit. Usage: asc_attach_build.rb [buildNumber]   (default: pubspec's)
require_relative "asc"

APP_ID = "6834613888"
VERSION = "1.0.0"
want = ARGV[0] || File.read(File.expand_path("../../pubspec.yaml", __dir__))[/^version:\s*\S+\+(\d+)/, 1]

code, body = ASC.get("/v1/builds?filter[app]=#{APP_ID}&filter[version]=#{want}&filter[preReleaseVersion.version]=#{VERSION}&limit=5")
ASC.expect!(code, body, 200, context: "finding build #{want}")
build = body["data"].first or abort "build #{want} (#{VERSION}) not found — a failed upload never appears; check TestFlight > Build Uploads"
state = build.dig("attributes", "processingState")
abort "build #{want} is #{state}, not VALID" unless state == "VALID"

code, body = ASC.get("/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=#{VERSION}")
ASC.expect!(code, body, 200, context: "finding version")
vid = body["data"].first&.dig("id") or abort "no IOS version #{VERSION}"

code, res = ASC.patch("/v1/appStoreVersions/#{vid}/relationships/build", { data: { type: "builds", id: build["id"] } })
ASC.expect!(code, res, 204, context: "attaching build")

code, body = ASC.get("/v1/appStoreVersions/#{vid}/build")
ASC.expect!(code, body, 200, context: "reading attached build")
got = body.dig("data", "attributes", "version")
puts "version #{VERSION} (#{vid}) build: #{got} id=#{body.dig('data', 'id')} usesNonExemptEncryption=#{body.dig('data', 'attributes', 'usesNonExemptEncryption').inspect}"
abort "read-back mismatch: #{got.inspect} != #{want}" unless got == want
