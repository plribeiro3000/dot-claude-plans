# Codebase snapshot — Rails i18n setup (captured 2026-06-26)
# Source files referenced in SPIKE.md Finding 1

# ── app/controllers/jwt_authorized_controller.rb ──────────────────────────────
# Line numbers from source as of 2026-06-26

# def set_locale
#   I18n.locale =
#     if current_user.present?
#       current_user.company.locale
#     else
#       I18n.default_locale
#     end
# end

# ── app/models/company.rb (lines 86–98) ───────────────────────────────────────
# Locale is an enumerized integer column (db: t.integer "locale", default: 0)

# enumerize :locale,
#           in: {
#             'pt-BR': 0,
#             en: 1,
#             es: 2,
#             'es-MX': 3,
#             'es-CO': 4,
#             'es-AR': 5,
#             'es-CL': 6,
#             'es-PA': 7,
#             'es-PE': 8
#           },
#           default: 'pt-BR',

# ── config/locales/ directory statistics ──────────────────────────────────────
# Total locale files: 875
# Languages covered: pt-BR, en, es, es-AR, es-CL, es-CO, es-MX, es-PA, es-PE
# Subdirectory layout per language:
#   generic.yml         – generic UI strings
#   incentive_payment.yml
#   models/             – activerecord model translations (name, one, other)
#   pages/              – page-level labels
#   gems/               – gem-generated locale overrides

# ── pt-BR value divergence sample ─────────────────────────────────────────────
# Backend (config/locales/pt-BR/models/acceptment.yml):
#   pt-BR:
#     activerecord:
#       models:
#         acceptment:
#           one: 'Aceitação'
#           other: 'Aceitações'
#
# Frontend (src/translations/pt-BR.json):
#   "acceptment": { "one": "Ciência", "other": "Ciências" }
#
# NOTE: The frontend key "acceptment.one" stores a DOMAIN LABEL used as
# a static string (e.g. `'acceptment.one' | translate` → "Ciência"),
# NOT ICU count-based pluralization. The values diverge intentionally:
# the product label was changed in the frontend without updating the backend.
