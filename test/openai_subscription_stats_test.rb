require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/openai_subscription_stats'

class OpenAISubscriptionStatsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @db_path = File.join(@tmpdir, 'state.sqlite')
    create_db
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_collect_from_db_aggregates_codex_thread_usage
    now = Time.local(2026, 6, 10, 12, 0, 0)
    insert_thread('openai', 'gpt-5.5', 100, now - 3600)
    insert_thread('openai', 'gpt-5.5', 200, now - (2 * 86_400))
    insert_thread('openai', 'gpt-5.4', 300, now - (20 * 86_400))
    insert_thread('anthropic', 'claude', 999, now - 3600)

    result = OpenAISubscriptionStats.collect_from_db(@db_path, now)
    assert result[:available]
    assert_equal 100, result[:windows][:three_hour][:tokens]
    assert_equal 300, result[:windows][:seven_day][:tokens]
    assert_equal 600, result[:windows][:thirty_day][:tokens]
    assert_equal 600, result[:windows][:lifetime][:tokens]
    assert_equal 2, result[:models].length
  end

  def test_collect_from_db_reports_missing_state
    result = OpenAISubscriptionStats.collect_from_db(File.join(@tmpdir, 'missing.sqlite'))
    refute result[:available]
    assert_equal 'missing_codex_state', result[:reason]
  end

  private

  def create_db
    system('sqlite3', @db_path, <<~SQL)
      CREATE TABLE threads (
        model_provider TEXT,
        model TEXT,
        tokens_used INTEGER,
        updated_at_ms INTEGER,
        updated_at INTEGER,
        created_at_ms INTEGER,
        created_at INTEGER
      );
    SQL
  end

  def insert_thread(provider, model, tokens, updated_at)
    ms = (updated_at.to_f * 1000).to_i
    system(
      'sqlite3',
      @db_path,
      "INSERT INTO threads VALUES ('#{provider}', '#{model}', #{tokens}, #{ms}, NULL, #{ms}, NULL);"
    )
  end
end
