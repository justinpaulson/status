require 'minitest/autorun'
require 'time'
require_relative '../lib/openai_stats'

class OpenAIStatsTest < Minitest::Test
  def test_month_bounds
    start_at, reset_at = OpenAIStats.month_bounds(Time.utc(2026, 6, 10, 12, 0, 0))
    assert_equal Time.utc(2026, 6, 1), start_at
    assert_equal Time.utc(2026, 7, 1), reset_at
  end

  def test_month_bounds_handles_december
    start_at, reset_at = OpenAIStats.month_bounds(Time.utc(2026, 12, 10, 12, 0, 0))
    assert_equal Time.utc(2026, 12, 1), start_at
    assert_equal Time.utc(2027, 1, 1), reset_at
  end

  def test_summarize_costs
    now = Time.utc(2026, 6, 10, 12, 0, 0)
    data = {
      'data' => [
        {
          'start_time' => Time.utc(2026, 6, 9).to_i,
          'results' => [
            { 'amount' => { 'value' => 1.25, 'currency' => 'usd' } }
          ]
        },
        {
          'start_time' => Time.utc(2026, 6, 10).to_i,
          'results' => [
            { 'amount' => { 'value' => 0.50, 'currency' => 'usd' } },
            { 'amount' => { 'value' => 0.25, 'currency' => 'usd' } }
          ]
        }
      ]
    }

    summary = OpenAIStats.summarize_costs(data, now)
    assert_in_delta 2.0, summary[:total], 0.001
    assert_in_delta 0.75, summary[:today], 0.001
    assert_equal 'usd', summary[:currency]
  end

  def test_summarize_completions
    data = {
      'data' => [
        {
          'results' => [
            {
              'input_tokens' => 100,
              'output_tokens' => 30,
              'input_cached_tokens' => 40,
              'num_model_requests' => 2
            },
            {
              'input_tokens' => 50,
              'output_tokens' => 20,
              'input_cached_tokens' => 0,
              'num_model_requests' => 1
            }
          ]
        }
      ]
    }

    summary = OpenAIStats.summarize_completions(data)
    assert_equal 150, summary[:input_tokens]
    assert_equal 50, summary[:output_tokens]
    assert_equal 40, summary[:cached_input_tokens]
    assert_equal 3, summary[:requests]
    assert_equal 200, summary[:total_tokens]
  end
end
