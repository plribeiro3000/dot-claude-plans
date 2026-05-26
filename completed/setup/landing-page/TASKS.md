# NEXT TASKS — Multilingual Landing Page for setup.app4shark.com — Rails Views with i18n + Accept-Language Detection + Inline CSS (Option 1)

> **Objective of this iteration:** Create a professional, responsive multilingual landing page (pt-BR, es, en) using Rails views with automatic language detection via Accept-Language header, manual language switcher, and cookie-based persistence.
> **Reference:** derived from `PLAN.md` (section: Option 1 — Rails Views with i18n + Accept-Language Detection + Inline CSS).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (option: **Option 1 - Rails Views with i18n + Accept-Language Detection + Inline CSS**)
- [x] **Base branch:** `develop` • **Working branch:** `develop`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Gather required assets and content
- **Objective:** Collect all necessary assets, URLs, and translations before starting implementation
- **Actions (checklist):**
  - [ ] Request 4Shark logo (SVG or high-res PNG) from user
  - [ ] Request iOS App Store URL from user (may differ by region)
  - [ ] Request Google Play Store URL from user (may differ by region)
  - [ ] Request brand colors/guidelines if available
  - [ ] Confirm exact setup flow with user:
    - How do users receive the configuration code?
    - What's the exact mobile app name?
    - Where in the app do they enter/scan the code?
    - What happens after code entry?
  - [ ] Request Spanish translations for all landing page content
  - [ ] Request English translations for all landing page content
  - [ ] Confirm if app store URLs are region-specific or universal
  - [ ] Confirm if setup steps are identical across all languages/regions
- **Affected files/areas:** None yet (information gathering phase)
- **Completion criteria:** All assets, URLs, and translations available and confirmed by user
- **Observations:** This is critical - implementation cannot proceed without these items
- **[HOLD POINT]** Pause here until user provides: logo file, app store URLs, brand colors, setup flow details, and Spanish/English translations

### Task 2 — Enable ActionView in Rails configuration
- **Objective:** Modify Rails configuration to enable view rendering while maintaining API-only functionality
- **Actions (checklist):**
  - [ ] Open `config/application.rb`
  - [ ] Add `require 'action_view/railtie'` to the require section (if not already present)
  - [ ] Keep `config.api_only = true` but add selective middleware
  - [ ] Document the change with inline comment explaining why ActionView is needed
- **Affected files/areas:** `config/application.rb`
- **Completion criteria:** Rails application can render views without breaking existing API functionality
- **Observations:** Keep api_only = true to preserve API behavior for /api/* routes

### Task 3 — Enable session middleware for cookie-based language persistence
- **Objective:** Add session and cookie middleware to Rails to store user language preference
- **Actions (checklist):**
  - [ ] Open `config/application.rb`
  - [ ] Add `config.middleware.use ActionDispatch::Cookies` to enable cookies
  - [ ] Add `config.middleware.use ActionDispatch::Session::CookieStore, key: '_setup_session'` for sessions
  - [ ] Configure session store with secure flags for production (Secure, HttpOnly, SameSite)
  - [ ] Add inline comment explaining cookie is used only for language preference
- **Affected files/areas:** `config/application.rb`
- **Completion criteria:** Session middleware is available for cookie storage, existing API routes unaffected
- **Observations:** Cookies should be minimal and secure - only store language preference

### Task 4 — Create app/views directory structure
- **Objective:** Set up the view folder structure for landing page
- **Actions (checklist):**
  - [ ] Create `app/views/` directory (Rails will autoload it)
  - [ ] Create `app/views/layouts/` subdirectory
  - [ ] Create `app/views/pages/` subdirectory for landing page view
- **Affected files/areas:** `app/views/layouts/`, `app/views/pages/`
- **Completion criteria:** View directories exist and are ready for templates
- **Observations:** Standard Rails convention for view organization

### Task 5 — Create PagesController with locale detection
- **Objective:** Implement controller with Accept-Language header parsing and language switching logic
- **Actions (checklist):**
  - [ ] Create `app/controllers/pages_controller.rb`
  - [ ] Add `landing` action for root page
  - [ ] Add `set_language` action for manual language switching
  - [ ] Implement `before_action :set_locale` to detect language:
    - Check `cookies[:language]` first (user previously selected language)
    - If no cookie, parse `request.env['HTTP_ACCEPT_LANGUAGE']` header
    - Match against supported locales: `['pt-BR', 'es', 'en']`
    - Fallback to `'pt-BR'` if no match
    - Set `I18n.locale` based on detected/selected language
  - [ ] Implement locale detection helper method (parse Accept-Language with quality values)
  - [ ] Add error handling for malformed Accept-Language headers
  - [ ] Set `cookies[:language]` when user manually switches language
  - [ ] Redirect back to root after language switch
- **Affected files/areas:** `app/controllers/pages_controller.rb`
- **Completion criteria:** Controller detects language automatically, allows manual override, persists choice in cookie
- **Observations:** Accept-Language format: "pt-BR,pt;q=0.9,en;q=0.8,es;q=0.7" - need to parse quality values

### Task 6 — Add routes for landing page and language switcher
- **Objective:** Configure Rails routes for landing page and language switching
- **Actions (checklist):**
  - [ ] Open `config/routes.rb`
  - [ ] Add `root to: 'pages#landing'` to set landing page as root
  - [ ] Add `post 'language', to: 'pages#set_language'` for language switcher
  - [ ] Verify existing `/api/*` routes remain unaffected
  - [ ] Add comments to document new routes
- **Affected files/areas:** `config/routes.rb`
- **Completion criteria:** Root path serves landing page, POST /language switches language, API routes intact
- **Observations:** Use POST instead of GET for language switching to avoid caching issues

### Task 7 — Create Portuguese locale file (pt-BR)
- **Objective:** Define all Portuguese translations for landing page content
- **Actions (checklist):**
  - [ ] Create `config/locales/landing.pt-BR.yml`
  - [ ] Add translations for:
    - Page title and meta description
    - Header section (logo alt text, language switcher labels)
    - Hero section (main heading, subheading, call-to-action)
    - Download section (heading, iOS button, Android button, descriptions)
    - Setup guide section (heading, step 1-4 descriptions)
    - Footer section (copyright, links, contact info if applicable)
  - [ ] Use proper YAML structure: `pt-BR: landing: section: key: "value"`
  - [ ] Keep text clear, friendly, non-technical
- **Affected files/areas:** `config/locales/landing.pt-BR.yml`
- **Completion criteria:** All Portuguese content is defined in YAML format
- **Observations:** Portuguese is the default and most used language

### Task 8 — Create Spanish locale file (es)
- **Objective:** Define all Spanish translations for landing page content
- **Actions (checklist):**
  - [ ] Create `config/locales/landing.es.yml`
  - [ ] Add translations matching pt-BR.yml structure but in Spanish
  - [ ] Translate all sections: title, meta, header, hero, download, guide, footer
  - [ ] Verify translations with native speaker if possible
  - [ ] Keep cultural/regional nuances in mind (Latin American Spanish)
- **Affected files/areas:** `config/locales/landing.es.yml`
- **Completion criteria:** All Spanish content is defined and matches pt-BR structure
- **Observations:** Need user-provided translations from Task 1
- **[HOLD POINT]** Depends on Spanish translations from Task 1

### Task 9 — Create English locale file (en)
- **Objective:** Define all English translations for landing page content
- **Actions (checklist):**
  - [ ] Create `config/locales/landing.en.yml`
  - [ ] Add translations matching pt-BR.yml structure but in English
  - [ ] Translate all sections: title, meta, header, hero, download, guide, footer
  - [ ] Use clear, professional English (American or International)
- **Affected files/areas:** `config/locales/landing.en.yml`
- **Completion criteria:** All English content is defined and matches pt-BR structure
- **Observations:** Need user-provided translations from Task 1
- **[HOLD POINT]** Depends on English translations from Task 1

### Task 10 — Create application layout with Tailwind CSS CDN
- **Objective:** Build main layout template with HTML structure, Tailwind CSS, and meta tags
- **Actions (checklist):**
  - [ ] Create `app/views/layouts/application.html.erb`
  - [ ] Add HTML5 boilerplate with proper DOCTYPE
  - [ ] Add `<head>` section with:
    - `<meta charset="UTF-8">`
    - `<meta name="viewport" content="width=device-width, initial-scale=1.0">`
    - `<title><%= I18n.t('landing.meta.title') %></title>`
    - `<meta name="description" content="<%= I18n.t('landing.meta.description') %>">`
    - `<html lang="<%= I18n.locale %>">`
  - [ ] Include Tailwind CSS via CDN: `<script src="https://cdn.tailwindcss.com"></script>`
  - [ ] Add hreflang meta tags for SEO:
    - `<link rel="alternate" hreflang="pt-BR" href="https://setup.app4shark.com">`
    - `<link rel="alternate" hreflang="es" href="https://setup.app4shark.com">`
    - `<link rel="alternate" hreflang="en" href="https://setup.app4shark.com">`
    - `<link rel="alternate" hreflang="x-default" href="https://setup.app4shark.com">`
  - [ ] Add Open Graph meta tags for social sharing (og:title, og:description, og:image)
  - [ ] Add favicon reference (use logo or placeholder)
  - [ ] Add `<%= yield %>` for content rendering
- **Affected files/areas:** `app/views/layouts/application.html.erb`
- **Completion criteria:** Layout template exists with proper HTML structure and meta tags
- **Observations:** Tailwind CSS CDN is sufficient for a single page - no build step needed

### Task 11 — Create landing page view template
- **Objective:** Build the main landing page HTML structure with i18n placeholders
- **Actions (checklist):**
  - [ ] Create `app/views/pages/landing.html.erb`
  - [ ] Add header section:
    - 4Shark logo (use asset from Task 1)
    - Language switcher dropdown (pt-BR, es, en)
  - [ ] Add hero section:
    - Large heading with `<%= I18n.t('landing.hero.heading') %>`
    - Subheading with explanation
    - Visual appeal with background color or gradient
  - [ ] Add download section:
    - Heading
    - iOS App Store button with URL from Task 1
    - Google Play button with URL from Task 1
    - Icons/badges from official Apple and Google assets
  - [ ] Add setup guide section:
    - Numbered or visual step-by-step guide
    - Step 1: Download app
    - Step 2: Get configuration code
    - Step 3: Enter code in app
    - Step 4: Automatic configuration
    - Use `<%= I18n.t('landing.guide.step1') %>` etc.
  - [ ] Add footer section:
    - Copyright notice
    - Optional: links, contact, social media
  - [ ] Use Tailwind CSS utility classes for styling
  - [ ] Ensure mobile-first responsive design
- **Affected files/areas:** `app/views/pages/landing.html.erb`
- **Completion criteria:** Landing page template is complete with all sections and i18n calls
- **Observations:** All text must use I18n.t() - no hardcoded strings
- **[HOLD POINT]** Depends on logo and app store URLs from Task 1

### Task 12 — Implement language switcher with JavaScript
- **Objective:** Add minimal JavaScript to handle language switching without page reload
- **Actions (checklist):**
  - [ ] Add inline `<script>` tag in layout or landing page
  - [ ] Create language switcher dropdown/buttons in HTML
  - [ ] Add JavaScript to:
    - Listen for language selection (dropdown change or button click)
    - Send POST request to `/language` with selected locale
    - Include CSRF token (Rails CSRF protection)
    - Reload page after successful POST (to show new language)
  - [ ] Add loading state during language switch
  - [ ] Ensure switcher works without JavaScript (progressive enhancement)
  - [ ] Style switcher with Tailwind CSS (prominent, easy to find)
- **Affected files/areas:** `app/views/layouts/application.html.erb` or `app/views/pages/landing.html.erb`
- **Completion criteria:** Language switcher works, persists selection in cookie, reloads page with new language
- **Observations:** Keep JavaScript minimal - only for UX enhancement

### Task 13 — Add app store badges and optimize images
- **Objective:** Download official app store badges and optimize all images for web
- **Actions (checklist):**
  - [ ] Download Apple App Store badge from: https://developer.apple.com/app-store/marketing/guidelines/
  - [ ] Download Google Play badge from: https://play.google.com/intl/en_us/badges/
  - [ ] Save badges to `public/images/` (Rails will serve them automatically)
  - [ ] Save 4Shark logo to `public/images/4shark-logo.svg` (or .png)
  - [ ] Optimize all images:
    - Compress to reduce file size (use ImageOptim, TinyPNG, or similar)
    - Target max 200KB per image
    - Ensure high resolution for Retina displays
  - [ ] Update view templates with correct image paths
  - [ ] Add proper `alt` attributes for accessibility
- **Affected files/areas:** `public/images/`, `app/views/pages/landing.html.erb`
- **Completion criteria:** All images are in place, optimized, and display correctly
- **Observations:** Official badges must follow Apple and Google brand guidelines
- **[HOLD POINT]** Depends on logo from Task 1

### Task 14 — Add CSRF token handling for language switcher
- **Objective:** Ensure language switcher POST request includes Rails CSRF token
- **Actions (checklist):**
  - [ ] Add `<%= csrf_meta_tags %>` to layout head (if not already present)
  - [ ] In language switcher JavaScript, include CSRF token in POST request:
    - Read token from `document.querySelector('meta[name="csrf-token"]').content`
    - Add to request headers: `'X-CSRF-Token': token`
  - [ ] Verify POST request is not blocked by Rails CSRF protection
- **Affected files/areas:** `app/views/layouts/application.html.erb`, JavaScript in landing page
- **Completion criteria:** Language switching POST request works without CSRF errors
- **Observations:** Rails requires CSRF token for POST/PATCH/DELETE requests

### Task 15 — Test automatic language detection
- **Objective:** Verify Accept-Language header detection works correctly
- **Actions (checklist):**
  - [ ] Start Rails server locally (`rails s`)
  - [ ] Test with different browser language settings:
    - Set browser to Portuguese (pt-BR) - should show Portuguese
    - Set browser to Spanish (es) - should show Spanish
    - Set browser to English (en) - should show English
    - Set browser to unsupported language (e.g., Italian) - should fallback to Portuguese
  - [ ] Test quality value parsing (e.g., "en;q=0.8,es;q=0.9" should prefer Spanish)
  - [ ] Test with no Accept-Language header - should fallback to Portuguese
  - [ ] Use browser DevTools or curl to modify Accept-Language header
- **Affected files/areas:** None (testing phase)
- **Completion criteria:** Language detection works accurately for all scenarios
- **Observations:** Test with multiple browsers (Chrome, Firefox, Safari)

### Task 16 — Test manual language switching
- **Objective:** Verify language switcher works correctly and persists choice
- **Actions (checklist):**
  - [ ] Test language switcher dropdown/buttons:
    - Click Portuguese - page should reload in Portuguese
    - Click Spanish - page should reload in Spanish
    - Click English - page should reload in English
  - [ ] Verify cookie is set correctly:
    - Check browser DevTools → Application → Cookies
    - Should see `language` cookie with value `pt-BR`, `es`, or `en`
  - [ ] Test persistence:
    - Select Spanish
    - Close and reopen browser
    - Visit landing page again - should still be in Spanish
  - [ ] Test cookie override:
    - Browser language is Portuguese
    - Manually select English
    - Page should show English (cookie overrides Accept-Language)
- **Affected files/areas:** None (testing phase)
- **Completion criteria:** Language switching works, cookie persists, overrides automatic detection
- **Observations:** Test in private/incognito mode to ensure cookies work

### Task 17 — Test responsive design on all devices
- **Objective:** Verify landing page works correctly on mobile, tablet, and desktop
- **Actions (checklist):**
  - [ ] Test on mobile devices (PRIORITY - most users come from mobile):
    - iOS Safari (iPhone)
    - Chrome on Android
    - Various screen sizes (320px to 428px width)
  - [ ] Test on tablet devices:
    - iPad (Safari)
    - Android tablet (Chrome)
  - [ ] Test on desktop browsers:
    - Chrome, Firefox, Safari, Edge
    - Various window sizes
  - [ ] Verify responsive breakpoints:
    - Header adapts to screen size
    - Language switcher is accessible on mobile
    - Download buttons are touch-friendly
    - Setup guide is readable on small screens
    - Footer doesn't break on narrow screens
  - [ ] Test with browser DevTools device emulation
  - [ ] Test with slow network (throttle to 3G in DevTools)
- **Affected files/areas:** None (testing phase)
- **Completion criteria:** Page looks good and functions correctly on all device sizes and browsers
- **Observations:** Mobile experience is critical - most users access from mobile apps

### Task 18 — Test all three languages completely
- **Objective:** Verify all content displays correctly in Portuguese, Spanish, and English
- **Actions (checklist):**
  - [ ] Set language to Portuguese (pt-BR):
    - Verify all sections display Portuguese text
    - Check for missing translations (should not show translation keys like "landing.hero.title")
    - Verify text is natural and grammatically correct
  - [ ] Set language to Spanish (es):
    - Verify all sections display Spanish text
    - Check for missing translations
    - Verify text is natural and grammatically correct
  - [ ] Set language to English (en):
    - Verify all sections display English text
    - Check for missing translations
    - Verify text is natural and grammatically correct
  - [ ] Check that app store links work in all languages
  - [ ] Verify hreflang tags are present in all versions
  - [ ] Check that HTML lang attribute changes with language
- **Affected files/areas:** None (testing phase)
- **Completion criteria:** All three languages render correctly with no missing translations
- **Observations:** Get native speakers to review Spanish and English if possible

### Task 19 — Test SEO and accessibility
- **Objective:** Ensure landing page is optimized for search engines and accessible to all users
- **Actions (checklist):**
  - [ ] Run Lighthouse audit in Chrome DevTools:
    - Target: Performance > 90, Accessibility > 90, Best Practices > 90, SEO > 90
    - Fix any critical issues identified
  - [ ] Verify meta tags:
    - Title tag is present and descriptive
    - Meta description is present (under 160 characters)
    - Open Graph tags are present for social sharing
    - hreflang tags are correctly configured
  - [ ] Test with screen reader (VoiceOver on Mac, NVDA on Windows):
    - All images have alt text
    - Page structure is logical (headings hierarchy)
    - Language switcher is accessible
    - Links are descriptive
  - [ ] Verify HTML lang attribute matches current language
  - [ ] Test keyboard navigation (Tab, Enter, Shift+Tab)
  - [ ] Verify color contrast meets WCAG AA standards
- **Affected files/areas:** None (testing phase)
- **Completion criteria:** Lighthouse scores are acceptable, page is accessible to all users
- **Observations:** Accessibility is not optional - ensure all users can access content

### Task 20 — Test that API routes remain unaffected
- **Objective:** Confirm that existing API functionality still works after adding view support
- **Actions (checklist):**
  - [ ] Start Rails server locally
  - [ ] Test existing API endpoints:
    - `/api/v1/devices` - should still return JSON
    - `/api/v1/devices/:id/configurations` - should still work
    - Any other existing API routes
  - [ ] Verify API responses have correct Content-Type: application/json
  - [ ] Verify API endpoints don't accidentally render HTML
  - [ ] Check server logs for any errors or warnings
  - [ ] Verify CORS configuration still works for API routes
- **Affected files/areas:** None (testing phase)
- **Completion criteria:** All existing API functionality works correctly, no breaking changes
- **Observations:** Critical - API-only functionality must remain intact

### Task 21 — Performance optimization
- **Objective:** Ensure landing page loads quickly (< 2 seconds)
- **Actions (checklist):**
  - [ ] Test page load time with browser DevTools Network tab
  - [ ] Test on slow connection (3G throttling)
  - [ ] Optimize if needed:
    - Compress images further if load time is slow
    - Consider inlining small images as data URIs
    - Minimize CSS if it becomes large (unlikely with Tailwind CDN)
    - Add loading="lazy" to images below the fold
  - [ ] Verify Tailwind CSS CDN loads from fast CDN (jsDelivr or unpkg)
  - [ ] Consider adding cache headers for static assets
  - [ ] Test Time to First Byte (TTFB) - should be < 500ms
  - [ ] Test Largest Contentful Paint (LCP) - should be < 2.5s
  - [ ] Test Cumulative Layout Shift (CLS) - should be < 0.1
- **Affected files/areas:** Various
- **Completion criteria:** Page loads in < 2 seconds on 3G, meets Core Web Vitals thresholds
- **Observations:** Mobile users often have slower connections - performance is critical

### Task 22 — Update CHANGELOG.md
- **Objective:** Document the new multilingual landing page feature for end users
- **Actions (checklist):**
  - [ ] Open `CHANGELOG.md` in project root
  - [ ] Add new entry under `[Unreleased]` section
  - [ ] Write user-focused description (NOT technical details)
  - [ ] Example: "Added multilingual welcome page with automatic language detection (Portuguese, Spanish, English). The page provides app download links and step-by-step setup instructions in your preferred language."
  - [ ] Follow Keep a Changelog format (Added/Changed/Fixed/etc.)
  - [ ] Emphasize business value: users can now access setup instructions in their language
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** Changelog entry exists and describes the business value clearly
- **Observations:** Focus on WHAT users can now do (access in their language), not HOW (Rails views, i18n, etc.)

### Task 23 — Security review
- **Objective:** Ensure landing page implementation is secure
- **Actions (checklist):**
  - [ ] Verify cookie security flags:
    - Secure flag (cookies only sent over HTTPS in production)
    - HttpOnly flag (JavaScript cannot access cookie)
    - SameSite flag (CSRF protection)
  - [ ] Verify language parameter validation:
    - Only accepts whitelisted values: pt-BR, es, en
    - Rejects invalid input (SQL injection, XSS attempts)
  - [ ] Verify no sensitive information in any language version
  - [ ] Verify CSRF protection is active for POST requests
  - [ ] Check for XSS vulnerabilities (all user input is sanitized)
  - [ ] Verify CSP headers if inline JavaScript is used
  - [ ] Run Brakeman security scanner: `bundle exec brakeman`
  - [ ] Fix any security issues identified
- **Affected files/areas:** Various
- **Completion criteria:** No security vulnerabilities, cookies are secure, input is validated
- **Observations:** Security is critical even for a simple landing page

### Task 24 — Final testing in staging environment
- **Objective:** Test complete implementation in production-like environment before deployment
- **Actions (checklist):**
  - [ ] Deploy to staging server (if available)
  - [ ] Verify HTTPS works correctly
  - [ ] Test all three languages on staging
  - [ ] Test language switcher on staging
  - [ ] Test cookie persistence on staging
  - [ ] Test app store links open correctly
  - [ ] Test responsive design on real mobile devices (not just DevTools)
  - [ ] Test with different browser versions
  - [ ] Verify no console errors in browser DevTools
  - [ ] Verify no server errors in Rails logs
  - [ ] Get user acceptance/approval
- **Affected files/areas:** Staging environment
- **Completion criteria:** Landing page works perfectly on staging, user approves for production
- **Observations:** Staging testing prevents production issues
- **[HOLD POINT]** Wait for user approval before production deployment

### Task 25 — Deploy to production
- **Objective:** Deploy multilingual landing page to production setup.app4shark.com
- **Actions (checklist):**
  - [ ] Confirm deployment strategy with user (Git push? CI/CD? Manual?)
  - [ ] Merge changes to appropriate branch (develop → master or similar)
  - [ ] Deploy to production server
  - [ ] Run database migrations (if any)
  - [ ] Restart Rails server if needed
  - [ ] Access https://setup.app4shark.com in browser
  - [ ] Verify landing page loads correctly in production
  - [ ] Verify SSL certificate is valid (HTTPS)
  - [ ] Test all three languages in production
  - [ ] Test language switcher in production
  - [ ] Test app store links in production
  - [ ] Test on real mobile devices
  - [ ] Monitor server logs for errors
  - [ ] Monitor application performance
  - [ ] Verify API routes still work in production
  - [ ] Announce deployment to team
- **Affected files/areas:** Production server
- **Completion criteria:** Landing page is live, fully functional, and accessible at setup.app4shark.com
- **Observations:** Monitor production for first 24 hours after deployment
- **[HOLD POINT]** Confirm deployment method and timing with user

---

## 2) Items Requiring User Confirmation

- [x] **Approved Option:** Option 1 - Rails Views with i18n + Accept-Language Detection + Inline CSS
- [ ] **4Shark Logo:** Please provide logo file (SVG or high-res PNG) for header
- [ ] **iOS App Store URL:** Please provide full URL to 4Shark app on Apple App Store
- [ ] **Google Play Store URL:** Please provide full URL to 4Shark app on Google Play
- [ ] **Regional URLs:** Are app store URLs the same for all regions, or different for Brazil vs Spain vs US?
- [ ] **Brand Colors:** Please provide hex codes for primary and accent colors (or confirm we should use defaults)
- [ ] **Setup Flow Details:** Please describe the exact user flow:
  1. How do users receive their configuration code? (QR code, email, web portal?)
  2. What is the exact mobile app name users should download?
  3. Where in the app do they enter/scan the code? (first screen, settings menu?)
  4. What happens after they enter the code? (automatic sync, success message?)
- [ ] **Spanish Translations:** Please provide Spanish translations for:
  - Page title and meta description
  - Hero section (main heading, subheading)
  - Download section (heading, buttons, descriptions)
  - Setup guide (all 4 steps with descriptions)
  - Footer (copyright, links)
- [ ] **English Translations:** Please provide English translations for all the same sections
- [ ] **Language Preference:** Confirm default/fallback language is Portuguese (pt-BR)
- [ ] **Deployment Method:** How should we deploy to production? (Git workflow, CI/CD pipeline, manual deployment?)
- [ ] **Deployment Timing:** When should deployment happen? (immediate, scheduled maintenance window?)

> **Expected response (example):**
> `Logo attached (4shark-logo.svg), iOS: https://apps.apple.com/br/app/4shark/..., Android: https://play.google.com/store/apps/details?id=com.4shark.app, URLs are universal (same for all regions), Brand colors: #003366 (primary) #FF6600 (accent), Setup flow: [detailed description], Spanish and English translations attached as separate document, Default language: pt-BR confirmed, Deployment: merge to master triggers automatic deploy via CI/CD, Schedule for next Tuesday 10am BRT`

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] **Future Enhancement:** Add FAQ section if users have common questions about setup process
- [ ] **Future Enhancement:** Add contact/support section if users need help
- [ ] **Future Enhancement:** Add analytics tracking (Google Analytics, Plausible, etc.) to understand language usage
- [ ] **Future Enhancement:** Consider A/B testing different hero messages to improve conversion
- [ ] **Future Enhancement:** If SEO becomes critical, migrate to URL-based routing (Option 2) for better search engine indexing
- [ ] **Future Enhancement:** Add more languages if needed (e.g., German, French, Italian for European expansion)
- [ ] **Future Enhancement:** Add region-specific content (e.g., different support contacts per country)
- [ ] **Monitoring:** Track which language is most used to prioritize future development

---

## Next Steps

1. **User must provide** all items listed in section 2 (logo, URLs, translations, setup flow details)
2. **For complex changes**, consider using `@specifier` to create BLUEPRINT.md before implementation
3. **For straightforward implementation**, proceed directly to `/execute` after receiving required information
4. **Recommendation:** Since this involves Rails configuration changes and i18n setup, consider creating a BLUEPRINT.md using `@specifier` to document the technical implementation details before executing

**Decision Point:** Does this task require detailed technical specification?
- **YES** (Recommended): Use `@specifier` to create BLUEPRINT.md - This involves Rails configuration, middleware, i18n, and multiple moving parts
- **NO**: Proceed directly to `/execute` if you're confident about the implementation approach

The landing page implementation is moderately complex (Rails config changes, i18n, locale detection) - specification is recommended but not strictly required.
