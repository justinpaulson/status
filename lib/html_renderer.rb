require 'erb'

module HtmlRenderer
  TEMPLATE_PATH = File.join(__dir__, '..', 'templates', 'status.html.erb')

  def self.render(data)
    template = File.read(TEMPLATE_PATH)
    erb = ERB.new(template)
    erb.result_with_hash(data: data)
  end
end
