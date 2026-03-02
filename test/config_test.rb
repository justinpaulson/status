require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative '../lib/config'

class ConfigTest < Minitest::Test
  def setup
    Config.reset!
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    Config.reset!
    FileUtils.remove_entry(@tmpdir)
  end

  def write_config(hash)
    path = File.join(@tmpdir, 'config.yml')
    File.write(path, YAML.dump(hash))
    path
  end

  def test_dashboard_defaults
    path = write_config({})
    Config.load(path)
    assert_equal "Status Dashboard", Config.dashboard[:title]
    assert_nil Config.dashboard[:subtitle]
    assert_equal 9999, Config.dashboard[:port]
  end

  def test_dashboard_custom_values
    path = write_config({
      'dashboard' => { 'title' => 'My Server', 'subtitle' => 'prod', 'port' => 8080 }
    })
    Config.load(path)
    assert_equal "My Server", Config.dashboard[:title]
    assert_equal "prod", Config.dashboard[:subtitle]
    assert_equal 8080, Config.dashboard[:port]
  end

  def test_feature_flags
    path = write_config({
      'features' => { 'docker' => true, 'claude_code' => false }
    })
    Config.load(path)
    assert Config.feature?(:docker)
    refute Config.feature?(:claude_code)
    refute Config.feature?(:nonexistent)
  end

  def test_feature_string_name
    path = write_config({
      'features' => { 'docker' => true }
    })
    Config.load(path)
    assert Config.feature?('docker')
  end

  def test_services_parsing
    path = write_config({
      'services' => {
        'web' => {
          'label' => 'Web Services',
          'services' => [
            { 'id' => 'com.example.web', 'name' => 'Web Server', 'type' => 'daemon', 'log' => '/var/log/web.log' }
          ]
        }
      }
    })
    Config.load(path)
    services = Config.services
    assert_equal 1, services.keys.length
    assert_equal "Web Services", services[:web][:label]
    assert_equal 1, services[:web][:services].length

    svc = services[:web][:services][0]
    assert_equal "com.example.web", svc[:id]
    assert_equal "Web Server", svc[:name]
    assert_equal :daemon, svc[:type]
    assert_equal "/var/log/web.log", svc[:log]
  end

  def test_tilde_expansion_in_log_paths
    path = write_config({
      'services' => {
        'test' => {
          'label' => 'Test',
          'services' => [
            { 'id' => 'test.svc', 'name' => 'Test', 'type' => 'daemon', 'log' => '~/logs/test.log' }
          ]
        }
      }
    })
    Config.load(path)
    svc = Config.services[:test][:services][0]
    expected = File.join(ENV['HOME'], 'logs/test.log')
    assert_equal expected, svc[:log]
  end

  def test_home_var_expansion_in_log_paths
    path = write_config({
      'services' => {
        'test' => {
          'label' => 'Test',
          'services' => [
            { 'id' => 'test.svc', 'name' => 'Test', 'type' => 'daemon', 'log' => '$HOME/logs/test.log' }
          ]
        }
      }
    })
    Config.load(path)
    svc = Config.services[:test][:services][0]
    expected = File.join(ENV['HOME'], 'logs/test.log')
    assert_equal expected, svc[:log]
  end

  def test_scheduled_service_with_schedule
    path = write_config({
      'services' => {
        'crons' => {
          'label' => 'Crons',
          'services' => [
            { 'id' => 'cron.job', 'name' => 'My Cron', 'type' => 'scheduled', 'schedule' => 'Every 5 min' }
          ]
        }
      }
    })
    Config.load(path)
    svc = Config.services[:crons][:services][0]
    assert_equal :scheduled, svc[:type]
    assert_equal "Every 5 min", svc[:schedule]
  end

  def test_process_type_with_process_name
    path = write_config({
      'services' => {
        'bg' => {
          'label' => 'Background',
          'services' => [
            { 'id' => 'worker', 'name' => 'Worker', 'type' => 'process', 'process' => 'my-worker' }
          ]
        }
      }
    })
    Config.load(path)
    svc = Config.services[:bg][:services][0]
    assert_equal :process, svc[:type]
    assert_equal "my-worker", svc[:process]
  end

  def test_validation_missing_id
    path = write_config({
      'services' => {
        'test' => {
          'label' => 'Test',
          'services' => [
            { 'name' => 'Test', 'type' => 'daemon' }
          ]
        }
      }
    })
    err = assert_raises(Config::ConfigError) { Config.load(path) }
    assert_match(/missing required field 'id'/, err.message)
  end

  def test_validation_missing_name
    path = write_config({
      'services' => {
        'test' => {
          'label' => 'Test',
          'services' => [
            { 'id' => 'test', 'type' => 'daemon' }
          ]
        }
      }
    })
    err = assert_raises(Config::ConfigError) { Config.load(path) }
    assert_match(/missing required field 'name'/, err.message)
  end

  def test_validation_missing_type
    path = write_config({
      'services' => {
        'test' => {
          'label' => 'Test',
          'services' => [
            { 'id' => 'test', 'name' => 'Test' }
          ]
        }
      }
    })
    err = assert_raises(Config::ConfigError) { Config.load(path) }
    assert_match(/missing required field 'type'/, err.message)
  end

  def test_empty_services_is_ok
    path = write_config({ 'services' => {} })
    Config.load(path)
    assert_equal({}, Config.services)
  end

  def test_no_services_key_is_ok
    path = write_config({})
    Config.load(path)
    assert_equal({}, Config.services)
  end

  def test_label_defaults_to_group_key
    path = write_config({
      'services' => {
        'my_group' => {
          'services' => [
            { 'id' => 'svc', 'name' => 'Svc', 'type' => 'daemon' }
          ]
        }
      }
    })
    Config.load(path)
    assert_equal "My_group", Config.services[:my_group][:label]
  end

  def test_invalid_yaml_raises_config_error
    path = File.join(@tmpdir, 'config.yml')
    File.write(path, "invalid: yaml: [unterminated")
    assert_raises(Config::ConfigError) { Config.load(path) }
  end

  def test_fallback_to_example_config
    # Config.find_config_path looks relative to lib/config.rb's parent dir,
    # so we test directly with load(path)
    example_path = write_config({
      'dashboard' => { 'title' => 'Example Dashboard' }
    })
    Config.load(example_path)
    assert_equal "Example Dashboard", Config.dashboard[:title]
  end

  def test_multiple_groups
    path = write_config({
      'services' => {
        'group_a' => {
          'label' => 'Group A',
          'services' => [
            { 'id' => 'a1', 'name' => 'A1', 'type' => 'daemon' }
          ]
        },
        'group_b' => {
          'label' => 'Group B',
          'services' => [
            { 'id' => 'b1', 'name' => 'B1', 'type' => 'runner' },
            { 'id' => 'b2', 'name' => 'B2', 'type' => 'scheduled', 'schedule' => 'Daily' }
          ]
        }
      }
    })
    Config.load(path)
    services = Config.services
    assert_equal 2, services.keys.length
    assert_equal 1, services[:group_a][:services].length
    assert_equal 2, services[:group_b][:services].length
  end
end
