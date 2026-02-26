require 'socket'
require 'json'
require 'uri'
require_relative 'lib/service_checker'
require_relative 'lib/system_stats'
require_relative 'lib/log_reader'
require_relative 'lib/html_renderer'
require_relative 'lib/favicon_renderer'

PORT = ENV.fetch('PORT', 9999).to_i

APPLE_TOUCH_ICON = File.binread(File.join(__dir__, 'public', 'apple-touch-icon.png')).freeze

MANIFEST_JSON = JSON.generate({
  name: "Mac Mini Status",
  short_name: "Status",
  start_url: "/",
  display: "standalone",
  background_color: "#0d1117",
  theme_color: "#0d1117",
  icons: [
    { src: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }
  ]
}).freeze

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

      # Read request headers, capture Content-Length
      content_length = 0
      while (header = conn.gets) && header != "\r\n"
        if header =~ /^Content-Length:\s*(\d+)/i
          content_length = $1.to_i
        end
      end

      # Read and discard POST body if present
      conn.read(content_length) if content_length > 0

      if path&.start_with?('/api/logs')
        params = URI.decode_www_form(URI(path).query || '').to_h
        service_id = params['service']
        lines = (params['lines'] || 100).to_i.clamp(1, 1000)
        log_path = ServiceChecker.log_path_for(service_id)
        if log_path
          log_text = LogReader.tail(log_path, lines) || ''
          body = JSON.generate({ service: service_id, lines: log_text })
          conn.print "HTTP/1.1 200 OK\r\n" \
                     "Content-Type: application/json; charset=utf-8\r\n" \
                     "Content-Length: #{body.bytesize}\r\n" \
                     "Cache-Control: no-cache\r\n" \
                     "Access-Control-Allow-Origin: *\r\n" \
                     "Connection: close\r\n\r\n#{body}"
        else
          body = JSON.generate({ error: 'Service not found' })
          conn.print "HTTP/1.1 404 Not Found\r\n" \
                     "Content-Type: application/json\r\n" \
                     "Content-Length: #{body.bytesize}\r\n" \
                     "Connection: close\r\n\r\n#{body}"
        end
      elsif path == '/api/status'
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
        } && data[:system][:docker][:running]
        body = FaviconRenderer.render(all_ok)
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: image/svg+xml\r\n" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "Cache-Control: no-cache\r\n" \
                   "Connection: close\r\n\r\n#{body}"
      elsif _method == 'POST' && path == '/api/docker/start'
        system('open -a OrbStack')
        body = JSON.generate({ status: 'starting' })
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: application/json; charset=utf-8\r\n" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "Cache-Control: no-cache\r\n" \
                   "Access-Control-Allow-Origin: *\r\n" \
                   "Connection: close\r\n\r\n#{body}"
      elsif path == '/favicon.ico'
        conn.print "HTTP/1.1 301 Moved Permanently\r\nLocation: /favicon.svg\r\nConnection: close\r\n\r\n"
      elsif path == '/apple-touch-icon.png'
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: image/png\r\n" \
                   "Content-Length: #{APPLE_TOUCH_ICON.bytesize}\r\n" \
                   "Cache-Control: public, max-age=86400\r\n" \
                   "Connection: close\r\n\r\n"
        conn.write APPLE_TOUCH_ICON
      elsif path == '/manifest.json'
        conn.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: application/manifest+json\r\n" \
                   "Content-Length: #{MANIFEST_JSON.bytesize}\r\n" \
                   "Cache-Control: public, max-age=86400\r\n" \
                   "Connection: close\r\n\r\n#{MANIFEST_JSON}"
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
