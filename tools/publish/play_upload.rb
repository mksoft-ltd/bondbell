# Upload the release AAB to a Google Play track, driving the raw Publishing
# API rather than `fastlane supply`.
#
# WHY NOT supply: its chunked uploader crawls at ~64KB/s from this machine and
# dies after ~16 minutes with "Upload has already been terminated", whatever
# the timeout setting (house-facts §28, proven on ApexRoute). A plain
# `uploadType=media` POST of the raw bytes pushes the same bundle in seconds.
# supply remains fine for metadata and changelogs.
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/play_upload.rb
#
# Flags:
#   --track=internal      which track to release on (default internal)
#   --status=draft        release status: draft or completed (default draft)
#   --dry-run             do everything except the commit, then delete the edit
#   --version-code=N      skip the upload and release a code already uploaded
#                         (Play refuses a second upload of a used code)
#
# The edit is committed only at the very end. Every earlier failure leaves the
# live listing untouched, so a retry is safe.
require_relative "play"

REPO = File.expand_path("../..", __dir__)
AAB = "#{REPO}/build/app/outputs/bundle/release/app-release.aab"

DRY = ARGV.include?("--dry-run")
TRACK = (ARGV.find { |a| a.start_with?("--track=") } || "--track=internal").split("=", 2).last
STATUS = (ARGV.find { |a| a.start_with?("--status=") } || "--status=draft").split("=", 2).last
REUSE_VC = (ARGV.find { |a| a.start_with?("--version-code=") } || "=").split("=", 2).last.to_s

# The release name follows pubspec, so a later round cannot ship versionCode 7
# under a release labelled 1.0.0.
VERSION_NAME = File.read("#{REPO}/pubspec.yaml")[/^version:\s*([^\s+]+)/, 1] or
  abort "could not read version from pubspec.yaml"

def h1(t) = puts("\n== #{t} ==")

h1 "open edit"
edit = Play.service.insert_edit(Play::PACKAGE)
eid = edit.id
puts "  edit=#{eid} expires=#{Time.at(edit.expiry_time_seconds.to_i)}"

h1 "bundle"
if !REUSE_VC.empty?
  vc = REUSE_VC.to_i
  puts "  reusing versionCode=#{vc} already uploaded (no upload)"
else
  abort "  no AAB at #{AAB} — run `flutter build appbundle --release` first" unless File.exist?(AAB)
  size = File.size(AAB)
  puts "  uploading #{AAB}"
  puts "  #{(size / 1024.0 / 1024).round(1)} MB"
  uri = URI("https://androidpublisher.googleapis.com/upload/androidpublisher/v3/" \
            "applications/#{Play::PACKAGE}/edits/#{eid}/bundles?uploadType=media")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Bearer #{Play.access_token}"
  req["Content-Type"] = "application/octet-stream"
  req["Content-Length"] = size.to_s
  req.body_stream = File.open(AAB, "rb")
  t0 = Time.now
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 1800,
                        write_timeout: 1800, open_timeout: 60) { |h| h.request(req) }
  body = (JSON.parse(res.body) rescue res.body)
  Play.expect!(res.code.to_i, body, 200, context: "bundle upload")
  vc = body["versionCode"]
  puts "  uploaded versionCode=#{vc} sha256=#{body['sha256']} in #{(Time.now - t0).round}s"
end

h1 "track #{TRACK}"
# Release notes are deliberately NOT written here. Play silently swallows notes
# for locales the listing does not have (house-facts §19), and the changelog
# text is release-manager's deliverable, not this script's.
track_body = {
  track: TRACK,
  releases: [{
    name: "#{VERSION_NAME} (#{vc})",
    versionCodes: [vc.to_s],
    status: STATUS
  }]
}
code, data = Play.raw("PUT", "/edits/#{eid}/tracks/#{TRACK}", track_body)
Play.expect!(code, data, 200, context: "setting the #{TRACK} track")
puts "  #{JSON.dump(data)}"

if DRY
  Play.service.delete_edit(Play::PACKAGE, eid)
  puts "\nDRY RUN — edit deleted, nothing committed."
  exit 0
end

h1 "commit"
# A commit can return ECONNRESET *after* the server committed (house-facts §28).
# If that happens, do NOT re-issue the write: re-read with a fresh edit first.
code, data = Play.raw("POST", "/edits/#{eid}:commit")
Play.expect!(code, data, 200, context: "committing edit #{eid}")
puts "  COMMITTED edit #{eid}"

h1 "read-back"
Play.inspect_edit do |fresh|
  tracks = Play.service.list_edit_tracks(Play::PACKAGE, fresh.id)
  (tracks.tracks || []).each do |t|
    rels = (t.releases || []).map do |r|
      "status=#{r.status} codes=#{(r.version_codes || []).join('/')} name=#{r.name.inspect}"
    end
    puts "  #{t.track}: #{rels.empty? ? '(no releases)' : rels.join(' | ')}"
  end
  bundles = Play.service.list_edit_bundles(Play::PACKAGE, fresh.id).bundles || []
  puts "  bundles: #{bundles.map { |b| "vc=#{b.version_code} sha1=#{b.sha1}" }.join(', ')}"
end
