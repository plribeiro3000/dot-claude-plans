-- =============================================================================
-- Effort 1 / Phase 1 — Mutation: create the least-privilege Keycloak DB user
-- and transfer ownership of the existing objects onto it.
--
-- Target: the `keycloak` database on the auth-001 RDS, connected as `postgres`.
-- Grounded in active/spike/keycloak-least-privilege-db-user/SPIKE.md.
-- Inventory confirmed by Phase 0 (2026-07-22): 91 tables in `public`, all owned
-- by `postgres`; no sequences/views/matviews.
--
-- ROLE NAME: `keycloak_app` (confirm or override before running).
-- PASSWORD:  generate a strong password yourself, put it in the CREATE ROLE below
--            AND in the auth-001-sm secret (KC_DB_PASSWORD). Never paste it back
--            into the assistant session.
--
-- The optional SELECT on pg_class/pg_namespace Keycloak documents (faster upgrades)
-- is already available to the new role via PostgreSQL's default PUBLIC access to
-- those catalogs — no explicit grant needed (and postgres, being NOSUPERUSER,
-- could not grant on a catalog it does not own anyway).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- SECTION A — as `postgres`: create the role and its baseline grants.
-- LOGIN only; NO superuser/createdb/createrole; NOT a member of rds_superuser.
-- These grants must exist BEFORE the ownership transfer (SPIKE Finding 4).
-- -----------------------------------------------------------------------------
BEGIN;

CREATE ROLE keycloak_app WITH LOGIN PASSWORD '<GERAR_SENHA_FORTE>';

GRANT CONNECT ON DATABASE keycloak TO keycloak_app;
GRANT USAGE, CREATE ON SCHEMA public TO keycloak_app;

-- postgres must be a member of the target role to run ALTER ... OWNER TO
-- (SPIKE Findings 4, 7, 9). KEEP THIS through the whole cutover window — it is
-- the rollback path. It is revoked only in Phase 3, after the cutover is stable.
GRANT keycloak_app TO postgres;

COMMIT;


-- -----------------------------------------------------------------------------
-- SECTION B — as `keycloak_app` (open a NEW connection with the new credentials):
-- prove CREATE + ALTER + DROP work under the new role on a throwaway table,
-- BEFORE transferring any real Keycloak object (SPIKE cutover step 3).
-- All four statements must succeed and the probe table must be gone afterward.
-- -----------------------------------------------------------------------------
-- CREATE TABLE public._kc_probe (id int);
-- ALTER TABLE public._kc_probe ADD COLUMN note text;
-- ALTER TABLE public._kc_probe DROP COLUMN note;
-- DROP TABLE public._kc_probe;


-- -----------------------------------------------------------------------------
-- SECTION C — as `postgres`: transfer ownership of the 91 existing Keycloak
-- tables to keycloak_app. Object-by-object, scoped to `public` — NOT
-- REASSIGN OWNED (SPIKE Finding 7: it is database-wide + shared objects).
-- Wrapped in one transaction: all-or-nothing, so a failure leaves no half-move.
-- -----------------------------------------------------------------------------
BEGIN;

ALTER TABLE public.admin_event_entity OWNER TO keycloak_app;
ALTER TABLE public.associated_policy OWNER TO keycloak_app;
ALTER TABLE public.authentication_execution OWNER TO keycloak_app;
ALTER TABLE public.authentication_flow OWNER TO keycloak_app;
ALTER TABLE public.authenticator_config OWNER TO keycloak_app;
ALTER TABLE public.authenticator_config_entry OWNER TO keycloak_app;
ALTER TABLE public.broker_link OWNER TO keycloak_app;
ALTER TABLE public.client OWNER TO keycloak_app;
ALTER TABLE public.client_attributes OWNER TO keycloak_app;
ALTER TABLE public.client_auth_flow_bindings OWNER TO keycloak_app;
ALTER TABLE public.client_initial_access OWNER TO keycloak_app;
ALTER TABLE public.client_node_registrations OWNER TO keycloak_app;
ALTER TABLE public.client_scope OWNER TO keycloak_app;
ALTER TABLE public.client_scope_attributes OWNER TO keycloak_app;
ALTER TABLE public.client_scope_client OWNER TO keycloak_app;
ALTER TABLE public.client_scope_role_mapping OWNER TO keycloak_app;
ALTER TABLE public.component OWNER TO keycloak_app;
ALTER TABLE public.component_config OWNER TO keycloak_app;
ALTER TABLE public.composite_role OWNER TO keycloak_app;
ALTER TABLE public.credential OWNER TO keycloak_app;
ALTER TABLE public.databasechangelog OWNER TO keycloak_app;
ALTER TABLE public.databasechangeloglock OWNER TO keycloak_app;
ALTER TABLE public.default_client_scope OWNER TO keycloak_app;
ALTER TABLE public.event_entity OWNER TO keycloak_app;
ALTER TABLE public.fed_user_attribute OWNER TO keycloak_app;
ALTER TABLE public.fed_user_consent OWNER TO keycloak_app;
ALTER TABLE public.fed_user_consent_cl_scope OWNER TO keycloak_app;
ALTER TABLE public.fed_user_credential OWNER TO keycloak_app;
ALTER TABLE public.fed_user_group_membership OWNER TO keycloak_app;
ALTER TABLE public.fed_user_required_action OWNER TO keycloak_app;
ALTER TABLE public.fed_user_role_mapping OWNER TO keycloak_app;
ALTER TABLE public.federated_identity OWNER TO keycloak_app;
ALTER TABLE public.federated_user OWNER TO keycloak_app;
ALTER TABLE public.group_attribute OWNER TO keycloak_app;
ALTER TABLE public.group_role_mapping OWNER TO keycloak_app;
ALTER TABLE public.identity_provider OWNER TO keycloak_app;
ALTER TABLE public.identity_provider_config OWNER TO keycloak_app;
ALTER TABLE public.identity_provider_mapper OWNER TO keycloak_app;
ALTER TABLE public.idp_mapper_config OWNER TO keycloak_app;
ALTER TABLE public.jgroups_ping OWNER TO keycloak_app;
ALTER TABLE public.jgroupsping OWNER TO keycloak_app;
ALTER TABLE public.keycloak_group OWNER TO keycloak_app;
ALTER TABLE public.keycloak_role OWNER TO keycloak_app;
ALTER TABLE public.migration_model OWNER TO keycloak_app;
ALTER TABLE public.offline_client_session OWNER TO keycloak_app;
ALTER TABLE public.offline_user_session OWNER TO keycloak_app;
ALTER TABLE public.org OWNER TO keycloak_app;
ALTER TABLE public.org_domain OWNER TO keycloak_app;
ALTER TABLE public.org_invitation OWNER TO keycloak_app;
ALTER TABLE public.policy_config OWNER TO keycloak_app;
ALTER TABLE public.protocol_mapper OWNER TO keycloak_app;
ALTER TABLE public.protocol_mapper_config OWNER TO keycloak_app;
ALTER TABLE public.realm OWNER TO keycloak_app;
ALTER TABLE public.realm_attribute OWNER TO keycloak_app;
ALTER TABLE public.realm_default_groups OWNER TO keycloak_app;
ALTER TABLE public.realm_enabled_event_types OWNER TO keycloak_app;
ALTER TABLE public.realm_events_listeners OWNER TO keycloak_app;
ALTER TABLE public.realm_localizations OWNER TO keycloak_app;
ALTER TABLE public.realm_required_credential OWNER TO keycloak_app;
ALTER TABLE public.realm_smtp_config OWNER TO keycloak_app;
ALTER TABLE public.realm_supported_locales OWNER TO keycloak_app;
ALTER TABLE public.redirect_uris OWNER TO keycloak_app;
ALTER TABLE public.required_action_config OWNER TO keycloak_app;
ALTER TABLE public.required_action_provider OWNER TO keycloak_app;
ALTER TABLE public.resource_attribute OWNER TO keycloak_app;
ALTER TABLE public.resource_policy OWNER TO keycloak_app;
ALTER TABLE public.resource_scope OWNER TO keycloak_app;
ALTER TABLE public.resource_server OWNER TO keycloak_app;
ALTER TABLE public.resource_server_perm_ticket OWNER TO keycloak_app;
ALTER TABLE public.resource_server_policy OWNER TO keycloak_app;
ALTER TABLE public.resource_server_resource OWNER TO keycloak_app;
ALTER TABLE public.resource_server_scope OWNER TO keycloak_app;
ALTER TABLE public.resource_uris OWNER TO keycloak_app;
ALTER TABLE public.revoked_token OWNER TO keycloak_app;
ALTER TABLE public.role_attribute OWNER TO keycloak_app;
ALTER TABLE public.scope_mapping OWNER TO keycloak_app;
ALTER TABLE public.scope_policy OWNER TO keycloak_app;
ALTER TABLE public.server_config OWNER TO keycloak_app;
ALTER TABLE public.user_attribute OWNER TO keycloak_app;
ALTER TABLE public.user_consent OWNER TO keycloak_app;
ALTER TABLE public.user_consent_client_scope OWNER TO keycloak_app;
ALTER TABLE public.user_entity OWNER TO keycloak_app;
ALTER TABLE public.user_federation_config OWNER TO keycloak_app;
ALTER TABLE public.user_federation_mapper OWNER TO keycloak_app;
ALTER TABLE public.user_federation_mapper_config OWNER TO keycloak_app;
ALTER TABLE public.user_federation_provider OWNER TO keycloak_app;
ALTER TABLE public.user_group_membership OWNER TO keycloak_app;
ALTER TABLE public.user_required_action OWNER TO keycloak_app;
ALTER TABLE public.user_role_mapping OWNER TO keycloak_app;
ALTER TABLE public.web_origins OWNER TO keycloak_app;
ALTER TABLE public.workflow_state OWNER TO keycloak_app;

COMMIT;

-- After COMMIT, run Phase 2 verification (all 91 now owned by keycloak_app, none
-- on postgres) BEFORE the cutover (secret update + rolling restart). See PLAN.md.
