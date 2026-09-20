-- Idempotent upgrades for existing Giftistry PostgreSQL data directories.
-- Safe to re-run; mirrors giftistry-bun migrations on startup.
-- Keep in sync with giftistry-bun/src/common/database/migrations.ts and run-migration.ts
-- Create tables (audit_log, content_reports, etc.) before their indexes.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS theme VARCHAR(255) DEFAULT 'default';
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar TEXT DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verification_token VARCHAR(255) DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verification_expires TIMESTAMP WITH TIME ZONE DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_secret VARCHAR(255) DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_recovery_codes TEXT DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;

DO $$ BEGIN
  ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
EXCEPTION WHEN others THEN NULL;
END $$;

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_onboarded BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS oauth_sub VARCHAR(255) DEFAULT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_oauth_sub ON users (oauth_sub) WHERE oauth_sub IS NOT NULL;

DO $$ BEGIN
  ALTER TABLE users ALTER COLUMN avatar TYPE TEXT;
EXCEPTION WHEN others THEN NULL;
END $$;

ALTER TABLE users ADD COLUMN IF NOT EXISTS birthday DATE DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_online TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_owner BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_enabled BOOLEAN DEFAULT TRUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS web_search_enabled BOOLEAN DEFAULT TRUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_disabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_count INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS force_password_change BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS login_attempts_before_lockout INTEGER DEFAULT -1;
ALTER TABLE users ADD COLUMN IF NOT EXISTS session_version INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS policy_json JSONB DEFAULT '{}'::jsonb;

ALTER TABLE lists ADD COLUMN IF NOT EXISTS category VARCHAR(255) DEFAULT 'generic';
ALTER TABLE lists ADD COLUMN IF NOT EXISTS reveal_suggestions BOOLEAN DEFAULT TRUE;
ALTER TABLE lists ADD COLUMN IF NOT EXISTS ai_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE lists ADD COLUMN IF NOT EXISTS web_search_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE lists ADD COLUMN IF NOT EXISTS manual_job_background BOOLEAN DEFAULT TRUE;
ALTER TABLE lists ADD COLUMN IF NOT EXISTS auto_rollover BOOLEAN DEFAULT FALSE;
ALTER TABLE lists DROP COLUMN IF EXISTS visibility;

ALTER TABLE list_shares ADD COLUMN IF NOT EXISTS granted_via VARCHAR(50) DEFAULT 'direct';

ALTER TABLE items ADD COLUMN IF NOT EXISTS is_suggestion BOOLEAN DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT NULL;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS desired_quantity INTEGER DEFAULT NULL;
ALTER TABLE items ADD COLUMN IF NOT EXISTS multi_count BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS other_users_can_see BOOLEAN DEFAULT NULL;
ALTER TABLE items ADD COLUMN IF NOT EXISTS custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE items ADD COLUMN IF NOT EXISTS variations JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE items ADD COLUMN IF NOT EXISTS photos JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE items ADD COLUMN IF NOT EXISTS allow_substitutions BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_substitution BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS substitution_for_item_id UUID NULL REFERENCES items(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS item_item_links (
    item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    linked_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, linked_item_id),
    CHECK (item_id <> linked_item_id)
);
CREATE INDEX IF NOT EXISTS idx_item_item_links_linked_item_id ON item_item_links (linked_item_id);

-- Backfill metadata columns + linked-item junction from legacy Description JSON.
DO $$
DECLARE
  r RECORD;
  parsed JSONB;
  linked_id TEXT;
BEGIN
  FOR r IN
    SELECT id, description
    FROM items
    WHERE description IS NOT NULL
      AND trim(description) LIKE '{%'
      AND trim(description) LIKE '%}'
  LOOP
    BEGIN
      parsed := r.description::jsonb;
    EXCEPTION WHEN others THEN
      CONTINUE;
    END;

    UPDATE items
    SET
      is_favorite = COALESCE((parsed->>'IsFavorite')::boolean, is_favorite),
      is_pinned = COALESCE((parsed->>'IsPinned')::boolean, is_pinned),
      desired_quantity = COALESCE((parsed->>'DesiredQuantity')::integer, desired_quantity),
      multi_count = COALESCE((parsed->>'MultiCount')::boolean, multi_count),
      other_users_can_see = CASE
        WHEN parsed ? 'OtherUsersCanSee' THEN (parsed->>'OtherUsersCanSee')::boolean
        ELSE other_users_can_see
      END,
      custom_fields = COALESCE(parsed->'CustomFields', custom_fields),
      variations = COALESCE(parsed->'Variations', variations),
      description = NULLIF(trim(COALESCE(parsed->>'Text', '')), '')
    WHERE id = r.id;

    IF parsed ? 'LinkedItemIds' AND jsonb_typeof(parsed->'LinkedItemIds') = 'array' THEN
      FOR linked_id IN SELECT jsonb_array_elements_text(parsed->'LinkedItemIds')
      LOOP
        IF linked_id IS DISTINCT FROM r.id::text THEN
          BEGIN
            INSERT INTO item_item_links (item_id, linked_item_id)
            VALUES (r.id, linked_id::uuid)
            ON CONFLICT DO NOTHING;
          EXCEPTION WHEN others THEN
            NULL;
          END;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END $$;

ALTER TABLE claims ADD COLUMN IF NOT EXISTS anonymous BOOLEAN DEFAULT FALSE;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1 NOT NULL;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS selection VARCHAR(255) DEFAULT NULL;

ALTER TABLE comments ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;
ALTER TABLE comments ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES comments(id) ON DELETE CASCADE;
ALTER TABLE comments ADD COLUMN IF NOT EXISTS image_url TEXT DEFAULT NULL;

CREATE TABLE IF NOT EXISTS user_custom_themes (
    id VARCHAR(100) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    colors JSONB NOT NULL,
    advanced JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_passkeys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    credential_id TEXT UNIQUE NOT NULL,
    public_key TEXT NOT NULL,
    counter BIGINT NOT NULL DEFAULT 0,
    backed_up BOOLEAN DEFAULT FALSE,
    transports VARCHAR(255) DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS friend_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sender_id, receiver_id)
);

CREATE TABLE IF NOT EXISTS friends (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_a_id, user_b_id),
    CHECK (user_a_id < user_b_id)
);

CREATE TABLE IF NOT EXISTS list_email_invites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    list_id UUID NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'viewer'
      CHECK (role IN ('viewer', 'collaborator')),
    token_hash VARCHAR(255) NOT NULL,
    invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    accepted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS list_link_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    list_id UUID NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    role VARCHAR(50) NOT NULL DEFAULT 'viewer'
      CHECK (role IN ('viewer', 'collaborator')),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    max_uses INTEGER DEFAULT NULL,
    use_count INTEGER DEFAULT 0,
    revoked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE list_link_tokens ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255) DEFAULT NULL;
ALTER TABLE list_link_tokens ADD COLUMN IF NOT EXISTS token TEXT DEFAULT NULL;

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT DEFAULT '',
    metadata JSONB DEFAULT '{}',
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_notification_prefs (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    email_alerts BOOLEAN DEFAULT TRUE,
    marketing BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS friend_requests BOOLEAN DEFAULT TRUE;
ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS list_shares BOOLEAN DEFAULT TRUE;
ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS item_claims BOOLEAN DEFAULT TRUE;
ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS comments BOOLEAN DEFAULT TRUE;
ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS job_completions BOOLEAN DEFAULT TRUE;
ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS push_alerts BOOLEAN DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS user_push_subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android')),
    transport VARCHAR(20) NOT NULL CHECK (transport IN ('ntfy', 'webpush', 'fcm')),
    endpoint TEXT NOT NULL,
    endpoint_auth TEXT DEFAULT NULL,
    p256dh TEXT DEFAULT NULL,
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
);
CREATE INDEX IF NOT EXISTS idx_user_push_subscriptions_user_id ON user_push_subscriptions (user_id);

CREATE TABLE IF NOT EXISTS item_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID UNIQUE NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    summary TEXT,
    pros TEXT[] NOT NULL DEFAULT '{}',
    cons TEXT[] NOT NULL DEFAULT '{}',
    reviews JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS item_field_definitions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category VARCHAR(255) NOT NULL,
    field_key VARCHAR(255) NOT NULL,
    label VARCHAR(255) NOT NULL,
    placeholder VARCHAR(255),
    display_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE(category, field_key)
);

CREATE TABLE IF NOT EXISTS item_field_dependencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dependent_field_id UUID NOT NULL REFERENCES item_field_definitions(id) ON DELETE CASCADE,
    trigger_field_key VARCHAR(255) NOT NULL,
    trigger_value VARCHAR(255) NOT NULL,
    UNIQUE(dependent_field_id, trigger_field_key, trigger_value)
);

CREATE TABLE IF NOT EXISTS item_audiences (
    item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (item_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_item_audiences_user_id ON item_audiences(user_id);

CREATE TABLE IF NOT EXISTS item_item_related (
    item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    related_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, related_item_id),
    CHECK (item_id <> related_item_id)
);
CREATE INDEX IF NOT EXISTS idx_item_item_related_related_item_id ON item_item_related (related_item_id);

CREATE TABLE IF NOT EXISTS item_substitutions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    substitution_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('owner_approved', 'claimer_custom')),
    created_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (substitution_item_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_item_substitutions_one_claimer_custom
    ON item_substitutions (parent_item_id)
    WHERE kind = 'claimer_custom';
CREATE INDEX IF NOT EXISTS idx_item_substitutions_parent_item_id ON item_substitutions (parent_item_id);
CREATE INDEX IF NOT EXISTS idx_items_substitution_for_item_id ON items (substitution_for_item_id);

CREATE TABLE IF NOT EXISTS comment_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    username VARCHAR(100) NOT NULL,
    reaction VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(comment_id, user_id, reaction)
);

CREATE TABLE IF NOT EXISTS background_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kind VARCHAR(100) NOT NULL,
    list_id UUID REFERENCES lists(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'queued'
      CHECK (status IN ('queued', 'running', 'completed', 'failed', 'cancelled')),
    phase VARCHAR(100) NOT NULL DEFAULT 'queued',
    progress_done INTEGER NOT NULL DEFAULT 0,
    progress_total INTEGER NOT NULL DEFAULT 0,
    message TEXT DEFAULT '',
    error TEXT DEFAULT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    result JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    finished_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
);
CREATE INDEX IF NOT EXISTS idx_background_jobs_status_created
    ON background_jobs (status, created_at);
CREATE INDEX IF NOT EXISTS idx_background_jobs_list_status
    ON background_jobs (list_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS background_job_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES background_jobs(id) ON DELETE CASCADE,
    item_id UUID REFERENCES items(id) ON DELETE SET NULL,
    link_url TEXT DEFAULT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending', 'running', 'done', 'failed', 'skipped')),
    error TEXT DEFAULT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_background_job_items_job_status
    ON background_job_items (job_id, status);

CREATE TABLE IF NOT EXISTS site_policy (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    policy JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO site_policy (id, policy)
VALUES (1, '{}')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    metadata JSONB DEFAULT '{}',
    ip_address VARCHAR(64) DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS content_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_type VARCHAR(50) NOT NULL CHECK (target_type IN ('comment', 'wishlist', 'user')),
    target_id UUID NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    status VARCHAR(50) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'dismissed')),
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Reseed field definitions only when empty (matches app migration behavior)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM item_field_definitions LIMIT 1) THEN
    INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
    VALUES
      ('clothing', 'PantsSize', 'Pants Size', 'e.g. 32x30', 1),
      ('clothing', 'WaistFit', 'Waist Fit', 'e.g. Slim, Regular, Relaxed', 2),
      ('clothing', 'ShirtSize', 'Shirt Size', 'e.g. Medium, 15.5', 3),
      ('clothing', 'ShoesSize', 'Shoes Size', 'e.g. 10.5', 4),
      ('clothing', 'SocksSize', 'Socks Size', 'e.g. 9-11', 5),
      ('clothing', 'PreferredColor', 'Preferred Color', 'e.g. Navy Blue, Matte Black', 6),
      ('tech', 'ModelNumber', 'Model / Version', 'e.g. iPhone 15 Pro', 1),
      ('tech', 'StorageCapacity', 'Storage Capacity', 'e.g. 256GB, 1TB', 2),
      ('tech', 'PreferredColor', 'Preferred Color', 'e.g. Space Gray, Silver', 3);

    INSERT INTO item_field_dependencies (dependent_field_id, trigger_field_key, trigger_value)
    SELECT id, 'PantsSize', 'any'
    FROM item_field_definitions
    WHERE category = 'clothing' AND field_key = 'WaistFit';

    INSERT INTO item_field_dependencies (dependent_field_id, trigger_field_key, trigger_value)
    SELECT id, 'ModelNumber', 'any'
    FROM item_field_definitions
    WHERE category = 'tech' AND field_key = 'StorageCapacity';
  END IF;
END $$;

-- Rename legacy camelCase field keys on existing databases
UPDATE item_field_definitions SET field_key = 'PantsSize' WHERE field_key = 'pantsSize';
UPDATE item_field_definitions SET field_key = 'WaistFit' WHERE field_key = 'waistFit';
UPDATE item_field_definitions SET field_key = 'ShirtSize' WHERE field_key = 'shirtSize';
UPDATE item_field_definitions SET field_key = 'ShoesSize' WHERE field_key = 'shoesSize';
UPDATE item_field_definitions SET field_key = 'SocksSize' WHERE field_key = 'socksSize';
UPDATE item_field_definitions SET field_key = 'PreferredColor' WHERE field_key = 'preferredColor';
UPDATE item_field_definitions SET field_key = 'ModelNumber' WHERE field_key = 'modelNumber';
UPDATE item_field_definitions SET field_key = 'StorageCapacity' WHERE field_key = 'storageCapacity';

UPDATE item_field_dependencies SET trigger_field_key = 'PantsSize' WHERE trigger_field_key = 'pantsSize';
UPDATE item_field_dependencies SET trigger_field_key = 'WaistFit' WHERE trigger_field_key = 'waistFit';
UPDATE item_field_dependencies SET trigger_field_key = 'ShirtSize' WHERE trigger_field_key = 'shirtSize';
UPDATE item_field_dependencies SET trigger_field_key = 'ShoesSize' WHERE trigger_field_key = 'shoesSize';
UPDATE item_field_dependencies SET trigger_field_key = 'SocksSize' WHERE trigger_field_key = 'socksSize';
UPDATE item_field_dependencies SET trigger_field_key = 'PreferredColor' WHERE trigger_field_key = 'preferredColor';
UPDATE item_field_dependencies SET trigger_field_key = 'ModelNumber' WHERE trigger_field_key = 'modelNumber';
UPDATE item_field_dependencies SET trigger_field_key = 'StorageCapacity' WHERE trigger_field_key = 'storageCapacity';

-- Performance indexes on foreign key columns (tables above must already exist)
CREATE INDEX IF NOT EXISTS idx_user_custom_themes_user_id ON user_custom_themes(user_id);
CREATE INDEX IF NOT EXISTS idx_lists_user_id ON lists(user_id);
CREATE INDEX IF NOT EXISTS idx_list_shares_user_id ON list_shares(user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_receiver_id ON friend_requests(receiver_id);
CREATE INDEX IF NOT EXISTS idx_friends_user_b_id ON friends(user_b_id);
CREATE INDEX IF NOT EXISTS idx_list_email_invites_list_id ON list_email_invites(list_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_list_email_invites_token_hash ON list_email_invites(token_hash);
CREATE INDEX IF NOT EXISTS idx_list_link_tokens_list_id ON list_link_tokens(list_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_created_at ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_items_list_id ON items(list_id);
CREATE INDEX IF NOT EXISTS idx_item_item_links_linked_item_id ON item_item_links(linked_item_id);
CREATE INDEX IF NOT EXISTS idx_item_links_item_id ON item_links(item_id);
CREATE INDEX IF NOT EXISTS idx_claims_item_id ON claims(item_id);
CREATE INDEX IF NOT EXISTS idx_claims_user_id ON claims(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_list_id ON comments(list_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent_id ON comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_id ON audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_target_id ON audit_log(target_id);
CREATE INDEX IF NOT EXISTS idx_content_reports_reporter_id ON content_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_content_reports_target_id ON content_reports(target_id);
CREATE INDEX IF NOT EXISTS idx_content_reports_resolved_by ON content_reports(resolved_by);
