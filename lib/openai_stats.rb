require 'json'
require 'net/http'
require 'open3'
require 'timeout'
require 'time'
require 'uri'
require_relative 'config'

module OpenAIStats
  CACHE_TTL = 300 # 5 minutes
  BACKOFF_TTL = 900 # 15 minutes on transient failure
  CACHE_FILE = File.join(__dir__, '..', '.openai_stats_cache.json')
  BASE_URL = 'https://api.openai.com'

  class ApiError < StandardError; end

  @cache = nil
  @cache_at = Time.at(0)
  @last_good = nil

  def self.collect
    return @cache if @cache && (Time.now - @cache_at) < CACHE_TTL

    @last_good ||= load_cached
    result = fetch_usage
    if result[:available]
      result[:fetched_at] = Time.now.utc.iso8601
      @last_good = result
      save_cached(result)
      @cache = result
      @cache_at = Time.now
    else
      @cache = @last_good || result
      @cache_at = Time.now - CACHE_TTL + BACKOFF_TTL
    end
    @cache
  rescue => e
    $stderr.puts "#{Time.now} OpenAIStats error: #{e.class}: #{e.message}"
    @last_good || { available: false }
  end

  def self.month_bounds(now = Time.now.utc)
    start_at = Time.utc(now.year, now.month, 1)
    next_month_year = now.month == 12 ? now.year + 1 : now.year
    next_month = now.month == 12 ? 1 : now.month + 1
    end_at = Time.utc(next_month_year, next_month, 1)
    [start_at, end_at]
  end

  def self.summarize_costs(data, now = Time.now.utc)
    total = 0.0
    today = 0.0
    currencies = []
    current_day = now.utc.to_date

    buckets(data).each do |bucket|
      bucket_start = bucket['start_time'] ? Time.at(bucket['start_time']).utc.to_date : nil
      bucket['results'].to_a.each do |result|
        amount = result.dig('amount', 'value').to_f
        currency = result.dig('amount', 'currency')
        total += amount
        today += amount if bucket_start == current_day
        currencies << currency if currency && amount != 0
      end
    end

    {
      total: total.round(4),
      today: today.round(4),
      currency: currencies.uniq.length > 1 ? 'mixed' : (currencies.first || 'usd')
    }
  end

  def self.summarize_completions(data)
    totals = {
      input_tokens: 0,
      output_tokens: 0,
      cached_input_tokens: 0,
      requests: 0
    }

    buckets(data).each do |bucket|
      bucket['results'].to_a.each do |result|
        totals[:input_tokens] += result['input_tokens'].to_i
        totals[:output_tokens] += result['output_tokens'].to_i
        totals[:cached_input_tokens] += result['input_cached_tokens'].to_i
        totals[:requests] += result['num_model_requests'].to_i
      end
    end

    totals[:total_tokens] = totals[:input_tokens] + totals[:output_tokens]
    totals
  end

  private

  def self.load_cached
    return nil unless File.exist?(CACHE_FILE)

    data = JSON.parse(File.read(CACHE_FILE), symbolize_names: true)
    data[:available] ? data : nil
  rescue
    nil
  end

  def self.save_cached(result)
    File.write(CACHE_FILE, JSON.generate(result))
  rescue
    nil
  end

  def self.fetch_usage
    admin_key = read_admin_key
    return { available: false, reason: 'missing_admin_key' } unless admin_key

    now = Time.now.utc
    start_at, reset_at = month_bounds(now)
    common_params = {
      start_time: start_at.to_i,
      end_time: now.to_i,
      bucket_width: '1d',
      limit: 31
    }

    costs = get_json('/v1/organization/costs', common_params, admin_key)
    completions = get_json('/v1/organization/usage/completions', common_params, admin_key)

    cost_summary = summarize_costs(costs, now)
    completion_summary = summarize_completions(completions)
    budget = Config.openai_usage[:monthly_budget_usd]
    days_in_month = (reset_at.to_date - start_at.to_date).to_i
    daily_budget = budget ? budget / days_in_month : nil

    {
      available: true,
      period: {
        starts_at: start_at.iso8601,
        resets_at: reset_at.iso8601,
        days: days_in_month
      },
      monthly: {
        cost: cost_summary[:total],
        currency: cost_summary[:currency],
        budget: budget,
        utilization: utilization(cost_summary[:total], budget),
        resets_at: reset_at.iso8601
      },
      daily: {
        cost: cost_summary[:today],
        currency: cost_summary[:currency],
        budget: daily_budget,
        utilization: utilization(cost_summary[:today], daily_budget),
        resets_at: (Time.utc(now.year, now.month, now.day) + 86_400).iso8601
      },
      completions: completion_summary
    }
  rescue ApiError => e
    $stderr.puts "#{Time.now} OpenAIStats API error: #{e.message}"
    { available: false, reason: 'api_error' }
  end

  def self.utilization(used, limit)
    return nil unless limit&.positive?

    ((used.to_f / limit) * 100).round(1)
  end

  def self.get_json(path, params, admin_key)
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params.compact)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{admin_key}"
    req['Content-Type'] = 'application/json'

    resp = http.request(req)
    unless resp.is_a?(Net::HTTPSuccess)
      raise ApiError, "#{path} #{resp.code}: #{resp.body[0..200]}"
    end

    JSON.parse(resp.body)
  end

  def self.buckets(data)
    data.fetch('data', [])
  end

  def self.read_admin_key
    cfg = Config.openai_usage
    env_name = cfg[:admin_key_env]
    env_value = ENV[env_name].to_s.strip
    return env_value unless env_value.empty?

    service = cfg[:keychain_service].to_s.strip
    return nil if service.empty?

    args = ['security', 'find-generic-password', '-s', service, '-w']
    account = cfg[:keychain_account].to_s.strip
    args.insert(4, '-a', account) unless account.empty?

    output, status = Timeout.timeout(3) { Open3.capture2e(*args) }
    return nil unless status.success?

    value = output.strip
    value.empty? ? nil : value
  rescue
    nil
  end
end
