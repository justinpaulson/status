require 'socket'
require 'json'
require_relative 'lib/service_checker'
require_relative 'lib/system_stats'
require_relative 'lib/log_reader'
require_relative 'lib/html_renderer'
require_relative 'lib/favicon_renderer'

PORT = ENV.fetch('PORT', 9999).to_i

module StatusPage
  @cache = nil
  @cache_at = Time.at(0)
  CACHE_TTL = 5

  def self.collect_all
    if Time.now - @cache_at < CACHE_TTL && @cache
      return @cache
    end
    @cache = {
      system: SystemStats.collect,
      services: ServiceChecker.check_all,
      generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')
    }
    @cache_at = Time.now
    @cache
  end
end

server = TCPServer.new('0.0.0.0', PORT)
server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)

$stdout.sync = true
puts "Status server listening on port #{PORT}"

trap('TERM') { server.close; exit }
trap('INT')  { server.close; exit }

loop do
  client = server.accept
  Thread.new(client) do |conn|
    begin
      request_line = conn.gets
      next unless request_line
      _method, path, _version = request_line.split(' ')

      # Read and discard request headers
      while (header = conn.gets) && header != "\r\n"
      end

      if path == '/api/status'
        data = StatusPage.collect_all
        body = JSON.generate(data)
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: application/json; charset=utf-8\r\n" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "Cache-Control: no-cache\r\n" \
                   "Access-Control-Allow-Origin: *\r\n" \
                   "Connection: close\r\n\r\n#{body}"
      elsif path == '/health'
        body = "ok"
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: text/plain\r\n" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "Connection: close\r\n\r\n#{body}"
      elsif path == '/favicon.svg'
        data = StatusPage.collect_all
        all_ok = data[:services].values.all? { |g|
          g[:services].all? { |s| s[:status] == "ok" }
        }
        body = FaviconRenderer.render(all_ok)
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: image/svg+xml\r\n" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "Cache-Control: no-cache\r\n" \
                   "Connection: close\r\n\r\n#{body}"
      elsif path == '/favicon.ico'
        conn.print "HTTP/1.1 301 Moved Permanently\r\nLocation: /favicon.svg\r\nConnection: close\r\n\r\n"
      else
        data = StatusPage.collect_all
        body = HtmlRenderer.render(data)
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: text/html; charset=utf-8\r\n" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "Cache-Control: no-cache\r\n" \
                   "Connection: close\r\n\r\n#{body}"
      end
    rescue => e
      $stderr.puts "#{Time.now} ERROR: #{e.class}: #{e.message}"
    ensure
      conn.close rescue nil
    end
  end
end
