#!/usr/bin/env ruby
# Read-only App Store Connect API credential check for AI Buddies.

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

def b64url(bytes)
  Base64.urlsafe_encode64(bytes).delete("=")
end

def der_to_raw_es256(der)
  seq = OpenSSL::ASN1.decode(der)
  seq.value.map do |integer|
    hex = integer.value.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    [hex].pack("H*").rjust(32, "\x00")
  end.join
end

def jwt_for(key_id:, issuer_id:, key_path:)
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = { iss: issuer_id, exp: Time.now.to_i + 1200, aud: "appstoreconnect-v1" }
  unsigned = [b64url(JSON.generate(header)), b64url(JSON.generate(payload))].join(".")
  key = OpenSSL::PKey.read(File.read(key_path))
  signature = der_to_raw_es256(key.sign(OpenSSL::Digest::SHA256.new, unsigned))
  [unsigned, b64url(signature)].join(".")
end

key_id = ENV.fetch("ASC_KEY_ID")
issuer_id = ENV.fetch("ASC_ISSUER_ID")
app_id = ENV.fetch("ASC_APP_ID")
key_path = File.expand_path(
  ENV.fetch("ASC_KEY_FILEPATH", "~/.appstoreconnect/private_keys/AuthKey_#{key_id}.p8")
)

unless File.file?(key_path)
  warn "Missing App Store Connect private key: #{key_path}"
  warn "Install it with: Scripts/install_asc_api_key.sh #{key_id} #{issuer_id} /path/to/AuthKey_#{key_id}.p8"
  exit 1
end

token = jwt_for(key_id: key_id, issuer_id: issuer_id, key_path: key_path)
uri = URI("https://api.appstoreconnect.apple.com/v1/apps/#{app_id}")
request = Net::HTTP::Get.new(uri)
request["Authorization"] = "Bearer #{token}"

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(request)
end

body = JSON.parse(response.body)

if response.code.to_i == 200
  data = body.fetch("data")
  attrs = data.fetch("attributes")
  puts "ASC API key OK: #{attrs.fetch("name")} (#{data.fetch("id")}) bundle=#{attrs.fetch("bundleId")}"
else
  errors = body["errors"] || response.body
  warn "ASC API key check failed: HTTP #{response.code}"
  warn JSON.pretty_generate(errors)
  exit 1
end
