require 'shellwords'
require 'time'

module LogReader
  def self.tail_errors(log_path, num_lines = 5)
    return nil unless log_path && File.exist?(log_path)
    lines = `tail -n 50 #{Shellwords.escape(log_path)} 2>/dev/null`
    error_lines = lines.lines.select { |l| l =~ /error|fail|exception|crash|fatal|killed/i }
    if error_lines.any?
      error_lines.last(num_lines).map(&:strip)
    else
      lines.lines.last(num_lines).map(&:strip)
    end
  end

  def self.last_modified(log_path)
    return nil unless log_path && File.exist?(log_path)
    File.mtime(log_path)
  end
end
