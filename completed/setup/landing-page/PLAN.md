# PLAN — Multilingual Landing Page for setup.app4shark.com

**Status:** ✅ COMPLETED

## Current Situation
- **Relevant context/architecture:**
  - The setup.app4shark.com is a Rails 8.0.3 API-only application (config.api_only = true)
  - Project is configured with Ruby 3.4.1
  - Rails i18n is already configured: default_locale = 'pt-BR'
  - Application has no view layer, asset pipeline, or HTML rendering capabilities
  - Current stack includes only API controllers (Api::V1::DevicesController, Api::V1::Devices::ConfigurationsController)
  - No Sprockets, Webpacker, or Vite configured for asset management
  - Public folder contains only robots.txt
  - Application serves as configuration bridge between mobile apps and backend APIs

- **Impacted components:**
  - Rails application configuration (needs to enable view rendering)
  - Routes (need to add landing page routes with language support)
  - Controllers (new controller for landing page with locale detection)
  - Views (new directory and files with i18n support)
  - Locale files (need pt-BR, es, en translations)
  - Middleware (session/cookie support for language persistence)
  - Assets (CSS, JavaScript for language switcher)

- **Versions/environment:**
  - Rails 8.0.3 (already has i18n support built-in)
  - Ruby 3.4.1
  - Production environment: setup.app4shark.com
  - Existing i18n config: default_locale = 'pt-BR', load_path configured

## Objective / Target State
- **Desired outcome:**
  - Professional multilingual landing page accessible at https://setup.app4shark.com
  - Automatic language detection for anonymous users (not logged in)
  - Support for three languages: Portuguese (pt-BR), Spanish (es), English (en)
  - User can manually override language selection
  - Language preference persists across visits (cookie)
  - Page includes 4Shark branding, clear explanation, app download links, setup guide
  - Responsive design that works on mobile, tablet, and desktop
  - Fast loading and requires minimal maintenance
  - No impact on existing API endpoints

- **Success metrics / acceptance criteria:**
  - Landing page correctly detects user language from browser settings
  - All three languages (pt-BR, es, en) render correctly
  - Manual language switcher works and persists preference
  - Page displays correctly on mobile (iOS/Android), tablet, and desktop browsers
  - All download links are functional (Apple Store, Google Play)
  - Setup guide is clear in all three languages
  - Page load time < 2 seconds
  - Maintains API-only architecture for /api/* routes
  - SEO: search engines can index all language versions
  - Zero downtime deployment

## Problem / New Feature
- **Objective description:**
  - Currently, landing page is planned as static HTML (Option 3 from previous plan)
  - **NEW REQUIREMENT**: System has clients who speak Portuguese (current), Spanish (current), and English (coming soon)
  - **CRITICAL CONSTRAINT**: Users are NOT logged in when accessing the landing page
  - Cannot determine language from user preferences in database
  - Static HTML (Option 3) is NO LONGER viable - page must be dynamic to handle i18n
  - Need intelligent language detection without authentication
  - Must provide fallback mechanism if detection fails
  - Language preference should persist for returning visitors

- **Why this is complex for anonymous users:**
  - No user session or authentication at this point
  - No database record to store language preference
  - Cannot use user profile settings
  - Must rely on browser/client-side signals
  - Need to balance automatic detection with user control
  - SEO implications: need proper URL structure for search engines

## Challenges, Difficulties and Risks

- **Technical:**
  - Rails is configured as API-only (config.api_only = true) - needs partial reconfiguration
  - Need to enable ActionView and session/cookie middleware selectively
  - Need to maintain existing API functionality while adding view support
  - Cookie-based language persistence requires session middleware
  - URL structure decision impacts SEO and routing complexity
  - Potential conflicts with existing CORS configuration
  - Asset pipeline decision (Propshaft vs inline CSS)
  - Browser Accept-Language header parsing is complex (has quality values, multiple languages)

- **Product/UX:**
  - Language detection must be accurate but not intrusive
  - Users should feel in control of language selection
  - Language switcher must be prominent and easy to find
  - Mobile users (primary audience) need touch-friendly switcher
  - What if browser language is not one of the three supported? (e.g., Italian)
  - Setup guide steps might vary slightly by region/language
  - Download links may need to be region-specific (different app store URLs)

- **Security/privacy:**
  - Minimal concerns since it's a landing page
  - Cookies require proper SameSite, Secure, HttpOnly flags
  - Ensure no sensitive information in any language version
  - Validate language codes to prevent injection attacks
  - CSP headers for any inline JavaScript

- **Performance:**
  - Page should load fast in all three languages
  - Minimize JavaScript dependencies for language switcher
  - Consider CDN for CSS frameworks if used
  - Image optimization for logos/screenshots
  - Cache headers for static assets
  - Locale file loading performance (Rails i18n caching)

- **SEO:**
  - Search engines need to discover all language versions
  - Need proper hreflang tags for multilingual SEO
  - URL structure impacts search ranking
  - Avoid duplicate content penalties

## Solution Options (comparative)

### Language Detection Strategies

#### Strategy A — Browser Accept-Language Header (Recommended)
- **How it works:**
  - Read `Accept-Language` HTTP header sent by browser
  - Parse quality values (e.g., "pt-BR,pt;q=0.9,en;q=0.8,es;q=0.7")
  - Match against supported locales (pt-BR, es, en)
  - Set Rails I18n.locale based on best match
  - Store choice in cookie for future visits
  - Provide manual language switcher to override

- **Pros:**
  - Standard web practice - how most sites handle this
  - Works automatically without user interaction
  - Respects user's OS/browser language preferences
  - No complex URL routing needed
  - Rails has built-in support (http_accept_language gem)
  - Cookie persists override for returning users
  - Clean URLs (no language prefix needed)

- **Cons:**
  - Accept-Language header is not always accurate (public computers, VPNs)
  - Some browsers send multiple languages with quality values (parsing complexity)
  - Users might not know their browser is configured incorrectly
  - Search engines may have difficulty discovering all versions

- **When NOT to use:**
  - If SEO is critical and you need separate URLs for each language
  - If you want language to be explicit in URL for sharing
  - If users frequently switch languages on same device

#### Strategy B — URL Path-based (e.g., /pt, /es, /en)
- **How it works:**
  - Root path "/" detects language and redirects to /pt, /es, or /en
  - Each language has dedicated URL path
  - Routes: get '/:locale' => 'pages#landing', constraints: {locale: /pt|es|en/}
  - Extract locale from params[:locale]
  - Language switcher changes URL path
  - Cookie stores preference for root path redirect

- **Pros:**
  - SEO-friendly: search engines index each language separately
  - Shareable URLs: user can send language-specific link
  - Explicit language in URL is clear to users
  - Easy to implement with Rails routing
  - Good for analytics (can track which language is popular)

- **Cons:**
  - Root path needs redirect logic (extra request)
  - More complex routing
  - URL structure is more rigid
  - Switching language changes URL (may confuse users)
  - Need to handle both "/" and "/:locale" routes

- **When NOT to use:**
  - If you want seamless language switching without URL change
  - If root path should always show detected language without redirect
  - If URL sharing is not important

#### Strategy C — Subdomain-based (e.g., pt.setup.app4shark.com)
- **How it works:**
  - Different subdomain for each language
  - DNS: pt.setup.app4shark.com, es.setup.app4shark.com, en.setup.app4shark.com
  - Rails routing based on request.subdomain
  - Root domain (setup.app4shark.com) detects and redirects to appropriate subdomain

- **Pros:**
  - Best for SEO: completely separate sites in search engines
  - Clear separation of languages
  - Can have different SSL certificates per language if needed
  - Good for CDN optimization per region
  - Professional appearance for enterprise clients

- **Cons:**
  - **OVERKILL for a single landing page**
  - Requires DNS configuration (3 subdomains)
  - SSL certificate must cover subdomains
  - More complex deployment
  - Harder to maintain (feels like separate sites)
  - Cookie sharing between subdomains is tricky

- **When NOT to use:**
  - For simple landing pages (like this one)
  - When you don't have control over DNS
  - When maintenance cost outweighs benefits

#### Strategy D — Query Parameter (e.g., ?lang=pt)
- **How it works:**
  - Default URL shows detected language
  - Language switcher appends ?lang=pt, ?lang=es, ?lang=en
  - Controller reads params[:lang] to set locale
  - Cookie stores preference

- **Pros:**
  - Simplest implementation
  - No routing complexity
  - Easy to add to existing setup
  - Shareable language-specific URLs

- **Cons:**
  - **Poor SEO**: search engines may treat ?lang as duplicate content
  - Ugly URLs for a landing page
  - Feels outdated (modern sites use paths)
  - Query parameter can be lost when sharing
  - Not professional appearance

- **When NOT to use:**
  - When SEO matters
  - When URL aesthetics matter
  - For user-facing landing pages (use for admin panels)

#### Strategy E — JavaScript-based Detection (Client-side)
- **How it works:**
  - Serve single HTML with all translations in JSON
  - JavaScript detects navigator.language
  - Client-side rendering switches content
  - localStorage persists preference

- **Pros:**
  - No server-side logic needed
  - Fast switching (no page reload)
  - Works with static HTML

- **Cons:**
  - **Terrible for SEO**: search engines see only one language (or none)
  - Requires JavaScript (bad for accessibility)
  - Slower initial render (extra JavaScript execution)
  - Not suitable for Rails application
  - Harder to maintain (translations in JSON)

- **When NOT to use:**
  - For landing pages that need SEO
  - In Rails applications (waste of Rails i18n)
  - When you care about accessibility

### Implementation Approaches

#### Option 1 — Rails Views with i18n + Accept-Language Detection + Inline CSS
- **How it works:**
  - Enable ActionView and session middleware in Rails
  - Use http_accept_language gem or custom parser for Accept-Language header
  - Create PagesController with before_action :set_locale
  - Single route: root to: 'pages#landing'
  - ERB views using I18n.t() helpers
  - Locale files: config/locales/landing.pt-BR.yml, landing.es.yml, landing.en.yml
  - Cookie stores user's manual language selection
  - Inline CSS or small external file
  - Simple JavaScript for language switcher (toggle cookie and reload)

- **Pros:**
  - Leverages Rails' built-in i18n system (already configured)
  - Simple routing (no URL path complexity)
  - Automatic language detection feels seamless
  - Easy to maintain translations (YAML files)
  - Minimal JavaScript (progressive enhancement)
  - Fast deployment - no asset compilation
  - Cookie-based persistence is standard practice
  - Can use i18n-tasks gem for translation management

- **Cons:**
  - Needs session middleware (breaks pure API-only mode)
  - SEO requires hreflang tags (manual configuration)
  - Search engines may not discover all language versions easily
  - Language not visible in URL (harder to share specific language)

- **When NOT to use:**
  - If SEO is absolutely critical
  - If you need separate URLs for each language
  - If keeping pure API-only mode is mandatory

#### Option 2 — Rails Views with i18n + URL Path-based + Propshaft
- **How it works:**
  - Enable ActionView and configure Propshaft (Rails 8 default asset pipeline)
  - Route structure: get '/:locale' => 'pages#landing', constraints: {locale: /pt|es|en/}
  - Root path "/" detects Accept-Language and redirects to /pt, /es, or /en
  - Extract locale from params[:locale]
  - Proper app/assets structure for CSS and JavaScript
  - Language switcher links to different paths
  - Cookie stores preference for future "/" visits

- **Pros:**
  - **Best for SEO**: each language has unique URL
  - Shareable language-specific links
  - Clear and explicit language in URL
  - Proper Rails asset pipeline (prepared for growth)
  - hreflang tags are straightforward (one per URL)
  - Search engines can index each version separately
  - Better analytics (track language popularity)

- **Cons:**
  - More complex routing logic
  - Root path needs redirect (extra request)
  - Propshaft requires asset precompilation in deployment
  - More configuration overhead
  - URL changes when switching language (may confuse users)

- **When NOT to use:**
  - If you want simplest possible implementation
  - If URL structure doesn't matter for your use case
  - If deployment complexity is a concern

#### Option 3 — Static HTML (NO LONGER VIABLE)
- **Status:** **RULED OUT**
- **Why:** Cannot support dynamic language detection/switching for anonymous users
- **Previous decision:** Was approved but new i18n requirement makes it impossible

## Proposed Steps (high level, don't execute yet)

### For Option 1 (Accept-Language + Inline CSS):
1. Modify config/application.rb to enable ActionView selectively
2. Enable session middleware with cookie_store for language persistence
3. Create app/views folder structure (layouts, pages)
4. Create PagesController with locale detection logic:
   - Parse Accept-Language header (use http_accept_language gem or custom)
   - Check cookie for previous language selection
   - Set I18n.locale
   - Provide set_language action for manual switching
5. Add routes: root to pages#landing, patch /language route for switcher
6. Create locale files:
   - config/locales/landing.pt-BR.yml
   - config/locales/landing.es.yml
   - config/locales/landing.en.yml
7. Build landing page view with I18n.t() calls:
   - Header with language switcher
   - Hero section
   - App downloads
   - Setup guide
   - Footer
8. Add inline CSS or small external CSS file
9. Add minimal JavaScript for language switcher (updates cookie, reloads page)
10. Add hreflang meta tags for SEO
11. Test all three languages on multiple browsers
12. Test language persistence (cookie)
13. Test Accept-Language detection with different browser settings
14. Deploy to staging/production

### For Option 2 (URL Path-based + Propshaft):
1. Add propshaft gem to Gemfile (if not already present)
2. Enable ActionView and configure Propshaft
3. Enable session middleware
4. Create app/assets structure (stylesheets, javascript)
5. Create PagesController with locale extraction from URL:
   - Extract params[:locale]
   - Validate against whitelist (pt, es, en)
   - Set I18n.locale
6. Add routes:
   - root to redirect action (detects Accept-Language, redirects to /:locale)
   - get '/:locale' => 'pages#landing', constraints: {locale: /pt|es|en/}
7. Create locale files (same as Option 1)
8. Build landing page view with I18n.t() calls
9. Language switcher generates links: /pt, /es, /en
10. Add hreflang tags with explicit URLs
11. Precompile assets
12. Test all three language paths
13. Test root redirect logic
14. Deploy with asset:precompile step

## Internal References
- Code:
  - `config/application.rb` - API-only configuration, i18n already configured
  - `config/routes.rb` - Current routes (only API namespace)
  - `app/controllers/application_controller.rb` - Base controller
  - `config/locales/rails.yml` - Existing locale file (pt-BR)
  - `Gemfile` - Need to add session middleware, possibly http_accept_language

- Documentation needs:
  - App store URLs (iOS and Android) - may differ by region
  - 4Shark logo assets (high resolution)
  - Brand colors/guidelines
  - Exact setup flow in mobile app (for guide section)
  - Translation content for Spanish and English (Portuguese exists)
  - Confirmation: are setup steps identical across all languages/regions?

- Research needed:
  - Do app store links need to be region-specific? (US store vs Brazilian store)
  - Are there any country-specific legal requirements for landing pages?
  - Should phone numbers or support emails differ by language?

---

## Recommendation

I recommend **Option 1 (Rails Views with i18n + Accept-Language Detection + Inline CSS)** for the following reasons:

### Why Option 1:

1. **Simplicity**: Leverages Rails' built-in i18n system (already configured for pt-BR)
2. **User Experience**: Automatic detection is seamless - users see their language immediately
3. **Minimal Configuration**: No complex routing, no asset pipeline, just enable views
4. **Rails Best Practices**: Using Accept-Language header is the standard Rails way
5. **Cookie Persistence**: Simple cookie stores manual language override
6. **Maintenance**: Translations in YAML files are easy to manage
7. **Fast Deployment**: No asset compilation, just deploy views and locale files
8. **Progressive Enhancement**: Works without JavaScript, switcher enhances experience
9. **No URL Pollution**: Clean URLs without language prefixes or query parameters

### Why NOT Option 2:

- **Overkill for this use case**: Propshaft and URL-based routing add complexity
- **Extra request**: Root path redirect adds latency
- **Not needed yet**: If we need better SEO later, we can migrate
- **Deployment complexity**: Asset precompilation adds CI/CD steps
- **Single page**: Asset pipeline makes sense for multi-page apps, not single landing page

### Fallback Strategy:

- **Default language**: Portuguese (pt-BR) - largest user base
- **Detection order**:
  1. Check cookie (user previously selected language)
  2. Parse Accept-Language header
  3. Fallback to pt-BR if no match

- **Supported languages**: pt-BR (Portuguese), es (Spanish), en (English)
- **Unsupported languages**: Default to Portuguese with language switcher visible

### SEO Considerations:

- Use hreflang meta tags: `<link rel="alternate" hreflang="pt-BR" href="https://setup.app4shark.com" />`
- Use lang attribute on HTML tag: `<html lang="pt-BR">`
- Include Open Graph meta tags with language
- If SEO becomes critical, migration to Option 2 is straightforward

### Mobile-First:

- Language switcher must be touch-friendly (large tap targets)
- Minimal JavaScript to keep page fast on mobile networks
- Responsive design with mobile-first CSS

---

**Question:** Which option do you prefer to follow?

Answer with: `APPROVED: Option 1` **or** `APPROVED: Option 2`.

(Alternative options or modifications are welcome, describe if applicable.)

---

## Decision

**APPROVED: Option 1**

**Rationale:** Option 1 (Rails Views with i18n + Accept-Language Detection + Inline CSS) is the right choice for a single landing page. It leverages Rails' built-in i18n system, provides seamless automatic language detection, and avoids the complexity of asset pipelines and URL-based routing. If SEO becomes critical later, migration to Option 2 is straightforward.
