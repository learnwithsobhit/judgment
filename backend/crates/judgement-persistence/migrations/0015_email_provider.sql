-- Email/password accounts are their own identity. Older providers stay valid.
ALTER TABLE user_identities DROP CONSTRAINT IF EXISTS user_identities_provider_check;
ALTER TABLE user_identities
    ADD CONSTRAINT user_identities_provider_check
    CHECK (provider IN ('google', 'facebook', 'telegram', 'email'));
