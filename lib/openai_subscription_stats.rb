require 'open3'
require 'time'
require_relative 'config'

module OpenAISubscriptionStats
  CACHE_TTL = 60

  PLAN_LIMITS = {
    free: 'Limited messages, uploads, images, deep research, memory/context, and Codex',
    go: 'More messages, uploads, image creation, memory; limited Codex',
    plus: 'Expanded GPT-5.5 Instant/Thinking, messages, uploads, deep research, agent mode, and Codex',
    pro_100: 'Pro $100: 5x more usage than Plus; GPT-5.5 Pro and expanded Codex',
    pro_200: 'Pro $200: 20x more usage than Plus; GPT-5.5 Pro and maximum Codex tasks',
    business: 'Unlimited core chat, Codex included, and workspace controls',
    enterprise: 'Unlimited core chat, flexible model access, and enterprise controls'
  }.freeze

  @cache = nil
  @cache_at = Time.at(0)

  def self.collect
    return @cache if @cache && (Time.now - @cache_at) < CACHE_TTL

    cfg = Config.openai_subscription
    db_path = expand_path(cfg[:codex_state_db])
    result = collect_from_db(db_path, Time.now)
    plan = cfg[:plan]&.to_sym
    result[:plan] = {
      name: plan ? plan.to_s.tr('_', ' ').split.map(&:capitalize).join(' ') : nil,
      key: plan,
      limit_summary: plan ? PLAN_LIMITS[plan] : nil
    }
    @cache = result.merge(fetched_at: Time.now.utc.iso8601)
    @cache_at = Time.now
    @cache
  rescue => e
    $stderr.puts "#{Time.now} OpenAISubscriptionStats error: #{e.class}: #{e.message}"
    { available: false, reason: 'collector_error' }
  end

  def self.collect_from_db(db_path, now = Time.now)
    return { available: false, reason: 'missing_codex_state' } unless db_path && File.exist?(db_path)

    cutoffs = {
      three_hour: now - (3 * 3600),
      today: Time.local(now.year, now.month, now.day),
      seven_day: now - (7 * 86_400),
      thirty_day: now - (30 * 86_400),
      lifetime: nil
    }

    windows = {}
    cutoffs.each do |key, cutoff|
      windows[key] = aggregate_window(db_path, cutoff)
    end

    {
      available: true,
      source: 'local_codex_state',
      windows: windows,
      models: aggregate_models(db_path),
      note: 'Local Codex thread totals only; not account-wide remaining subscription quota.'
    }
  end

  def self.aggregate_window(db_path, cutoff)
    where = "model_provider = 'openai'"
    where += " AND #{updated_expr} >= #{(cutoff.to_f * 1000).to_i}" if cutoff
    sql = <<~SQL
      SELECT
        COUNT(*),
        COALESCE(SUM(tokens_used), 0),
        COALESCE(MAX(#{updated_expr}), 0)
      FROM threads
      WHERE #{where};
    SQL

    row = sqlite_rows(db_path, sql).first || []
    {
      threads: row[0].to_i,
      tokens: row[1].to_i,
      updated_at: ms_to_iso(row[2].to_i)
    }
  end

  def self.aggregate_models(db_path)
    sql = <<~SQL
      SELECT
        COALESCE(model, ''),
        COUNT(*),
        COALESCE(SUM(tokens_used), 0)
      FROM threads
      WHERE model_provider = 'openai'
      GROUP BY COALESCE(model, '')
      ORDER BY COALESCE(SUM(tokens_used), 0) DESC
      LIMIT 5;
    SQL

    sqlite_rows(db_path, sql).map do |row|
      { model: row[0], threads: row[1].to_i, tokens: row[2].to_i }
    end
  end

  def self.updated_expr
    'COALESCE(updated_at_ms, updated_at * 1000, created_at_ms, created_at * 1000, 0)'
  end

  def self.sqlite_rows(db_path, sql)
    output, err, status = Open3.capture3('sqlite3', '-separator', "\t", db_path, sql)
    raise "sqlite3 failed: #{err.strip}" unless status.success?

    output.each_line.map { |line| line.chomp.split("\t", -1) }
  end

  def self.ms_to_iso(ms)
    return nil unless ms.positive?

    Time.at(ms / 1000.0).utc.iso8601
  end

  def self.expand_path(path)
    return nil unless path

    File.expand_path(path.to_s.sub(/\A~/, Dir.home))
  end
end
