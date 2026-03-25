require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative '../lib/config'
require_relative '../lib/auth'

class AuthTest < Minitest::Test
  def setup
    Config.reset!
    Auth.reset_sessions!
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    Config.reset!
    Auth.reset_sessions!
    FileUtils.remove_entry(@tmpdir)
  end

  def write_config(hash)
    path = File.join(@tmpdir, 'config.yml')
    File.write(path, YAML.dump(hash))
    Config.load(path)
  end

  # --- Session management tests ---

  def test_create_session_returns_token
    token = Auth.create_session('test@example.com')
    assert_kind_of String, token
    assert_equal 64, token.length # SecureRandom.hex(32) = 64 hex chars
  end

  def test_valid_session
    token = Auth.create_session('test@example.com')
    assert Auth.valid_session?(token)
  end

  def test_invalid_session_nil_token
    refute Auth.valid_session?(nil)
  end

  def test_invalid_session_bad_token
    refute Auth.valid_session?('nonexistent_token')
  end

  def test_session_email
    token = Auth.create_session('test@example.com')
    assert_equal 'test@example.com', Auth.session_email(token)
  end

  def test_session_email_nil_for_invalid
    assert_nil Auth.session_email('bad_token')
  end

  def test_destroy_session
    token = Auth.create_session('test@example.com')
    Auth.destroy_session(token)
    refute Auth.valid_session?(token)
  end

  def test_reset_sessions
    token = Auth.create_session('test@example.com')
    Auth.reset_sessions!
    refute Auth.valid_session?(token)
  end

  # --- Cookie parsing tests ---

  def test_parse_session_cookie
    cookie = 'status_session=abc123; other=value'
    assert_equal 'abc123', Auth.parse_session_cookie(cookie)
  end

  def test_parse_session_cookie_only_session
    cookie = 'status_session=abc123'
    assert_equal 'abc123', Auth.parse_session_cookie(cookie)
  end

  def test_parse_session_cookie_no_session
    cookie = 'other=value; another=thing'
    assert_nil Auth.parse_session_cookie(cookie)
  end

  def test_parse_session_cookie_nil
    assert_nil Auth.parse_session_cookie(nil)
  end

  # --- Email allowlist tests ---

  def test_allowed_email_matching
    write_config({ 'auth' => { 'allowed_email' => 'user@example.com' } })
    assert Auth.allowed?('user@example.com')
  end

  def test_allowed_email_case_insensitive
    write_config({ 'auth' => { 'allowed_email' => 'User@Example.com' } })
    assert Auth.allowed?('user@example.com')
  end

  def test_not_allowed_email
    write_config({ 'auth' => { 'allowed_email' => 'user@example.com' } })
    refute Auth.allowed?('other@example.com')
  end

  def test_allowed_nil_email
    write_config({ 'auth' => { 'allowed_email' => 'user@example.com' } })
    refute Auth.allowed?(nil)
  end

  def test_allowed_no_config
    write_config({})
    refute Auth.allowed?('user@example.com')
  end

  # --- Auth configured tests ---

  def test_auth_configured_with_valid_client_id
    write_config({ 'auth' => { 'google_client_id' => '123456.apps.googleusercontent.com' } })
    assert Auth.auth_configured?
  end

  def test_auth_not_configured_placeholder
    write_config({ 'auth' => { 'google_client_id' => 'YOUR_CLIENT_ID.apps.googleusercontent.com' } })
    refute Auth.auth_configured?
  end

  def test_auth_not_configured_empty
    write_config({ 'auth' => { 'google_client_id' => '' } })
    refute Auth.auth_configured?
  end

  def test_auth_not_configured_missing
    write_config({})
    refute Auth.auth_configured?
  end

  # --- Authenticated email (integration of cookie + session) ---

  def test_authenticated_email_valid
    token = Auth.create_session('test@example.com')
    cookie = "status_session=#{token}; other=value"
    assert_equal 'test@example.com', Auth.authenticated_email(cookie)
  end

  def test_authenticated_email_invalid_cookie
    cookie = 'status_session=badtoken'
    assert_nil Auth.authenticated_email(cookie)
  end

  def test_authenticated_email_no_cookie
    assert_nil Auth.authenticated_email(nil)
  end

  # --- JWT verification tests (malformed tokens) ---

  def test_verify_google_token_nil
    assert_nil Auth.verify_google_token('', 'client_id')
  end

  def test_verify_google_token_bad_format
    assert_nil Auth.verify_google_token('not.a.valid.jwt', 'client_id')
  end

  def test_verify_google_token_missing_parts
    assert_nil Auth.verify_google_token('only_one_part', 'client_id')
  end
end
