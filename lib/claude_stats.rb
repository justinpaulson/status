require 'json'
require 'timeout'
require 'net/http'
require 'uri'

module ClaudeStats
  @cache = nil
  @cache_at = Time.at(0)
  CACHE_TTL = 60 # 1 minute

  def self.collect
    return @cache if @cache && (Time.now - @cache_at) < CACHE_TTL
    @cache = fetch_usage
    @cache_at = Time.now
    @cache
  rescue => e
    $stderr.puts "#{Time.now} ClaudeStats error: #{e.class}: #{e.message}"
    { available: false }
  end

  private

  def self.fetch_usage
    token = read_oauth_token
    return { available: false } unless token

    uri = URI('https://api.anthropic.com/api/oauth/usage')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{token}"
    req['anthropic-beta'] = 'oauth-2025-04-20'
    req['Content-Type'] = 'application/json'

    resp = http.request(req)
    return { available: false } unless resp.is_a?(Net::HTTPSuccess)

    data = JSON.parse(resp.body)

    result = { available: true }

    if data['seven_day']
      result[:weekly] = {
        utilization: data['seven_day']['utilization'],
        resets_at: data['seven_day']['resets_at']
      }
    end

    if data['five_hour']
      result[:session] = {
        utilization: data['five_hour']['utilization'],
        resets_at: data['five_hour']['resets_at']
      }
    end

    if data['extra_usage']
      result[:extra] = {
        enabled: data['extra_usage']['is_enabled'],
        utilization: data['extra_usage']['utilization'],
        used: data['extra_usage']['used_credits'],
        limit: data['extra_usage']['monthly_limit']
      }
    end

    result
  end

  def self.read_oauth_token
    raw = Timeout.timeout(3) {
      `security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null`.strip
    }
    return nil if raw.empty?
    creds = JSON.parse(raw)
    creds.dig('claudeAiOauth', 'accessToken')
  rescue
    nil
  end
end
