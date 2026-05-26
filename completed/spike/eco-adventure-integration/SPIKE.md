# SPIKE — Eco Adventure Tour Integration Feasibility

**Conducted by:** Paulo Ribeiro
**Date:** 2026-01-29
**Status:** Closed — see conclusions

---

## Goal

Determine whether it is technically feasible to integrate Eco Adventure's external systems (RD Station CRM and Chat2Desk) with the 4Shark platform, and map the client's incentive business rules to understand what data is needed, where it comes from, and how it flows into 4Shark.

---

## Method

- Documented the client's full incentive scoring rules (positive points, penalties, bonuses)
- Mapped each data point to its source system (RD Station CRM, Chat2Desk, or manual)
- Analyzed the RD Station CRM API (endpoints, pagination, rate limits, filters, authentication)
- Analyzed the Chat2Desk API (endpoints, pagination, documentation quality, risks)
- Designed a proposed data flow architecture using the existing Integrator project
- Created field-by-field mapping from RD Station to 4Shark
- Identified calculated indicators that 4Shark would need to compute post-import
- Catalogued open questions that require client confirmation before implementation

---

## Evidence

### Client Business Rules

**Segment:** Tourism and travel
**External systems:** RD Station CRM + Chat2Desk

#### Positive Scoring

| Criterion | Description | Score |
|-----------|-------------|-------|
| **Sales** | Per sale | 3 pts/sale |
| | Sales above R$20k | 5 pts/sale |
| | Isolated service sale (partner or direct client) | 1 pt/sale |
| | Cross sell | 1 pt/sale |
| | Bonus: most sales in the month | 10 pts |
| **Average Ticket** | Per R$1,000 accumulated | 1 pt/R$1,000 |
| | Bonus: consultant with highest average ticket | 10 pts |
| **Air Travel Sales** | Per air travel sale | 2 pts/sale |
| | Bonus: most air travel sales | 5 pts |
| **Opportunities** | Per 5 opportunities created | 1 pt |
| | Bonus: most opportunities | 10 pts |
| **Conversion Rate** | 1st in ranking | 5 pts |
| | 2nd in ranking | 3 pts |
| **Goal Achievement** | 100% of goal | 50 pts |
| | 150% of goal | 70 pts |
| | 200% of goal | 100 pts |

#### Penalty Rule

If opportunity conversion rate is **below 10%** or **above 80%**, all points from the opportunities criterion are lost. This penalizes both poor performance (not converting) and gaming (not registering opportunities properly).

#### Negative Points (ATEND/CRM)

| Criterion | Penalty |
|-----------|---------|
| Wrong lead registration in CRM | -5 pts/sale |
| Unsigned general conditions | -5 pts/opportunity |
| Source field not filled or wrong | -5 pts/record |
| Per yellow card | -10 pts/card |
| No air travel offer for package buyer | -10 pts |
| More than 5 CRM absences in same month | -10 pts |

#### Positive Reinforcement

| Criterion | Bonus |
|-----------|-------|
| 100% correct CRM filling during the month | 10 extra pts |
| No yellow cards | 10 extra pts |

### Data Source Mapping

| Data | Source System | Notes |
|------|--------------|-------|
| Sales/Deals | RD Station CRM | Won opportunities (won=true) |
| Opportunities | RD Station CRM | All created opportunities |
| Sale value | RD Station CRM | Deal amount/value field |
| Sale type (air, package, isolated service) | RD Station CRM | Likely custom field |
| Cross sell | RD Station CRM | Likely custom field or tag |
| CRM filling | RD Station CRM | Required field validation |
| Source field | RD Station CRM | Origin/source field |
| Yellow card | Chat2Desk? / Manual? | **NEEDS CONFIRMATION** |
| CRM absences | RD Station CRM? / Manual? | **NEEDS CONFIRMATION** |
| Signed general conditions | RD Station CRM | Likely custom field |
| Air travel offer | RD Station CRM / Chat2Desk? | **NEEDS CONFIRMATION** |

### RD Station CRM API Analysis

**Documentation**: [developers.rdstation.com](https://developers.rdstation.com/reference)

| Aspect | Detail |
|--------|--------|
| **Base URL** | `https://crm.rdstation.com/api/v1` |
| **Authentication** | Token per user (header or query param `token`) |
| **Rate Limit** | 120 requests/minute |
| **Record Limit** | Maximum 10,000 per listing |

#### Relevant Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/deals` | GET | List deals |
| `/deals/{id}` | GET | Show deal |
| `/contacts` | GET | List contacts |
| `/contacts/{id}` | GET | Show contact |
| `/tasks` | GET | List tasks |
| `/users` | GET | List users (sellers) |
| `/custom_fields` | GET | List custom fields |
| `/pipelines` | GET | List sales funnels |

#### Pagination

```
GET /deals?page=1&limit=100&order=updated_at&direction=desc
```

| Parameter | Description | Default | Max |
|-----------|-------------|---------|-----|
| `page` | Page number | 1 | - |
| `limit` | Records per page | 20 | 200 |
| `order` | Sort field | name | created_at, updated_at, name |
| `direction` | Sort direction | asc | asc, desc |

Response:
```json
{
  "deals": [...],
  "has_more": true,
  "total": 1500
}
```

#### Available Filters

- **Deals**: `start_date`, `end_date`, `win` (boolean), `stage_id`, `user_id`
- **Contacts**: `email`, `phone`, `title`, `q` (search by name)

#### Deal Fields

```json
{
  "_id": "abc123",
  "name": "Pacote Cancun",
  "amount": 15000.00,
  "win": true,
  "created_at": "2025-01-15T10:00:00Z",
  "updated_at": "2025-01-20T14:30:00Z",
  "closed_at": "2025-01-20T14:30:00Z",
  "user": { "_id": "user123", "name": "João Silva" },
  "organization": { "_id": "org123", "name": "Acme Corp" },
  "contacts": [...],
  "custom_fields": {
    "tipo_venda": "pacote",
    "inclui_aereo": true,
    "cross_sell": false
  }
}
```

#### API Feasibility Assessment

| Criterion | Status | Notes |
|-----------|--------|-------|
| Pagination | OK | page + limit, max 200 |
| Date filter | Partial | start_date, end_date for deals |
| updated_at filter | Not confirmed | Only sort, not filter |
| Rate limit | OK | 120/min is sufficient |
| Custom fields | OK | Supports custom_fields |

**Recommended sync strategy:**
- Full daily sync, OR
- Sort by `updated_at desc` and stop when reaching already-processed records

### Chat2Desk API Analysis

**Documentation**: [Postman Collection](https://documenter.getpostman.com/view/8899980/UVC8BRBo)

| Aspect | Detail |
|--------|--------|
| **Base URL** | `https://api.chat2desk.com/v1` |
| **Authentication** | API Token (header `Authorization: Bearer {token}`) |
| **Rate Limit** | Not clearly documented |

#### Relevant Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/dialogs` | GET | List conversations |
| `/messages` | GET | List messages |
| `/clients` | GET | List clients |
| `/operators` | GET | List operators |
| `/tags` | GET | List tags |
| `/statistics` | GET | Statistics |

#### Pagination

```
GET /dialogs?limit=50&offset=100
```

| Parameter | Description |
|-----------|-------------|
| `limit` | Number of records |
| `offset` | Skip N records |

#### API Feasibility Assessment

| Criterion | Status | Notes |
|-----------|--------|-------|
| Pagination | OK | limit + offset |
| Date filter | Not confirmed | Needs practical testing |
| Rate limit | Unknown | Not documented |
| Documentation | Partial | Less detailed than RD Station |

**Identified risks:**
1. Unknown rate limit — may have throttling
2. Date filters not confirmed — may need to pull everything
3. Less mature documentation than RD Station

**Recommended strategy:**
- Test the API manually before implementing
- Check for available webhooks for real-time events
- Consider less frequent sync if no date filter exists

### Proposed Architecture

The existing `integrator` project already has the required infrastructure:

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTEGRATOR                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ExternalApplication: "RD Station CRM"                          │
│  ├── Authentication (TrackmobAuthentication)                    │
│  │   └── token: "rd_station_api_token"                         │
│  │                                                              │
│  ├── ApplicationProgrammingInterface: "Deals"                   │
│  │   ├── uri: "https://crm.rdstation.com/api/v1"               │
│  │   ├── query_template: "/deals?token={{token}}&limit={{resource_limit}}&page=1"
│  │   ├── paginated_query_template: "/deals?token={{token}}&limit={{resource_limit}}&page={{page}}"
│  │   ├── collection_source: "deals"                            │
│  │   └── attribute_mappings:                                    │
│  │       ├── _id → external_id (primary)                       │
│  │       ├── name → description                                 │
│  │       ├── amount → sold_price                               │
│  │       ├── user._id → user_id                                │
│  │       └── custom_fields.* → extra_fields                    │
│  │                                                              │
│  └── ApplicationProgrammingInterface: "Contacts"                │
│      └── (similar structure)                                    │
│                                                                  │
│  ExternalApplication: "Chat2Desk"                               │
│  ├── Authentication (TrackmobAuthentication)                    │
│  │   └── token: "chat2desk_api_token"                          │
│  │                                                              │
│  └── ApplicationProgrammingInterface: "Dialogs"                 │
│      ├── uri: "https://api.chat2desk.com/v1"                   │
│      ├── query_template: "/dialogs?limit={{resource_limit}}"   │
│      ├── paginated_query_template: "/dialogs?limit={{resource_limit}}&offset={{offset}}"
│      └── attribute_mappings: ...                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Data Flow

```
RD Station CRM                    Chat2Desk
     │                                │
     ▼                                ▼
┌─────────────┐                ┌─────────────┐
│ ApiExtractor│                │ ApiExtractor│
└─────────────┘                └─────────────┘
     │                                │
     ▼                                ▼
┌─────────────┐                ┌─────────────┐
│ Transformer │                │ Transformer │
└─────────────┘                └─────────────┘
     │                                │
     └────────────┬───────────────────┘
                  │
                  ▼
          ┌──────────────┐
          │ MongoDB      │
          │ (Resources)  │
          └──────────────┘
                  │
                  ▼
          ┌──────────────┐
          │ LoaderConsumer│
          └──────────────┘
                  │
                  ▼
          ┌──────────────┐
          │ 4Shark API   │
          │ (Deals, etc) │
          └──────────────┘
```

### Field Mapping: RD Station → 4Shark

| RD Station Field | 4Shark Field | Transformation |
|------------------|--------------|----------------|
| `_id` | `external_id` | Direct |
| `name` | `description` | Direct |
| `amount` | `sold_price` | FloatTransformer |
| `user._id` | `user_id` | Lookup by identifier |
| `organization._id` | `client_id` | Lookup by external_id |
| `created_at` | `date` | DateTransformer |
| `win` | - | Only sync if win=true |
| `custom_fields.tipo_venda` | `type` | Map to Sale/ServiceSale |
| `custom_fields.inclui_aereo` | Extra field | For scoring rule |

### Calculated Indicators

Indicators to be computed in 4Shark after import:

| Indicator | Calculation | 4Shark Variable |
|-----------|-------------|-----------------|
| Sales count | COUNT(deals) per user | `vendas_realizadas` |
| Sales >20k | COUNT(deals WHERE sold_price > 20000) | `vendas_acima_20k` |
| Air travel sales | COUNT(deals WHERE type=air) | `vendas_aereo` |
| Average ticket | AVG(sold_price) per user | `ticket_medio` |
| Opportunities | COUNT(deals) with win=false? | `oportunidades` |
| Conversion rate | sales / opportunities * 100 | `taxa_conversao` |

---

## Conclusions

- **RD Station CRM integration is feasible.** The API has sufficient endpoints, pagination, filters, and custom field support. Rate limit (120/min) is adequate. The Integrator project already has the infrastructure to handle this type of API extraction.
- **Chat2Desk integration has significant unknowns.** Rate limits are undocumented, date filters are unconfirmed, and documentation quality is lower. Needs hands-on API testing before committing to implementation.
- **The existing Integrator architecture fits.** No new infrastructure is needed — both APIs can be configured as ExternalApplications with their respective APIs and attribute mappings.
- **Several client data points cannot be mapped without confirmation.** Yellow cards, CRM absences, air travel offers, and sale type differentiation depend on fields/systems that are not yet confirmed (see Open Questions below).
- **Calculated indicators are straightforward** once the raw data is imported — standard aggregations on the 4Shark side.

---

## Open Questions

### To Confirm with Client

1. **RD Station CRM custom fields:**
   - What is the exact field name that indicates sale type (air, package, service)?
   - Is there a field for cross sell?
   - Is there a field for "signed general conditions"?
   - Is there a "source" field and what are the valid values?

2. **Yellow card:**
   - What is a yellow card? Is it a manual penalty?
   - Which system does it come from?
   - How should it be imported/registered?

3. **CRM absences:**
   - What constitutes an "absence"?
   - Is it lack of login? Days without activity?
   - Does RD Station have an API for this?

4. **Air travel offer:**
   - How to know if the consultant offered air travel?
   - Is it a deal field or a Chat2Desk interaction?

5. **Chat2Desk:**
   - What is the purpose of the Chat2Desk integration?
   - Do we want to count messages? Evaluate service quality?
   - Are Chat2Desk operators the same as CRM sellers?

### To Validate Technically

1. **RD Station:**
   - Confirm if `updated_at` filter exists or only sort
   - Obtain API token to test endpoints
   - List available custom fields

2. **Chat2Desk:**
   - Obtain credentials to test API
   - Verify rate limits in practice
   - Verify if date filters exist
   - Verify if webhooks are available

---

## Next Steps

1. Obtain API credentials for both RD Station CRM and Chat2Desk for hands-on testing
2. Confirm open questions with the client (see Open Questions section above)
3. Test APIs manually to validate pagination and filters in practice
4. Define custom field mapping after client confirmation
5. Create PLAN.md with implementation strategy
6. Create TASKS.md with detailed tasks

---

## Sources

- [RD Station CRM API - Developers](https://developers.rdstation.com/reference)
- [RD Station CRM - List Deals](https://developers.rdstation.com/reference/crm-v1-list-deals)
- [RD Station CRM - List Contacts](https://developers.rdstation.com/reference/crm-v1-contacts)
- [Chat2Desk API - Postman](https://documenter.getpostman.com/view/8899980/UVC8BRBo)
- [Chat2Desk Knowledge Base](https://chat2desk.com/en/knowledge-base/integrations/other-integrations/api)
- [Chat2Desk Python Library](https://github.com/jkasemenov/c2d_api)
