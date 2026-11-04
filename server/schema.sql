CREATE TABLE IF NOT EXISTS tyri_devices (
 environment text NOT NULL, key_id text NOT NULL, public_key text NOT NULL,
 receipt text NOT NULL, proof_hash text NOT NULL, counter bigint NOT NULL DEFAULT 0 CHECK(counter>=0),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(environment,key_id)
);
CREATE TABLE IF NOT EXISTS tyri_challenges (
 id uuid PRIMARY KEY, environment text NOT NULL, key_id text NOT NULL,
 purpose text NOT NULL CHECK(purpose IN ('enroll','create')), challenge text NOT NULL,
 expires_at timestamptz NOT NULL, consumed boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS tyri_challenge_expiry ON tyri_challenges(expires_at);
CREATE TABLE IF NOT EXISTS tyri_budgets (
 environment text NOT NULL, scope text NOT NULL, bucket text NOT NULL,
 count integer NOT NULL CHECK(count>0), created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(environment,scope,bucket)
);
