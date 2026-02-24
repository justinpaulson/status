require_relative 'log_reader'

module ServiceChecker
  HOME = ENV['HOME'] || '/Users/justinpaulson'

  SERVICES = {
    orchestrators: {
      label: "Orchestrators",
      services: [
        { id: "com.tend.orchestrator", name: "Tend Orchestrator", type: :daemon,
          log: "#{HOME}/Developer/tend/log/orchestrator.log" },
        { id: "com.ultrathink.orchestrator", name: "Ultrathink Orchestrator", type: :daemon,
          log: "#{HOME}/Developer/ultrathink/log/orchestrator.log" },
      ]
    },
    runners: {
      label: "GitHub Actions Runners",
      services: [
        { id: "actions.runner.justinpaulson-tend.mac-mini-runner-tend",
          name: "tend", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-tend.mac-mini-runner-tend/stdout.log" },
        { id: "actions.runner.justinpaulson-ultrathink.mac-mini-runner",
          name: "ultrathink", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-ultrathink.mac-mini-runner/stdout.log" },
        { id: "actions.runner.justinpaulson-golf.mac-mini-runner-golf",
          name: "golf", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-golf.mac-mini-runner-golf/stdout.log" },
        { id: "actions.runner.justinpaulson-golf-ios.mac-mini-runner-golf-ios",
          name: "golf-ios", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-golf-ios.mac-mini-runner-golf-ios/stdout.log" },
        { id: "actions.runner.justinpaulson-scriptum.mac-mini-runner-scriptum",
          name: "scriptum", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-scriptum.mac-mini-runner-scriptum/stdout.log" },
        { id: "actions.runner.justinpaulson-justinpaulson.mac-mini-runner-justinpaulson",
          name: "justinpaulson", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-justinpaulson.mac-mini-runner-justinpaulson/stdout.log" },
        { id: "actions.runner.justinpaulson-cerastout.mac-mini-runner-cerastout",
          name: "cerastout", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-cerastout.mac-mini-runner-cerastout/stdout.log" },
        { id: "actions.runner.justinpaulson-corre.mac-mini-runner-corre",
          name: "corre", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-corre.mac-mini-runner-corre/stdout.log" },
        { id: "actions.runner.justinpaulson-totle.mac-mini-runner-totle",
          name: "totle", type: :runner,
          log: "#{HOME}/Library/Logs/actions.runner.justinpaulson-totle.mac-mini-runner-totle/stdout.log" },
      ]
    },
    ultrathink: {
      label: "Ultrathink Services",
      services: [
        { id: "com.ultrathink.ceo-client", name: "CEO Client", type: :daemon,
          log: "#{HOME}/Developer/ultrathink/log/ceo-client.log" },
        { id: "com.ultrathink.ceo-strategy", name: "CEO Strategy Review", type: :scheduled,
          schedule: "Daily 9:00 AM",
          log: "#{HOME}/Developer/ultrathink/log/ceo-strategy.log" },
        { id: "com.ultrathink.daily-marketing", name: "Daily Marketing", type: :scheduled,
          schedule: "Daily 10:00 AM",
          log: "#{HOME}/Developer/ultrathink/log/daily-marketing.log" },
        { id: "com.ultrathink.daily-ops-audit", name: "Daily Ops Audit", type: :scheduled,
          schedule: "Every 24h",
          log: "#{HOME}/Developer/ultrathink/agents/state/health_logs/ops_audit.log" },
        { id: "com.ultrathink.daily-security", name: "Daily Security", type: :scheduled,
          schedule: "Daily 8:00 AM",
          log: "#{HOME}/Developer/ultrathink/log/daily-security.log" },
        { id: "com.ultrathink.health-monitor", name: "Health Monitor", type: :scheduled,
          schedule: "Every 5 min",
          log: "#{HOME}/Developer/ultrathink/agents/state/health_logs/health-monitor.log" },
        { id: "com.ultrathink.meeting-allhands", name: "Meeting: All Hands", type: :scheduled,
          schedule: "Every 2 days",
          log: "#{HOME}/Developer/ultrathink/log/meeting-allhands.log" },
        { id: "com.ultrathink.meeting-trendsync", name: "Meeting: Trend Sync", type: :scheduled,
          schedule: "Every 3 days",
          log: "#{HOME}/Developer/ultrathink/log/meeting-trendsync.log" },
        { id: "com.ultrathink.queue-health", name: "Queue Health", type: :scheduled,
          schedule: "Every 1h",
          log: "#{HOME}/Developer/ultrathink/agents/state/health_logs/launchd.log" },
        { id: "com.ultrathink.reddit-sync", name: "Reddit Sync", type: :scheduled,
          schedule: "Daily 6:00 AM",
          log: "#{HOME}/Developer/ultrathink/log/reddit-sync.log" },
        { id: "com.ultrathink.social-engagement", name: "Social Engagement", type: :scheduled,
          schedule: "Every 30 min (8am-10:30pm)",
          log: "#{HOME}/Developer/ultrathink/log/social-engagement.log" },
      ]
    }
  }

  def self.check_all
    raw = `launchctl list 2>/dev/null`
    launchd_state = parse_launchctl(raw)

    # Single ps call for runner listener check
    ps_output = `ps -eo args 2>/dev/null`

    SERVICES.transform_values do |group|
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

    if entry.nil?
      result[:state] = "unloaded"
      result[:status] = "error"
    elsif svc[:type] == :daemon
      if entry[:pid]
        result[:state] = "running"
        result[:pid] = entry[:pid]
        result[:status] = entry[:exit_status] == 0 ? "ok" : "warning"
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
      # Verify Runner.Listener is actually alive
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
    end

    # Log info
    if svc[:log]
      result[:log_modified] = LogReader.last_modified(svc[:log])&.iso8601
      if result[:status] != "ok"
        result[:recent_log] = LogReader.tail_errors(svc[:log], 5)
      end
    end

    result
  end
end
