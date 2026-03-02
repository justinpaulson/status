module FaviconRenderer
  def self.render(all_ok)
    light_color = all_ok ? "#3fb950" : "#f85149"
    glow_color = all_ok ? "#3fb95060" : "#f8514960"

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
        <!-- Server body -->
        <rect x="6" y="12" width="52" height="40" rx="8" ry="8" fill="#2d333b" stroke="#444c56" stroke-width="1.5"/>
        <!-- Top highlight -->
        <rect x="6" y="12" width="52" height="20" rx="8" ry="8" fill="#363d47"/>
        <rect x="6" y="24" width="52" height="8" fill="#363d47"/>
        <!-- Divider line -->
        <line x1="14" y1="36" x2="50" y2="36" stroke="#444c56" stroke-width="0.75"/>
        <!-- Accent bars -->
        <rect x="14" y="22" width="12" height="3" rx="1.5" fill="#444c56"/>
        <rect x="14" y="28" width="8" height="3" rx="1.5" fill="#444c56"/>
        <!-- Status light glow -->
        <circle cx="44" cy="44" r="6" fill="#{glow_color}"/>
        <!-- Status light -->
        <circle cx="44" cy="44" r="3" fill="#{light_color}"/>
      </svg>
    SVG
  end
end
