require 'shellwords'

module SystemStats
  def self.collect
    {
      uptime: parse_uptime,
      cpu: parse_cpu,
      memory: parse_memory,
      disk: parse_disk,
      load: parse_load,
      docker: parse_docker
    }
  end

  def self.parse_uptime
    raw = `uptime`.strip
    if raw =~ /up\s+(.+?),\s+\d+\s+user/
      $1.strip
    else
      "unknown"
    end
  end

  def self.parse_cpu
    raw = `top -l 1 -n 0 -s 0 2>/dev/null`
    if raw =~ /CPU usage:\s+([\d.]+)% user,\s+([\d.]+)% sys,\s+([\d.]+)% idle/
      { user: $1.to_f, sys: $2.to_f, idle: $3.to_f }
    else
      { user: 0, sys: 0, idle: 100 }
    end
  end

  def self.parse_memory
    page_size = `sysctl -n vm.pagesize 2>/dev/null`.strip.to_i
    page_size = 16384 if page_size == 0
    raw = `vm_stat 2>/dev/null`
    stats = {}
    raw.each_line do |line|
      if line =~ /^(.+?):\s+([\d]+)/
        stats[$1.strip.downcase] = $2.to_i * page_size
      end
    end
    total = `sysctl -n hw.memsize 2>/dev/null`.strip.to_i
    used = (stats["pages active"] || 0) +
           (stats["pages wired down"] || 0) +
           (stats["pages occupied by compressor"] || 0)
    { total: total, used: used, free: total - used }
  end

  def self.parse_disk
    raw = `df -h / 2>/dev/null`
    lines = raw.lines
    return { size: "?", used: "?", avail: "?", capacity: "?" } if lines.length < 2
    parts = lines[1].split
    { size: parts[1], used: parts[2], avail: parts[3], capacity: parts[4] }
  end

  def self.parse_load
    raw = `uptime`.strip
    if raw =~ /load averages?:\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)/
      { one: $1.to_f, five: $2.to_f, fifteen: $3.to_f }
    else
      { one: 0, five: 0, fifteen: 0 }
    end
  end

  def self.parse_docker
    version = `timeout 3 docker info --format '{{.ServerVersion}}' 2>/dev/null`.strip
    if $?.success? && !version.empty?
      { running: true, version: version }
    else
      orbstack_installed = File.exist?('/Applications/OrbStack.app')
      { running: false, orbstack_installed: orbstack_installed }
    end
  end
end
