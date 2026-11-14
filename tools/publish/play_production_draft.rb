# Prepare Bondbell's Play production release as a DRAFT from an already
# uploaded versionCode (a track update, not an upload). A never-published app
# accepts only status "draft" on production. Release notes are written for
# exactly the listing's locales (house-facts §19) from changelogs/<vc>.txt.
# Rollout and "Send changes for review" stay console clicks.
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/2.237.0/libexec \
#   GEM_PATH=$GEM_HOME /opt/homebrew/opt/ruby/bin/ruby tools/publish/play_production_draft.rb [versionCode]
require_relative "play"

REPO = File.expand_path("../..", __dir__)
VC = (ARGV[0] || File.read("#{REPO}/pubspec.yaml")[/^version:\s*\S+\+(\d+)/, 1]).to_s
NAME = File.read("#{REPO}/pubspec.yaml")[/^version:\s*([^\s+]+)/, 1]

code, edit = Play.raw("POST", "/edits", {})
Play.expect!(code, edit, 200, context: "opening an edit")
eid = edit["id"]
code, ls = Play.raw("GET", "/edits/#{eid}/listings")
Play.expect!(code, ls, 200, context: "listing locales")
locales = (ls["listings"] || []).map { |l| l["language"] }
notes = locales.map do |lang|
  f = "#{REPO}/android/fastlane/metadata/android/#{lang}/changelogs/#{VC}.txt"
  abort "missing #{f}" unless File.exist?(f)
  { language: lang, text: File.read(f).strip }
end
code, bundles = Play.raw("GET", "/edits/#{eid}/bundles")
abort "versionCode #{VC} not uploaded" unless (bundles["bundles"] || []).any? { |b| b["versionCode"].to_s == VC }
code, res = Play.raw("PUT", "/edits/#{eid}/tracks/production", { track: "production",
  releases: [{ name: "#{NAME} (#{VC})", versionCodes: [VC], status: "draft", releaseNotes: notes }] })
Play.expect!(code, res, 200, context: "setting production draft")
code, res = Play.raw("POST", "/edits/#{eid}:commit")
Play.expect!(code, res, 200, context: "committing")
puts "committed production draft #{NAME} (#{VC}), notes for #{locales.join(', ')}"

Play.inspect_edit do |fresh|
  (Play.service.list_edit_tracks(Play::PACKAGE, fresh.id).tracks || []).each do |t|
    rels = (t.releases || []).map { |r| "#{r.status}:#{(r.version_codes || []).join('/')} #{r.name.inspect} notes=#{(r.release_notes || []).map(&:language).join(',')}" }
    puts "  #{t.track}: #{rels.empty? ? '(no releases)' : rels.join(' | ')}"
  end
end
