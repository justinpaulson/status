require_relative 'config'
require_relative 'log_reader'

module ServiceChecker
  def self.log_path_for(service_id)
    Config.services.each_value do |group|
      group[:services].each do |svc|
        return svc[:log] if svc[:id] == service_id && svc[:log]
      end
    end
    nil
  end

  def self.check_all
    raw = `launchctl list 2>/dev/null`
    launchd_state = parse_launchctl(raw)

    ps_output = `ps -eo args 2>/dev/null`

    Config.services.transform_values do |group|
      {
        label: group[:label],
        services: group[:services].map { |svc| check_one(svc, launchd_state, ps_output) }
      }
    end
  end

  def self.parse_launchctl(raw)
    result = {}
    raw.each_line do |line|
      next if line.start_with?('PID')
      parts = line.strip.split(/\t/)
      next unless parts.length == 3
      pid_str, status_str, label = parts
      result[label] = {
        pid: pid_str == '-' ? nil : pid_str.to_i,
        exit_status: status_str.to_i
      }
    end
    result
  end

  def self.check_one(svc, launchd_state, ps_output)
    entry = launchd_state[svc[:id]]
    result = {
      id: svc[:id],
      name: svc[:name],
      type: svc[:type].to_s,
    }
    result[:schedule] = svc[:schedule] if svc[:schedule]

    if svc[:type] == :process
      check_process(svc, result, ps_output)
    elsif entry.nil?
      result[:state] = "unloaded"
      result[:status] = "error"
    elsif svc[:type] == :daemon
      if entry[:pid]
        result[:state] = "running"
        result[:pid] = entry[:pid]
        result[:status] = "ok"
      else
        result[:state] = "stopped"
        result[:status] = "error"
      end
    elsif svc[:type] == :runner
      if entry[:pid]
        result[:state] = "running"
        result[:pid] = entry[:pid]
        result[:status] = "ok"
      else
        result[:state] = "stopped"
        result[:status] = "error"
      end
      if result[:status] == "ok"
        runner_name = svc[:name]
        listener_running = ps_output.lines.any? { |l|
          l.include?("Runner.Listener") && l.include?(runner_name) && !l.include?("grep")
        }
        unless listener_running
          result[:status] = "warning"
          result[:listener_missing] = true
        end
      end
    elsif svc[:type] == :scheduled
      if entry[:pid]
        result[:state] = "running"
        result[:pid] = entry[:pid]
      else
        result[:state] = "idle"
      end
      result[:status] = entry[:exit_status] == 0 ? "ok" : "warning"
    else
      result[:state] = "unknown"
      result[:status] = "warning"
    end

    if svc[:log]
      result[:has_log] = File.exist?(svc[:log])
      result[:log_modified] = LogReader.last_modified(svc[:log])&.iso8601
      if result[:status] != "ok"
        result[:recent_log] = LogReader.tail_errors(svc[:log], 5)
      end
    end

    result
  end

  def self.check_process(svc, result, ps_output)
    process_name = svc[:process] || svc[:name]
    running = ps_output.lines.any? { |l|
      l.include?(process_name) && !l.include?("grep")
    }
    if running
      result[:state] = "running"
      result[:status] = "ok"
    else
      result[:state] = "stopped"
      result[:status] = "error"
    end
  end
end
