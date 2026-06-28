const fs = require("fs");
const path = require("path");
const { createPool } = require("./db");
const {
  generateSessionToken,
  hashSessionToken,
  safeSessionID,
  safeUserID,
} = require("./sessionCrypto");
const { sessionTTLDays } = require("./authConfig");

function publicUser(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    email: row.email || null,
    full_name: row.full_name || null,
  };
}

function createSessionStore({
  databaseUrl = process.env.DATABASE_URL,
  pool = null,
  ttlDays = sessionTTLDays(),
} = {}) {
  const dbPool = pool || createPool(databaseUrl);

  async function ensureSchema() {
    const sql = fs.readFileSync(
      path.join(__dirname, "migrations", "002_create_auth_tables.sql"),
      "utf8"
    );

    await dbPool.query(sql);
  }

  async function findOrCreateAppleUser({ appleSub, email = null, fullName = null }) {
    if (!appleSub) {
      throw new Error("appleSub is required.");
    }

    const existing = await dbPool.query(
      `SELECT id, email, full_name
         FROM users
        WHERE apple_sub = $1
          AND deleted_at IS NULL
        LIMIT 1`,
      [appleSub]
    );

    if (existing.rows[0]) {
      const updated = await dbPool.query(
        `UPDATE users
            SET email = COALESCE($2, email),
                full_name = COALESCE($3, full_name),
                last_login_at = now(),
                updated_at = now()
          WHERE id = $1
          RETURNING id, email, full_name`,
        [existing.rows[0].id, email, fullName]
      );

      return publicUser(updated.rows[0]);
    }

    const inserted = await dbPool.query(
      `INSERT INTO users (id, apple_sub, email, full_name, last_login_at, updated_at)
       VALUES ($1, $2, $3, $4, now(), now())
       RETURNING id, email, full_name`,
      [safeUserID(), appleSub, email, fullName]
    );

    return publicUser(inserted.rows[0]);
  }

  async function getUserByID(userId) {
    const result = await dbPool.query(
      `SELECT id, email, full_name
         FROM users
        WHERE id = $1
          AND deleted_at IS NULL
        LIMIT 1`,
      [userId]
    );

    return publicUser(result.rows[0]);
  }

  async function createSession(userId, { userAgent = null, ipHash = null } = {}) {
    if (!userId) {
      throw new Error("userId is required for session creation.");
    }

    const token = generateSessionToken();
    const tokenHash = hashSessionToken(token);
    const expiresAt = new Date(Date.now() + ttlDays * 24 * 60 * 60 * 1000);

    const result = await dbPool.query(
      `INSERT INTO user_sessions (
         id,
         user_id,
         token_hash,
         expires_at,
         user_agent,
         ip_hash
       ) VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING expires_at`,
      [
        safeSessionID(),
        userId,
        tokenHash,
        expiresAt.toISOString(),
        userAgent,
        ipHash,
      ]
    );

    return {
      token,
      expiresAt: result.rows[0].expires_at?.toISOString?.() || result.rows[0].expires_at,
      tokenHash,
    };
  }

  async function getSessionByToken(token) {
    const tokenHash = hashSessionToken(token);
    const result = await dbPool.query(
      `SELECT s.id AS session_id,
              s.user_id,
              s.expires_at,
              u.id,
              u.email,
              u.full_name
         FROM user_sessions s
         JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = $1
          AND s.revoked_at IS NULL
          AND s.expires_at > now()
          AND u.deleted_at IS NULL
        LIMIT 1`,
      [tokenHash]
    );

    const row = result.rows[0];

    if (!row) {
      return null;
    }

    await dbPool.query(
      `UPDATE user_sessions
          SET last_used_at = now()
        WHERE id = $1`,
      [row.session_id]
    );

    return {
      session: {
        id: row.session_id,
        user_id: row.user_id,
        expires_at: row.expires_at?.toISOString?.() || row.expires_at,
      },
      user: publicUser(row),
    };
  }

  async function revokeSessionToken(token) {
    const tokenHash = hashSessionToken(token);

    await dbPool.query(
      `UPDATE user_sessions
          SET revoked_at = now()
        WHERE token_hash = $1
          AND revoked_at IS NULL`,
      [tokenHash]
    );
  }

  async function revokeAllSessionsForUser(userId) {
    if (!userId) {
      throw new Error("userId is required for session revocation.");
    }

    const result = await dbPool.query(
      `UPDATE user_sessions
          SET revoked_at = now()
        WHERE user_id = $1
          AND revoked_at IS NULL`,
      [userId]
    );

    return result.rowCount || 0;
  }

  async function softDeleteUser(userId) {
    if (!userId) {
      throw new Error("userId is required for account deletion.");
    }

    const result = await dbPool.query(
      `UPDATE users
          SET deleted_at = now(),
              updated_at = now(),
              apple_sub = NULL,
              email = NULL,
              full_name = NULL
        WHERE id = $1
          AND deleted_at IS NULL`,
      [userId]
    );

    return (result.rowCount || 0) > 0;
  }

  async function close() {
    if (!pool) {
      await dbPool.end();
    }
  }

  return {
    ensureSchema,
    findOrCreateAppleUser,
    getSessionByToken,
    getUserByID,
    createSession,
    revokeSessionToken,
    revokeAllSessionsForUser,
    softDeleteUser,
    close,
  };
}

module.exports = {
  createSessionStore,
  publicUser,
};
