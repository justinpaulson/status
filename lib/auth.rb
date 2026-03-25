require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'
require 'securerandom'
require_relative 'config'

module Auth
  GOOGLE_JWKS_URI = 'https://www.googleapis.com/oauth2/v3/certs'
  GOOGLE_ISSUERS  = ['https://accounts.google.com', 'accounts.google.com'].freeze
  SESSION_TTL     = 86400 # 24 hours

  @jwks_cache = nil
  @jwks_cache_at = Time.at(0)
  @jwks_cache_ttl = 3600 # 1 hour default, updated from Cache-Control header
  @sessions = {}

  class << self
    def verify_google_token(id_token, client_id)
      parts = id_token.split('.')
      return nil unless parts.length == 3

      header = json_decode(parts[0])
      return nil unless header && header['kid']

      key = find_key(header['kid'])
      return nil unless key

      # Verify signature
      signing_input = "#{parts[0]}.#{parts[1]}"
      signature = base64url_decode(parts[2])
      return nil unless key.verify(OpenSSL::Digest::SHA256.new, signature, signing_input)

      # Decode and validate claims
      payload = json_decode(parts[1])
      return nil unless payload

      # Check issuer
      return nil unless GOOGLE_ISSUERS.include?(payload['iss'])

      # Check audience
      return nil unless payload['aud'] == client_id

      # Check expiry
      return nil unless payload['exp'] && payload['exp'].to_i > Time.now.to_i

      # Check email verified
      return nil unless payload['email_verified'] == true || payload['email_verified'] == 'true'

      { email: payload['email'] }
    rescue => e
      $stderr.puts "#{Time.now} AUTH: JWT verification failed: #{e.message}"
      nil
    end

    def create_session(email)
      token = SecureRandom.hex(32)
      @sessions[token] = { email: email, expires_at: Time.now + SESSION_TTL }
      token
    end

    def valid_session?(token)
      return false unless token
      session = @sessions[token]
      return false unless session
      if session[:expires_at] < Time.now
        @sessions.delete(token)
        return false
      end
      true
    end

    def session_email(token)
      return nil unless valid_session?(token)
      @sessions[token][:email]
    end

    def destroy_session(token)
      @sessions.delete(token)
    end

    def authenticated_email(cookie_header)
      token = parse_session_cookie(cookie_header)
      session_email(token)
    end

    def allowed?(email)
      return false unless email
      allowed = Config.auth[:allowed_email]
      return false unless allowed
      email.downcase == allowed.downcase
    end

    def auth_configured?
      client_id = Config.auth[:google_client_id]
      client_id && !client_id.empty? && client_id != "YOUR_CLIENT_ID.apps.googleusercontent.com"
    end

    def parse_session_cookie(cookie_header)
      return nil unless cookie_header
      cookie_header.split(';').each do |pair|
        key, value = pair.strip.split('=', 2)
        return value if key == 'status_session'
      end
      nil
    end

    def reset_sessions!
      @sessions = {}
    end

    private

    def find_key(kid)
      keys = fetch_jwks
      rsa_key = build_rsa_key(keys, kid)
      unless rsa_key
        # Key not found, try refreshing JWKS (key rotation)
        keys = fetch_jwks(force: true)
        rsa_key = build_rsa_key(keys, kid)
      end
      rsa_key
    end

    def build_rsa_key(keys, kid)
      key_data = keys.find { |k| k['kid'] == kid && k['kty'] == 'RSA' }
      return nil unless key_data

      n = OpenSSL::BN.new(base64url_decode(key_data['n']), 2)
      e = OpenSSL::BN.new(base64url_decode(key_data['e']), 2)

      data_sequence = OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Integer(n),
        OpenSSL::ASN1::Integer(e)
      ])
      asn1 = OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::ObjectId('rsaEncryption'),
          OpenSSL::ASN1::Null.new(nil)
        ]),
        OpenSSL::ASN1::BitString(data_sequence.to_der)
      ])
      OpenSSL::PKey::RSA.new(asn1.to_der)
    end

    def fetch_jwks(force: false)
      if !force && @jwks_cache && (Time.now - @jwks_cache_at) < @jwks_cache_ttl
        return @jwks_cache
      end

      uri = URI(GOOGLE_JWKS_URI)
      response = Net::HTTP.get_response(uri)

      if cc = response['Cache-Control']
        if cc =~ /max-age=(\d+)/
          @jwks_cache_ttl = $1.to_i
        end
      end

      data = JSON.parse(response.body)
      @jwks_cache = data['keys'] || []
      @jwks_cache_at = Time.now
      @jwks_cache
    rescue => e
      $stderr.puts "#{Time.now} AUTH: Failed to fetch JWKS: #{e.message}"
      @jwks_cache || []
    end

    def json_decode(base64url_str)
      JSON.parse(base64url_decode(base64url_str))
    rescue
      nil
    end

    def base64url_decode(str)
      str = str.tr('-_', '+/')
      # Add padding
      str += '=' * (4 - str.length % 4) if str.length % 4 != 0
      Base64.decode64(str)
    end
  end
end
