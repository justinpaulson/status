module FaviconRenderer
  def self.render(all_ok)
    light_color = all_ok ? "#3fb950" : "#f85149"
    glow_color = all_ok ? "#3fb95060" : "#f8514960"

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
        <!-- Mac Mini body -->
        <rect x="4" y="18" width="56" height="28" rx="6" ry="6" fill="#2d333b" stroke="#444c56" stroke-width="1.5"/>
        <!-- Top highlight -->
        <rect x="4" y="18" width="56" height="14" rx="6" ry="6" fill="#363d47"/>
        <rect x="4" y="26" width="56" height="6" fill="#363d47"/>
        <!-- Bottom bezel line -->
        <line x1="8" y1="40" x2="56" y2="40" stroke="#444c56" stroke-width="0.75"/>
        <!-- Feet -->
        <rect x="10" y="46" width="8" height="3" rx="1.5" fill="#22272e"/>
        <rect x="46" y="46" width="8" height="3" rx="1.5" fill="#22272e"/>
        <!-- Apple logo hint (small circle) -->
        <circle cx="32" cy="27" r="3" fill="#444c56"/>
        <!-- Status light glow -->
        <circle cx="32" cy="43" r="5" fill="#{glow_color}"/>
        <!-- Status light -->
        <circle cx="32" cy="43" r="2.5" fill="#{light_color}"/>
      </svg>
    SVG
  end
end
