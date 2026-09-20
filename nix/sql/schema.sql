-- Giftistry PostgreSQL schema (fresh init)
-- Keep in sync with:
--   giftistry-bun/src/common/database/init-schema.ts
--   giftistry-bun/src/common/database/migrations.ts (tables not in init-schema)
-- lists.visibility is omitted to match post-migration runtime state.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    auth_hash VARCHAR(255) NOT NULL,
    bio TEXT DEFAULT '',
    theme VARCHAR(100) DEFAULT 'default',
    avatar TEXT DEFAULT NULL,
    birthday DATE DEFAULT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    email_verification_token VARCHAR(255) DEFAULT NULL,
    email_verification_expires TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(255) DEFAULT NULL,
    two_factor_recovery_codes TEXT DEFAULT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    is_owner BOOLEAN DEFAULT FALSE,
    ai_enabled BOOLEAN DEFAULT TRUE,
    web_search_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_online TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    is_onboarded BOOLEAN DEFAULT FALSE,
    oauth_sub VARCHAR(255) UNIQUE,
    is_disabled BOOLEAN DEFAULT FALSE,
    is_hidden BOOLEAN DEFAULT FALSE,
    locked_until TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    failed_login_count INTEGER DEFAULT 0,
    force_password_change BOOLEAN DEFAULT FALSE,
    login_attempts_before_lockout INTEGER DEFAULT -1,
    session_version INTEGER DEFAULT 0,
    policy_json JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE user_custom_themes (
    id VARCHAR(100) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    colors JSONB NOT NULL,
    advanced JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_passkeys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    credential_id TEXT UNIQUE NOT NULL,
    public_key TEXT NOT NULL,
    counter BIGINT NOT NULL DEFAULT 0,
    backed_up BOOLEAN DEFAULT FALSE,
    transports VARCHAR(255) DEFAULT '[]'
);

CREATE TABLE priorities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    label VARCHAR(50) NOT NULL,
    weight INTEGER NOT NULL,
    UNIQUE(user_id, label)
);

CREATE TABLE lists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,
    allow_group_funds BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    category VARCHAR(255) DEFAULT 'generic',
    reveal_suggestions BOOLEAN DEFAULT TRUE,
    ai_enabled BOOLEAN DEFAULT FALSE,
    web_search_enabled BOOLEAN DEFAULT FALSE,
    manual_job_background BOOLEAN DEFAULT TRUE,
    auto_rollover BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE list_shares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    list_id UUID REFERENCES lists(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) CHECK (role IN ('viewer', 'collaborator')),
    granted_via VARCHAR(50) DEFAULT 'direct',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(list_id, user_id)
);

CREATE TABLE friend_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sender_id, receiver_id)
);

CREATE TABLE friends (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_a_id, user_b_id),
    CHECK (user_a_id < user_b_id)
);

CREATE TABLE list_email_invites (
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

CREATE TABLE list_link_tokens (
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
    password_hash VARCHAR(255) DEFAULT NULL,
    token TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT DEFAULT '',
    metadata JSONB DEFAULT '{}',
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_notification_prefs (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    email_alerts BOOLEAN DEFAULT TRUE,
    marketing BOOLEAN DEFAULT FALSE,
    friend_requests BOOLEAN DEFAULT TRUE,
    list_shares BOOLEAN DEFAULT TRUE,
    item_claims BOOLEAN DEFAULT TRUE,
    comments BOOLEAN DEFAULT TRUE,
    job_completions BOOLEAN DEFAULT TRUE,
    push_alerts BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_push_subscriptions (
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

CREATE TABLE items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    list_id UUID REFERENCES lists(id) ON DELETE CASCADE,
    priority_id UUID REFERENCES priorities(id) ON DELETE SET NULL,
    suggested_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_hidden_idea BOOLEAN DEFAULT FALSE,
    is_suggestion BOOLEAN DEFAULT FALSE,
    category VARCHAR(100) DEFAULT 'uncategorized',
    priority INTEGER DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    desired_quantity INTEGER DEFAULT NULL,
    multi_count BOOLEAN NOT NULL DEFAULT FALSE,
    other_users_can_see BOOLEAN DEFAULT NULL,
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    variations JSONB NOT NULL DEFAULT '[]'::jsonb,
    photos JSONB NOT NULL DEFAULT '[]'::jsonb,
    allow_substitutions BOOLEAN NOT NULL DEFAULT TRUE,
    is_substitution BOOLEAN NOT NULL DEFAULT FALSE,
    substitution_for_item_id UUID NULL REFERENCES items(id) ON DELETE CASCADE
);

CREATE TABLE item_substitutions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    substitution_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('owner_approved', 'claimer_custom')),
    created_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (substitution_item_id)
);

CREATE UNIQUE INDEX idx_item_substitutions_one_claimer_custom
    ON item_substitutions (parent_item_id)
    WHERE kind = 'claimer_custom';

CREATE INDEX idx_item_substitutions_parent_item_id ON item_substitutions (parent_item_id);
CREATE INDEX idx_items_substitution_for_item_id ON items (substitution_for_item_id);

CREATE TABLE item_item_links (
    item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    linked_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, linked_item_id),
    CHECK (item_id <> linked_item_id)
);

CREATE TABLE item_item_related (
    item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    related_item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, related_item_id),
    CHECK (item_id <> related_item_id)
);

CREATE INDEX idx_item_item_related_related_item_id ON item_item_related (related_item_id);

CREATE TABLE item_audiences (
    item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (item_id, user_id)
);

CREATE INDEX idx_item_audiences_user_id ON item_audiences(user_id);

CREATE TABLE item_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID REFERENCES items(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    retailer_name VARCHAR(100),
    extracted_price DECIMAL(10, 2),
    extracted_image_url TEXT
);

CREATE TABLE claims (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID REFERENCES items(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2),
    claimed_by_name VARCHAR(100),
    anonymous BOOLEAN DEFAULT FALSE,
    quantity INTEGER DEFAULT 1 NOT NULL,
    selection VARCHAR(255) DEFAULT NULL,
    claimed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    list_id UUID REFERENCES lists(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    commenter_name VARCHAR(100) NOT NULL,
    content TEXT NOT NULL,
    is_owner_visible BOOLEAN DEFAULT TRUE,
    is_rollover BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    image_url TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE comment_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    username VARCHAR(100) NOT NULL,
    reaction VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(comment_id, user_id, reaction)
);

CREATE TABLE item_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID UNIQUE NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    summary TEXT,
    pros TEXT[] NOT NULL DEFAULT '{}',
    cons TEXT[] NOT NULL DEFAULT '{}',
    reviews JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE item_field_definitions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category VARCHAR(255) NOT NULL,
    field_key VARCHAR(255) NOT NULL,
    label VARCHAR(255) NOT NULL,
    placeholder VARCHAR(255),
    display_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE(category, field_key)
);

CREATE TABLE item_field_dependencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dependent_field_id UUID NOT NULL REFERENCES item_field_definitions(id) ON DELETE CASCADE,
    trigger_field_key VARCHAR(255) NOT NULL,
    trigger_value VARCHAR(255) NOT NULL,
    UNIQUE(dependent_field_id, trigger_field_key, trigger_value)
);

-- Seed dynamic item field definitions
INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('clothing', 'PantsSize', 'Pants Size', 'e.g. 32x30', 1);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('clothing', 'WaistFit', 'Waist Fit', 'e.g. Slim, Regular, Relaxed', 2);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('clothing', 'ShirtSize', 'Shirt Size', 'e.g. Medium, 15.5', 3);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('clothing', 'ShoesSize', 'Shoes Size', 'e.g. 10.5', 4);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('clothing', 'SocksSize', 'Socks Size', 'e.g. 9-11', 5);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('clothing', 'PreferredColor', 'Preferred Color', 'e.g. Navy Blue, Matte Black', 6);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('tech', 'ModelNumber', 'Model / Version', 'e.g. iPhone 15 Pro', 1);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('tech', 'StorageCapacity', 'Storage Capacity', 'e.g. 256GB, 1TB', 2);

INSERT INTO item_field_definitions (category, field_key, label, placeholder, display_order)
VALUES ('tech', 'PreferredColor', 'Preferred Color', 'e.g. Space Gray, Silver', 3);

INSERT INTO item_field_dependencies (dependent_field_id, trigger_field_key, trigger_value)
SELECT id, 'PantsSize', 'any'
FROM item_field_definitions
WHERE category = 'clothing' AND field_key = 'WaistFit';

INSERT INTO item_field_dependencies (dependent_field_id, trigger_field_key, trigger_value)
SELECT id, 'ModelNumber', 'any'
FROM item_field_definitions
WHERE category = 'tech' AND field_key = 'StorageCapacity';

CREATE TABLE background_jobs (
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

CREATE INDEX idx_background_jobs_status_created
    ON background_jobs (status, created_at);

CREATE INDEX idx_background_jobs_list_status
    ON background_jobs (list_id, status, created_at DESC);

CREATE TABLE background_job_items (
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

CREATE INDEX idx_background_job_items_job_status
    ON background_job_items (job_id, status);

-- Migration-only tables (not in init-schema.ts CREATE path)
CREATE TABLE site_policy (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    policy JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO site_policy (id, policy)
VALUES (1, '{}')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    metadata JSONB DEFAULT '{}',
    ip_address VARCHAR(64) DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE content_reports (
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

-- Performance indexes on foreign key columns (after all tables exist)
CREATE INDEX IF NOT EXISTS idx_user_custom_themes_user_id ON user_custom_themes(user_id);
CREATE INDEX IF NOT EXISTS idx_lists_user_id ON lists(user_id);
CREATE INDEX IF NOT EXISTS idx_list_shares_user_id ON list_shares(user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_receiver_id ON friend_requests(receiver_id);
CREATE INDEX IF NOT EXISTS idx_friends_user_b_id ON friends(user_b_id);
CREATE INDEX IF NOT EXISTS idx_list_email_invites_list_id ON list_email_invites(list_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_list_email_invites_token_hash ON list_email_invites(token_hash);
CREATE INDEX IF NOT EXISTS idx_list_link_tokens_list_id ON list_link_tokens(list_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_created_at ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_push_subscriptions_user_id ON user_push_subscriptions(user_id);
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
