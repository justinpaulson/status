require 'yaml'

module Config
  class ConfigError < StandardError; end

  @data = nil

  def self.load(path = nil)
    path ||= find_config_path
    raw = File.read(path)
    @data = YAML.safe_load(raw, symbolize_names: true)
    validate!
    @data
  rescue Psych::SyntaxError => e
    raise ConfigError, "YAML syntax error in #{path} at line #{e.line}: #{e.message}"
  end

  def self.reset!
    @data = nil
  end

  def self.dashboard
    ensure_loaded
    cfg = @data[:dashboard] || {}
    {
      title: cfg[:title] || "Status Dashboard",
      subtitle: cfg[:subtitle],
      port: cfg[:port] || 9999
    }
  end

  def self.features
    ensure_loaded
    @data[:features] || {}
  end

  def self.feature?(name)
    ensure_loaded
    features[name.to_sym] == true
  end

  def self.services
    ensure_loaded
    result = {}
    (@data[:services] || {}).each do |group_key, group|
      result[group_key] = {
        label: group[:label] || group_key.to_s.capitalize,
        services: (group[:services] || []).map { |svc| normalize_service(svc) }
      }
    end
    result
  end

  private

  def self.find_config_path
    root = File.expand_path('..', __dir__)
    config_path = File.join(root, 'config.yml')
    return config_path if File.exist?(config_path)

    example_path = File.join(root, 'config.example.yml')
    return example_path if File.exist?(example_path)

    raise ConfigError, "No config.yml or config.example.yml found in #{root}"
  end

  def self.ensure_loaded
    load unless @data
  end

  def self.validate!
    raise ConfigError, "Config file is empty" unless @data.is_a?(Hash)

    (@data[:services] || {}).each do |group_key, group|
      unless group.is_a?(Hash)
        raise ConfigError, "Service group '#{group_key}' must be a mapping"
      end
      (group[:services] || []).each_with_index do |svc, i|
        %i[id name type].each do |field|
          unless svc[field]
            raise ConfigError, "Service ##{i + 1} in group '#{group_key}' is missing required field '#{field}'"
          end
        end
      end
    end
  end

  def self.normalize_service(svc)
    home = ENV['HOME'] || Dir.home
    result = {
      id: svc[:id],
      name: svc[:name],
      type: svc[:type].to_sym
    }
    result[:schedule] = svc[:schedule] if svc[:schedule]
    if svc[:log]
      log_path = svc[:log].to_s
      log_path = log_path.sub(/\A~/, home)
      log_path = log_path.gsub('$HOME', home)
      result[:log] = log_path
    end
    if svc[:process]
      result[:process] = svc[:process]
    end
    result
  end
end
