# Auxiliary source — Network access (IP access lists, Network Access Manager, private endpoints)

Preserved fetched content supporting SPIKE.md Finding 2 (the documented contradiction) and
Finding 11 (private endpoints vs IP access lists).

## Source A: https://www.mongodb.com/docs/atlas/security/ip-access-list/ (fetched, then re-fetched to self-check)

> "To manage IP Access List entries, you must have `Project Owner` or `Project Network
> Access Manager` access to the project.
>
> Users with `Organization Owner` access must add themselves to the project as a
> `Project Owner`."

> "Atlas supports creating temporary IP access list entries that expire within a
> user-configurable 7-day period."

## Source B: https://www.mongodb.com/docs/atlas/security/add-ip-address-to-list/ (fetched, then re-fetched to self-check)

> "To add your IP address to an IP access list, you must have `Project Owner` access to
> the project."

**This is the contradiction flagged in the investigation brief.** Source A (the general IP
Access List reference page) documents a narrower `Project Network Access Manager` role as
sufficient to manage IP Access List entries. Source B (the "Add your current IP address"
how-to page) states only `Project Owner` suffices, omitting the narrower role entirely. Both
statements were independently re-fetched and confirmed present verbatim in each source. No
page found in this research reconciles the two — a reader following Source B alone would
never learn the narrower role exists, which is exactly what makes the narrower role easy to
miss when designing a least-privilege model.

## Source C: https://www.mongodb.com/docs/atlas/architecture/current/network-security/

> "We recommend that you set up private endpoints for all new staging and production
> projects to limit the extension of your network trust boundary."

> "In general, we recommend using private endpoints for every Atlas project, because this
> approach provides the most granular security and eases the administrative burden that can
> come from managing IP access lists and large blocks of IP addresses as your cloud network
> scales."

> "We recommend that you configure an IP access list for your API keys and programmatic
> access to allow access only from trusted IP addresses such as your CI/CD pipeline or
> orchestration system. These IP access lists are set on the Atlas control plane upon
> provisioning a service account and are separate from IP access lists which can be set on
> the Atlas project data plane for connections to the clusters."

Note: this source does not recommend a policy of an intentionally-empty IP access list to
force all traffic through private networking — that framing came from a secondary
(non-MongoDB) blog summary and was NOT found verbatim on the MongoDB Architecture Center
page itself, so it is dropped from the SPIKE per the quote-or-drop rule.
