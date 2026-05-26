# Technical Specification - Multilingual Landing Page for setup.app4shark.com

## Objective

Implement a professional multilingual landing page accessible at https://setup.app4shark.com using Rails views with automatic language detection via Accept-Language header, manual language switcher, and cookie-based persistence. The implementation must maintain existing API-only functionality for `/api/*` routes while adding view rendering capability for the landing page.

## Affected Files

### Core Configuration
- `config/application.rb` - Enable ActionView and session middleware
- `config/routes.rb` - Add landing page and language switching routes

### Controllers
- `app/controllers/root_controller.rb` - New controller for landing page and locale management

### Views
- `app/views/layouts/application.html.erb` - New main layout template
- `app/views/root/show.html.erb` - New landing page template

### Locales
- `config/locales/root.pt-BR.yml` - Portuguese translations (new)
- `config/locales/root.es.yml` - Spanish translations (new)
- `config/locales/root.en.yml` - English translations (new)

### Assets
- `public/images/4shark-logo.png` - 4Shark logo (provided by user)
- `public/images/app-store-badge-pt.svg` - Apple App Store badge (Portuguese)
- `public/images/app-store-badge-es.svg` - Apple App Store badge (Spanish)
- `public/images/app-store-badge-en.svg` - Apple App Store badge (English)
- `public/images/google-play-badge-pt.png` - Google Play badge (Portuguese)
- `public/images/google-play-badge-es.png` - Google Play badge (Spanish)
- `public/images/google-play-badge-en.png` - Google Play badge (English)

## Detailed Changes

---

### 1. config/application.rb

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/config/application.rb`

**Current State**:
```ruby
# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative '../lib/application_configuration'

module Setup
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Use the responders controller from the responders gem
    config.app_generators.scaffold_controller :responders_controller

    config.generators do |generators|
      generators.orm :active_record
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = 'Brasilia'
    config.active_record.default_timezone = :utc

    config.i18n.default_locale = 'pt-BR'
    config.i18n.load_path += Rails.root.glob('config/locales/**/*.{rb,yml}')

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end
end
```

**Proposed Change**:
```ruby
# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie' # Enable ActionView for landing page

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative '../lib/application_configuration'

module Setup
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Use the responders controller from the responders gem
    config.app_generators.scaffold_controller :responders_controller

    config.generators do |generators|
      generators.orm :active_record
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = 'Brasilia'
    config.active_record.default_timezone = :utc

    config.i18n.default_locale = 'pt-BR'
    config.i18n.available_locales = ['pt-BR', :es, :en]
    config.i18n.load_path += Rails.root.glob('config/locales/**/*.{rb,yml}')

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Enable cookies and sessions for language persistence (landing page only)
    # This does not affect API routes which remain stateless
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: '_setup_session',
                          same_site: :lax,
                          secure: Rails.env.production?,
                          httponly: true
  end
end
```

**Rationale**:
- Add `action_view/railtie` to enable view rendering capabilities
- Keep `api_only = true` to preserve API middleware configuration
- Add `ActionDispatch::Cookies` and `ActionDispatch::Session::CookieStore` for language persistence
- Configure secure cookie flags: `secure: true` in production (HTTPS only), `httponly: true` (JavaScript cannot access), `same_site: :lax` (CSRF protection)
- Add `available_locales` configuration to explicitly define supported languages

---

### 2. config/routes.rb

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/config/routes.rb`

**Current State**:
```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :devices, only: :create do
        resources :configurations, only: :show, controller: 'devices/configurations'
      end
    end
  end
end
```

**Proposed Change**:
```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  # Landing page routes
  root to: 'root#show'
  post 'language', to: 'root#set_language'

  # API routes (unchanged)
  namespace :api do
    namespace :v1 do
      resources :devices, only: :create do
        resources :configurations, only: :show, controller: 'devices/configurations'
      end
    end
  end
end
```

**Rationale**:
- Add `root to: 'root#show'` to serve landing page at root URL (semantically correct - it's the root of the site)
- Add `POST /language` for manual language switching (POST to avoid caching)
- Keep existing API routes unchanged
- Landing page routes come first (priority), followed by API namespace

---

### 3. app/controllers/root_controller.rb

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/app/controllers/root_controller.rb` (NEW FILE)

**Proposed Implementation**:
```ruby
# frozen_string_literal: true

class RootController < ActionController::Base
  # Use Base instead of API to enable view rendering
  protect_from_forgery with: :exception
  before_action :set_locale

  def show
    # Renders app/views/root/show.html.erb
  end

  def set_language
    locale = params[:locale].to_s.strip

    if valid_locale?(locale)
      cookies[:language] = {
        value: locale,
        expires: 1.year.from_now,
        same_site: :lax,
        secure: Rails.env.production?,
        httponly: true
      }

      redirect_to root_path
    else
      redirect_to root_path, alert: 'Invalid language selection'
    end
  end

  private

  def set_locale
    I18n.locale = determine_locale
  end

  def determine_locale
    # Priority: 1. Cookie, 2. Accept-Language header, 3. Default
    cookie_locale || accept_language_locale || I18n.default_locale
  end

  def cookie_locale
    locale = cookies[:language]
    locale if valid_locale?(locale)
  end

  def accept_language_locale
    return nil unless request.env['HTTP_ACCEPT_LANGUAGE']

    # Parse Accept-Language header
    # Format: "pt-BR,pt;q=0.9,en;q=0.8,es;q=0.7"
    accepted_languages = parse_accept_language(request.env['HTTP_ACCEPT_LANGUAGE'])

    # Find first matching locale
    accepted_languages.each do |lang|
      # Exact match (e.g., "pt-BR")
      return lang if valid_locale?(lang)

      # Language-only match (e.g., "pt" -> "pt-BR", "en" -> "en")
      base_lang = lang.split('-').first
      matching_locale = I18n.available_locales.find { |loc| loc.to_s.start_with?(base_lang) }
      return matching_locale.to_s if matching_locale
    end

    nil
  end

  def parse_accept_language(header)
    # Parse "pt-BR,pt;q=0.9,en;q=0.8,es;q=0.7" into ordered array
    languages = header.split(',').map do |lang|
      parts = lang.split(';')
      locale = parts[0].strip
      quality = parts[1]&.split('=')&.last&.to_f || 1.0
      [locale, quality]
    end

    # Sort by quality (higher first) and return locales
    languages.sort_by { |_locale, quality| -quality }.map(&:first)
  rescue StandardError => e
    Rails.logger.warn("Failed to parse Accept-Language header: #{e.message}")
    []
  end

  def valid_locale?(locale)
    I18n.available_locales.map(&:to_s).include?(locale.to_s)
  end
end
```

**Rationale**:
- Inherit from `ActionController::Base` instead of `ActionController::API` to enable view rendering, sessions, and CSRF protection
- `show` action renders the landing page view (standard RESTful action for displaying a resource)
- `set_language` action handles manual language switching via POST request
- `set_locale` before_action determines and sets the locale for each request
- `determine_locale` implements priority: cookie → Accept-Language → default (pt-BR)
- `parse_accept_language` handles complex Accept-Language header format with quality values (q parameters)
- `valid_locale?` ensures only supported locales are accepted (security)
- Cookie is set with secure flags and 1-year expiration

**Edge Cases Handled**:
- Malformed Accept-Language header (rescued, logs warning, returns empty array)
- Invalid locale from cookie or parameter (ignored, falls back to default)
- Browser sends unsupported language (e.g., Italian) → falls back to Portuguese
- Partial language match (e.g., "en-US" matches "en")

---

### 4. app/views/layouts/application.html.erb

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/app/views/layouts/application.html.erb` (NEW FILE)

**Proposed Implementation**:
```erb
<!DOCTYPE html>
<html lang="<%= I18n.locale %>">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title><%= t('root.title') %></title>
  <meta name="description" content="<%= t('root.description') %>">

  <!-- Favicon -->
  <link rel="icon" type="image/png" href="/images/4shark-logo.png">

  <!-- hreflang tags for SEO -->
  <link rel="alternate" hreflang="pt-BR" href="https://setup.app4shark.com">
  <link rel="alternate" hreflang="es" href="https://setup.app4shark.com">
  <link rel="alternate" hreflang="en" href="https://setup.app4shark.com">
  <link rel="alternate" hreflang="x-default" href="https://setup.app4shark.com">

  <!-- Open Graph meta tags for social sharing -->
  <meta property="og:type" content="website">
  <meta property="og:title" content="<%= t('root.title') %>">
  <meta property="og:description" content="<%= t('root.description') %>">
  <meta property="og:image" content="https://4shark-assets.s3.us-east-1.amazonaws.com/logomarca/logo-azul-1F4B7B.png">
  <meta property="og:url" content="https://setup.app4shark.com">
  <meta property="og:locale" content="<%= I18n.locale %>">

  <!-- Twitter Card meta tags -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="<%= t('root.title') %>">
  <meta name="twitter:description" content="<%= t('root.description') %>">
  <meta name="twitter:image" content="https://4shark-assets.s3.us-east-1.amazonaws.com/logomarca/logo-azul-1F4B7B.png">

  <!-- Tailwind CSS via CDN (no build step required) -->
  <script src="https://cdn.tailwindcss.com"></script>

  <!-- Custom Tailwind configuration -->
  <script>
    tailwind.config = {
      theme: {
        extend: {
          colors: {
            'shark-blue': '#1F4B7B',
          }
        }
      }
    }
  </script>

  <!-- CSRF token for forms -->
  <%= csrf_meta_tags %>
</head>
<body class="bg-gray-50 min-h-screen">
  <%= yield %>
</body>
</html>
```

**Rationale**:
- HTML5 DOCTYPE with semantic structure
- `lang` attribute dynamically set based on current locale
- Comprehensive meta tags for SEO (title, description)
- hreflang tags for multilingual SEO (all point to same URL since we use Accept-Language detection)
- Open Graph and Twitter Card meta tags for social media sharing
- Tailwind CSS via CDN (no build pipeline needed)
- Custom Tailwind config to add brand color (`shark-blue: #1F4B7B`)
- CSRF meta tags for secure POST requests
- Minimal HTML - no unnecessary scripts or stylesheets

---

### 5. app/views/root/show.html.erb

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/app/views/root/show.html.erb` (NEW FILE)

**Proposed Implementation**:
```erb
<div class="min-h-screen flex flex-col">
  <!-- Header with Logo and Language Switcher -->
  <header class="bg-white shadow-sm">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
      <div class="flex justify-between items-center">
        <!-- Logo -->
        <div class="flex items-center">
          <img src="https://4shark-assets.s3.us-east-1.amazonaws.com/logomarca/logo-azul-1F4B7B.png"
               alt="4Shark"
               class="h-10 sm:h-12">
        </div>

        <!-- Language Switcher -->
        <div class="flex items-center space-x-2">
          <label for="language-select" class="text-sm text-gray-600 hidden sm:inline">
            <%= t('.language_label') %>:
          </label>
          <select id="language-select"
                  class="block pl-3 pr-8 py-2 text-base border-gray-300 focus:outline-none focus:ring-shark-blue focus:border-shark-blue sm:text-sm rounded-md bg-white">
            <option value="pt-BR" <%= 'selected' if I18n.locale.to_s == 'pt-BR' %>>Português</option>
            <option value="es" <%= 'selected' if I18n.locale.to_s == 'es' %>>Español</option>
            <option value="en" <%= 'selected' if I18n.locale.to_s == 'en' %>>English</option>
          </select>
        </div>
      </div>
    </div>
  </header>

  <!-- Hero Section -->
  <section class="bg-gradient-to-br from-shark-blue to-blue-700 text-white py-16 sm:py-24">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
      <h1 class="text-4xl sm:text-5xl lg:text-6xl font-bold mb-6">
        <%= t('.hero_title') %>
      </h1>
      <p class="text-xl sm:text-2xl mb-8 text-blue-100 max-w-3xl mx-auto">
        <%= t('.hero_subtitle') %>
      </p>
      <a href="#download"
         class="inline-block bg-white text-shark-blue font-semibold px-8 py-4 rounded-lg shadow-lg hover:bg-blue-50 transition-colors">
        <%= t('.hero_cta') %>
      </a>
    </div>
  </section>

  <!-- Download Section -->
  <section id="download" class="py-16 sm:py-24 bg-white">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <h2 class="text-3xl sm:text-4xl font-bold text-center text-gray-900 mb-4">
        <%= t('.download_title') %>
      </h2>
      <p class="text-center text-gray-600 mb-12 max-w-2xl mx-auto">
        <%= t('.download_description') %>
      </p>

      <div class="flex flex-col sm:flex-row justify-center items-center gap-6">
        <!-- Apple App Store -->
        <a href="<%= t('.app_store_url') %>"
           target="_blank"
           rel="noopener noreferrer"
           class="transform hover:scale-105 transition-transform">
          <img src="/images/app-store-badge-<%= I18n.locale.to_s.split('-').first %>.svg"
               alt="<%= t('.app_store_alt') %>"
               class="h-14 sm:h-16">
        </a>

        <!-- Google Play Store -->
        <a href="<%= t('.play_store_url') %>"
           target="_blank"
           rel="noopener noreferrer"
           class="transform hover:scale-105 transition-transform">
          <img src="/images/google-play-badge-<%= I18n.locale.to_s.split('-').first %>.png"
               alt="<%= t('.play_store_alt') %>"
               class="h-14 sm:h-16">
        </a>
      </div>
    </div>
  </section>

  <!-- Setup Guide Section -->
  <section class="py-16 sm:py-24 bg-gray-50">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <h2 class="text-3xl sm:text-4xl font-bold text-center text-gray-900 mb-4">
        <%= t('.guide_title') %>
      </h2>
      <p class="text-center text-gray-600 mb-12 max-w-2xl mx-auto">
        <%= t('.guide_description') %>
      </p>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
        <!-- Step 1 -->
        <div class="bg-white rounded-lg shadow-md p-6 text-center">
          <div class="w-16 h-16 bg-shark-blue text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-4">
            1
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">
            <%= t('.step1_title') %>
          </h3>
          <p class="text-gray-600 text-sm">
            <%= t('.step1_description') %>
          </p>
        </div>

        <!-- Step 2 -->
        <div class="bg-white rounded-lg shadow-md p-6 text-center">
          <div class="w-16 h-16 bg-shark-blue text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-4">
            2
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">
            <%= t('.step2_title') %>
          </h3>
          <p class="text-gray-600 text-sm">
            <%= t('.step2_description') %>
          </p>
        </div>

        <!-- Step 3 -->
        <div class="bg-white rounded-lg shadow-md p-6 text-center">
          <div class="w-16 h-16 bg-shark-blue text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-4">
            3
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">
            <%= t('.step3_title') %>
          </h3>
          <p class="text-gray-600 text-sm">
            <%= t('.step3_description') %>
          </p>
        </div>

        <!-- Step 4 -->
        <div class="bg-white rounded-lg shadow-md p-6 text-center">
          <div class="w-16 h-16 bg-shark-blue text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-4">
            4
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">
            <%= t('.step4_title') %>
          </h3>
          <p class="text-gray-600 text-sm">
            <%= t('.step4_description') %>
          </p>
        </div>
      </div>
    </div>
  </section>

  <!-- Footer -->
  <footer class="bg-white border-t border-gray-200 py-8 mt-auto">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <p class="text-center text-gray-600 text-sm">
        <%= t('.copyright', year: Time.current.year) %>
      </p>
    </div>
  </footer>
</div>

<!-- Language Switcher JavaScript -->
<script>
  (function() {
    const languageSelect = document.getElementById('language-select');

    if (languageSelect) {
      languageSelect.addEventListener('change', function(e) {
        const selectedLocale = e.target.value;
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

        if (!csrfToken) {
          console.error('CSRF token not found');
          return;
        }

        // Send POST request to update language
        fetch('/language', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken
          },
          body: JSON.stringify({ locale: selectedLocale })
        })
        .then(response => {
          if (response.ok) {
            // Reload page to show new language
            window.location.reload();
          } else {
            console.error('Failed to change language');
            // Revert selection
            languageSelect.value = '<%= I18n.locale %>';
          }
        })
        .catch(error => {
          console.error('Error changing language:', error);
          // Revert selection
          languageSelect.value = '<%= I18n.locale %>';
        });
      });
    }
  })();
</script>
```

**Rationale**:
- Mobile-first responsive design using Tailwind CSS utility classes
- Header with logo (from S3) and language switcher dropdown
- Hero section with gradient background using brand color, clear CTA
- Download section with app store badges (language-specific images)
- Setup guide section with 4 numbered steps in grid layout
- Footer with copyright notice
- Inline JavaScript for language switcher (minimal dependencies)
- CSRF token included in POST request
- Progressive enhancement: works without JavaScript (form fallback could be added)
- All text uses `I18n.t()` - no hardcoded strings
- Images use semantic alt text from translations
- Accessible: proper heading hierarchy, semantic HTML, keyboard navigation

**Responsive Breakpoints**:
- Mobile (< 640px): Single column, smaller text, stacked download buttons
- Tablet (640px - 1024px): 2-column grid for guide steps
- Desktop (> 1024px): 4-column grid for guide steps, larger text

---

### 6. config/locales/root.pt-BR.yml

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/config/locales/root.pt-BR.yml` (NEW FILE)

**Proposed Implementation**:
```yaml
---
pt-BR:
  root:
    # Meta tags
    title: "4Shark - Configure seu aplicativo"
    description: "Baixe o aplicativo 4Shark e configure automaticamente através de código QR. Gerencie remuneração variável de forma simples e eficiente."

    # Header
    language_label: "Idioma"

    # Hero section
    hero_title: "Configure o 4Shark em segundos"
    hero_subtitle: "Baixe o aplicativo, escaneie o código QR fornecido pela sua empresa e comece a usar imediatamente."
    hero_cta: "Baixar Aplicativo"

    # Download section
    download_title: "Baixe o aplicativo 4Shark"
    download_description: "Disponível gratuitamente para iOS e Android. Escolha a sua plataforma abaixo."
    app_store_url: "https://apps.apple.com/br/app/4shark-remunera%C3%A7%C3%A3o-vari%C3%A1vel/id6746106646"
    app_store_alt: "Baixar na App Store"
    play_store_url: "https://play.google.com/store/apps/details?id=com.sharkapp.sharkreal&hl=pt"
    play_store_alt: "Baixar no Google Play"

    # Guide section
    guide_title: "Como configurar o aplicativo"
    guide_description: "Siga estes passos simples para começar a usar o 4Shark."
    step1_title: "Baixe o aplicativo"
    step1_description: "Acesse a App Store (iOS) ou Google Play (Android) e baixe o aplicativo 4Shark gratuitamente."
    step2_title: "Acesse o sistema web"
    step2_description: "Faça login no sistema 4Shark através do navegador da sua empresa. Clique no ícone no canto superior direito para abrir o menu."
    step3_title: "Visualize o QR Code"
    step3_description: "No menu superior, clique no ícone ao lado do seletor de idioma para exibir o código QR de configuração."
    step4_title: "Escaneie o código"
    step4_description: "Abra o aplicativo 4Shark no seu celular e aponte a câmera para o QR Code. O aplicativo será configurado automaticamente com as cores, URLs e configurações da sua empresa."

    # Footer
    copyright: "© %{year} 4Shark. Todos os direitos reservados."
```

**Rationale**:
- Simple flat structure within `root` namespace (matches controller name)
- No unnecessary nesting (e.g., `root.title` instead of `root.meta.title`)
- All keys are descriptive and self-documenting
- App store URLs are language-specific (Brazilian store for Portuguese)
- Clear, friendly, non-technical language
- Setup guide uses text-only descriptions (no screenshots needed)
- Copyright uses interpolation for dynamic year

---

### 7. config/locales/root.es.yml

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/config/locales/root.es.yml` (NEW FILE)

**Proposed Implementation**:
```yaml
---
es:
  root:
    # Meta tags
    title: "4Shark - Configura tu aplicación"
    description: "Descarga la aplicación 4Shark y configúrala automáticamente a través de código QR. Gestiona la remuneración variable de forma simple y eficiente."

    # Header
    language_label: "Idioma"

    # Hero section
    hero_title: "Configura 4Shark en segundos"
    hero_subtitle: "Descarga la aplicación, escanea el código QR proporcionado por tu empresa y comienza a usarla inmediatamente."
    hero_cta: "Descargar Aplicación"

    # Download section
    download_title: "Descarga la aplicación 4Shark"
    download_description: "Disponible gratis para iOS y Android. Elige tu plataforma a continuación."
    app_store_url: "https://apps.apple.com/mx/app/4shark-remunera%C3%A7%C3%A3o-vari%C3%A1vel/id6746106646"
    app_store_alt: "Descargar en App Store"
    play_store_url: "https://play.google.com/store/apps/details?id=com.sharkapp.sharkreal&hl=es"
    play_store_alt: "Descargar en Google Play"

    # Guide section
    guide_title: "Cómo configurar la aplicación"
    guide_description: "Sigue estos pasos simples para comenzar a usar 4Shark."
    step1_title: "Descarga la aplicación"
    step1_description: "Accede a la App Store (iOS) o Google Play (Android) y descarga la aplicación 4Shark gratuitamente."
    step2_title: "Accede al sistema web"
    step2_description: "Inicia sesión en el sistema 4Shark a través del navegador de tu empresa. Haz clic en el ícono en la esquina superior derecha para abrir el menú."
    step3_title: "Visualiza el código QR"
    step3_description: "En el menú superior, haz clic en el ícono junto al selector de idioma para mostrar el código QR de configuración."
    step4_title: "Escanea el código"
    step4_description: "Abre la aplicación 4Shark en tu celular y apunta la cámara al código QR. La aplicación se configurará automáticamente con los colores, URLs y configuraciones de tu empresa."

    # Footer
    copyright: "© %{year} 4Shark. Todos los derechos reservados."
```

**Rationale**:
- Same flat structure as pt-BR (matches controller name)
- Spanish (Latin American) translations
- App store URLs point to Mexican store (representative of Latin America)
- Uses informal "tu" (can be adjusted to "usted" if more formal tone is needed)

**NOTE**: User must provide or validate these translations.

---

### 8. config/locales/root.en.yml

**Location**: `/Users/plribeiro3000/Projects/4Shark/setup/config/locales/root.en.yml` (NEW FILE)

**Proposed Implementation**:
```yaml
---
en:
  root:
    # Meta tags
    title: "4Shark - Configure your app"
    description: "Download the 4Shark app and configure it automatically via QR code. Manage variable compensation simply and efficiently."

    # Header
    language_label: "Language"

    # Hero section
    hero_title: "Set up 4Shark in seconds"
    hero_subtitle: "Download the app, scan the QR code provided by your company, and start using it immediately."
    hero_cta: "Download App"

    # Download section
    download_title: "Download the 4Shark app"
    download_description: "Available for free on iOS and Android. Choose your platform below."
    app_store_url: "https://apps.apple.com/us/app/4shark-remunera%C3%A7%C3%A3o-vari%C3%A1vel/id6746106646"
    app_store_alt: "Download on the App Store"
    play_store_url: "https://play.google.com/store/apps/details?id=com.sharkapp.sharkreal&hl=en"
    play_store_alt: "Get it on Google Play"

    # Guide section
    guide_title: "How to set up the app"
    guide_description: "Follow these simple steps to start using 4Shark."
    step1_title: "Download the app"
    step1_description: "Go to the App Store (iOS) or Google Play (Android) and download the 4Shark app for free."
    step2_title: "Access the web system"
    step2_description: "Log in to the 4Shark system through your company's browser. Click the icon in the top-right corner to open the menu."
    step3_title: "View the QR code"
    step3_description: "In the top menu, click the icon next to the language selector to display the configuration QR code."
    step4_title: "Scan the code"
    step4_description: "Open the 4Shark app on your phone and point the camera at the QR code. The app will be automatically configured with your company's colors, URLs, and settings."

    # Footer
    copyright: "© %{year} 4Shark. All rights reserved."
```

**Rationale**:
- Same flat structure as pt-BR and es (matches controller name)
- Professional American English translations
- App store URLs point to US store
- Uses standard app store terminology ("Download on the App Store", "Get it on Google Play")

**NOTE**: User must provide or validate these translations.

---

## Implementation Sequence

1. **Update Rails configuration** (`config/application.rb`)
   - Add `action_view/railtie`
   - Configure cookies and session middleware
   - Add `available_locales` configuration

2. **Update routes** (`config/routes.rb`)
   - Add root route to `root#show`
   - Add POST `/language` route

3. **Create RootController** (`app/controllers/root_controller.rb`)
   - Implement locale detection logic
   - Implement language switching action

4. **Create locale files**
   - Portuguese (`config/locales/root.pt-BR.yml`)
   - Spanish (`config/locales/root.es.yml`) - requires user translations
   - English (`config/locales/root.en.yml`) - requires user translations

5. **Create view structure**
   - Create `app/views/layouts/` directory
   - Create `app/views/root/` directory

6. **Create layout template** (`app/views/layouts/application.html.erb`)
   - HTML structure, meta tags, Tailwind CSS CDN

7. **Create landing page view** (`app/views/root/show.html.erb`)
   - Header, hero, download, guide, footer sections
   - Language switcher JavaScript

8. **Download and optimize assets**
   - Download official App Store badges (3 languages)
   - Download official Google Play badges (3 languages)
   - Save to `public/images/`
   - Optimize file sizes

9. **Testing**
   - Test automatic language detection
   - Test manual language switching
   - Test cookie persistence
   - Test responsive design (mobile, tablet, desktop)
   - Test all three languages render correctly
   - Test API routes remain unaffected

10. **Update CHANGELOG.md**
    - Add user-focused entry about multilingual landing page

---

## Important Considerations

### Breaking Changes
**NONE** - This implementation adds new functionality without modifying existing API behavior.

### Edge Cases

1. **Malformed Accept-Language header**: Handled with try/rescue, logs warning, falls back to default
2. **Invalid locale parameter**: Validated against whitelist, rejected if invalid
3. **Cookie tampering**: Validated against whitelist, ignored if invalid
4. **No Accept-Language header**: Falls back to default locale (pt-BR)
5. **Browser sends unsupported language**: Falls back to default locale
6. **Partial language match**: "en-US" matches "en", "pt-PT" matches "pt-BR"

### Security Considerations

1. **CSRF Protection**: Enabled via `protect_from_forgery with: :exception`
2. **Cookie Security**: HttpOnly, Secure (in production), SameSite=Lax
3. **Locale Validation**: Only whitelisted locales accepted
4. **XSS Prevention**: Rails ERB auto-escapes output
5. **Input Sanitization**: Locale parameter is validated and sanitized

### Performance Considerations

1. **Page Load**: Tailwind CSS loaded from CDN (fast, cached)
2. **Images**: App store badges are small (< 50KB each), served from public folder
3. **Logo**: Served from S3 CDN (fast, cached)
4. **No Asset Compilation**: No Propshaft, no build step needed
5. **Cookie Storage**: Minimal data (just locale string)
6. **Locale Files**: Rails i18n caching enabled in production

### SEO Considerations

1. **hreflang tags**: Present but all point to same URL (Accept-Language detection)
2. **Meta tags**: Translated title and description per language
3. **HTML lang attribute**: Dynamically set based on locale
4. **Open Graph tags**: Included for social media sharing
5. **Content duplication**: Not an issue - same URL serves different content based on Accept-Language

**Future SEO Enhancement**: If search engine visibility becomes critical, migrate to URL-based routing (Option 2 from PLAN.md) with `/pt`, `/es`, `/en` paths.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Accept-Language header not sent by browser | Users see wrong language | Falls back to Portuguese (largest user base), language switcher always visible |
| CORS issues with POST request | Language switcher fails | CORS already configured, POST is same-origin (no CORS needed) |
| Session middleware breaks API | API endpoints return errors | API routes inherit from `ActionController::API`, landing page uses `ActionController::Base` - separate inheritance chains |
| Tailwind CSS CDN unavailable | Page unstyled | Low risk (CDN has 99.9% uptime), could add fallback inline CSS if critical |
| Cookie blocked by browser | Language preference not saved | Falls back to Accept-Language detection on each visit, functionality still works |
| Invalid translations | Poor user experience | Translations must be reviewed by native speakers before deployment |

---

## Testing Checklist

### Functional Testing
- [ ] Root URL (`/`) serves landing page
- [ ] Portuguese language displays correctly
- [ ] Spanish language displays correctly (after translations provided)
- [ ] English language displays correctly (after translations provided)
- [ ] Language switcher changes language
- [ ] Language preference persists across sessions (cookie)
- [ ] Accept-Language header is parsed correctly
- [ ] Fallback to Portuguese works when language unsupported
- [ ] App store links open correctly (all 3 languages)
- [ ] CSRF token protection works for POST requests

### API Testing
- [ ] `/api/v1/devices` still returns JSON
- [ ] `/api/v1/devices/:id/configurations` still works
- [ ] API responses have correct Content-Type (application/json)
- [ ] API endpoints don't accidentally render HTML

### Browser Testing
- [ ] Chrome (desktop and mobile)
- [ ] Firefox (desktop)
- [ ] Safari (desktop and iOS)
- [ ] Edge (desktop)
- [ ] Chrome on Android

### Responsive Design Testing
- [ ] Mobile portrait (320px - 428px width)
- [ ] Mobile landscape (568px - 812px width)
- [ ] Tablet (768px - 1024px)
- [ ] Desktop (> 1024px)
- [ ] Language switcher accessible on all sizes
- [ ] Download buttons touch-friendly on mobile

### Performance Testing
- [ ] Page load time < 2 seconds on 3G
- [ ] Lighthouse Performance score > 90
- [ ] Lighthouse Accessibility score > 90
- [ ] Lighthouse SEO score > 90
- [ ] No console errors
- [ ] No server errors in logs

### Security Testing
- [ ] CSRF protection active
- [ ] Cookies have HttpOnly, Secure, SameSite flags
- [ ] Invalid locale parameters rejected
- [ ] No XSS vulnerabilities
- [ ] Brakeman security scan passes

### Accessibility Testing
- [ ] Screen reader compatible (test with VoiceOver or NVDA)
- [ ] Keyboard navigation works (Tab, Enter, Shift+Tab)
- [ ] Color contrast meets WCAG AA standards
- [ ] Alt text present on all images
- [ ] Proper heading hierarchy (h1 → h2 → h3)

---

## Dependencies on User-Provided Assets

**CRITICAL**: The following items must be provided by the user before implementation can be completed:

1. **Spanish Translations** (`config/locales/root.es.yml`)
   - All landing page text translated to Spanish
   - Must be reviewed by native Spanish speaker

2. **English Translations** (`config/locales/root.en.yml`)
   - All landing page text translated to English
   - Professional tone, clear instructions

3. **App Store Badge Images**
   - Download from Apple: https://developer.apple.com/app-store/marketing/guidelines/
   - Download from Google: https://play.google.com/intl/en_us/badges/
   - Required in 3 languages (pt, es, en)
   - Save to `public/images/`

4. **Verification of App Store URLs**
   - Confirm if URLs are universal or region-specific
   - Provided URLs in context:
     - iOS Brazilian: `https://apps.apple.com/br/app/4shark-remunera%C3%A7%C3%A3o-vari%C3%A1vel/id6746106646`
     - iOS Mexican: `https://apps.apple.com/mx/app/4shark-remunera%C3%A7%C3%A3o-vari%C3%A1vel/id6746106646`
     - iOS US: `https://apps.apple.com/us/app/4shark-remunera%C3%A7%C3%A3o-vari%C3%A1vel/id6746106646`
     - Android Portuguese: `https://play.google.com/store/apps/details?id=com.sharkapp.sharkreal&hl=pt`
     - Android Spanish: `https://play.google.com/store/apps/details?id=com.sharkapp.sharkreal&hl=es`
     - Android English: `https://play.google.com/store/apps/details?id=com.sharkapp.sharkreal&hl=en`

---

## Post-Implementation Tasks

1. **Monitor Production Logs**
   - Watch for Accept-Language parsing errors
   - Monitor language distribution (which language is most used)

2. **Gather User Feedback**
   - Is automatic detection accurate?
   - Is language switcher easy to find?
   - Are setup instructions clear?

3. **Analytics** (Optional)
   - Add Google Analytics or Plausible to track:
     - Language distribution
     - App store click-through rate
     - Time on page
     - Bounce rate

4. **SEO Monitoring** (Optional)
   - Submit sitemap to Google Search Console
   - Monitor search rankings for "4shark app" in different languages
   - If SEO performance is poor, consider migrating to URL-based routing

---

## Next Step

After this specification is approved, use `/execute` to implement the changes. The `/execute` command will:
1. Read this BLUEPRINT.md
2. Read PLAN.md and TASKS.md
3. Implement all changes sequentially
4. Update CHANGELOG.md
5. Run tests and validations

**Note**: Implementation will pause at hold points where user-provided assets (translations, images) are required.
