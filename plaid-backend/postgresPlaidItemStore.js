const fs = require("fs");
const path = require("path");
const { createPool } = require("./db");
const { decryptToken, encryptToken, decodeEncryptionKey } = require("./tokenCrypto");
const {
  normalizeLinkedItem,
  stableLegacyItemID,
  stablePlaidItemRowID,
} = require("./plaidItemUtils");

function createPostgresPlaidItemStore({
  databaseUrl = process.env.DATABASE_URL,
  tokenEncryptionKey = process.env.TOKEN_ENCRYPTION_KEY,
  pool = null,
} = {}) {
  decodeEncryptionKey(tokenEncryptionKey);

  const dbPool = pool || createPool(databaseUrl);

  async function ensureSchema() {
    for (const migration of [
      "001_create_plaid_item_store.sql",
      "003_transaction_readiness.sql",
    ]) {
      const sql = fs.readFileSync(
        path.join(__dirname, "migrations", migration), "utf8"
      );
      await dbPool.query(sql);
    }
  }

  async function ensureUser(userId) {
    if (!userId) {
      throw new Error("userId is required for Plaid item storage.");
    }

    await dbPool.query(
      `INSERT INTO users (id)
       VALUES ($1)
       ON CONFLICT (id)
       DO UPDATE SET updated_at = now()`,
      [userId]
    );
  }

  async function getUserItems(userId) {
    const result = await dbPool.query(
      `SELECT plaid_item_id, institution_id, institution_name,
              encrypted_access_token, access_token_iv, access_token_tag,
              created_at, updated_at, historical_ready_at,
              historical_recovery_started_at
         FROM plaid_items
        WHERE user_id = $1
          AND disconnected_at IS NULL
        ORDER BY created_at ASC`,
      [userId]
    );

    return result.rows.map((row) => ({
      accessToken: decryptToken(
        {
          ciphertext: row.encrypted_access_token,
          iv: row.access_token_iv,
          tag: row.access_token_tag,
        },
        tokenEncryptionKey
      ),
      itemId: row.plaid_item_id,
      institutionName: row.institution_name,
      institutionId: row.institution_id,
      linkedAt: row.created_at?.toISOString?.() || row.created_at,
      updatedAt: row.updated_at?.toISOString?.() || row.updated_at,
      historicalReadyAt: row.historical_ready_at?.toISOString?.() || null,
      historicalRecoveryStartedAt:
        row.historical_recovery_started_at?.toISOString?.() || null,
    }));
  }

  async function saveUserItem(userId, item) {
    const normalizedItem = normalizeLinkedItem(item);

    if (!normalizedItem) {
      return getUserItemCount(userId);
    }

    const plaidItemId = stableLegacyItemID(normalizedItem);
    const encryptedToken = encryptToken(normalizedItem.accessToken, tokenEncryptionKey);

    await ensureUser(userId);

    await dbPool.query(
      `INSERT INTO plaid_items (
         id,
         user_id,
         plaid_item_id,
         institution_id,
         institution_name,
         encrypted_access_token,
         access_token_iv,
         access_token_tag,
         created_at,
         updated_at,
         disconnected_at,
         historical_ready_at,
         historical_recovery_started_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now(), now(), NULL, NULL, NULL)
       ON CONFLICT (user_id, plaid_item_id)
       DO UPDATE SET
         institution_id = EXCLUDED.institution_id,
         institution_name = EXCLUDED.institution_name,
         encrypted_access_token = EXCLUDED.encrypted_access_token,
         access_token_iv = EXCLUDED.access_token_iv,
         access_token_tag = EXCLUDED.access_token_tag,
         created_at = CASE
           WHEN plaid_items.disconnected_at IS NULL
             THEN plaid_items.created_at ELSE now() END,
         updated_at = now(),
         historical_ready_at = CASE
           WHEN plaid_items.disconnected_at IS NULL
             THEN plaid_items.historical_ready_at ELSE NULL END,
         historical_recovery_started_at = CASE
           WHEN plaid_items.disconnected_at IS NULL
             THEN plaid_items.historical_recovery_started_at ELSE NULL END,
         disconnected_at = NULL`,
      [
        stablePlaidItemRowID(userId, plaidItemId),
        userId,
        plaidItemId,
        normalizedItem.institutionId,
        normalizedItem.institutionName,
        encryptedToken.ciphertext,
        encryptedToken.iv,
        encryptedToken.tag,
      ]
    );

    return getUserItemCount(userId);
  }

  async function removeUserItem(userId, itemId) {
    if (!itemId) {
      return getUserItemCount(userId);
    }

    await dbPool.query(
      `UPDATE plaid_items
          SET disconnected_at = now(),
              updated_at = now()
        WHERE user_id = $1
          AND plaid_item_id = $2
          AND disconnected_at IS NULL`,
      [userId, itemId]
    );

    return getUserItemCount(userId);
  }

  async function removeAllUserItems(userId) {
    await dbPool.query(
      `UPDATE plaid_items
          SET disconnected_at = now(),
              updated_at = now()
        WHERE user_id = $1
          AND disconnected_at IS NULL`,
      [userId]
    );
  }

  async function getUserItemCount(userId) {
    const result = await dbPool.query(
      `SELECT count(*)::int AS count
         FROM plaid_items
        WHERE user_id = $1
          AND disconnected_at IS NULL`,
      [userId]
    );

    return result.rows[0]?.count || 0;
  }

  async function getUserItemReadiness(userId, itemId) {
    const result = await dbPool.query(
      `SELECT historical_ready_at, historical_recovery_started_at
         FROM plaid_items
        WHERE user_id = $1 AND plaid_item_id = $2
          AND disconnected_at IS NULL`,
      [userId, itemId]
    );
    const row = result.rows[0];
    return row ? {
      historicalReadyAt: row.historical_ready_at?.toISOString?.() || null,
      historicalRecoveryStartedAt:
        row.historical_recovery_started_at?.toISOString?.() || null,
    } : null;
  }

  async function markHistoricalReadyByItemID(itemId, at) {
    const connection = await dbPool.connect();
    try {
      await connection.query("BEGIN");
      const matches = await connection.query(
        `SELECT id, created_at FROM plaid_items
          WHERE plaid_item_id = $1 AND disconnected_at IS NULL
          FOR UPDATE`,
        [itemId]
      );
      if (matches.rows.length !== 1 ||
          !Number.isFinite(Date.parse(at)) ||
          matches.rows[0].created_at > new Date(at)) {
        await connection.query("ROLLBACK");
        return false;
      }
      await connection.query(
        `UPDATE plaid_items
            SET historical_ready_at = COALESCE(historical_ready_at, $2)
          WHERE id = $1 AND disconnected_at IS NULL`,
        [matches.rows[0].id, at]
      );
      await connection.query("COMMIT");
      return true;
    } catch (error) {
      await connection.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      connection.release();
    }
  }

  async function markHistoricalReadyForUserItem(userId, expectedItem, at) {
    if (!userId || !expectedItem?.itemId ||
        !Number.isFinite(Date.parse(at))) {
      return null;
    }
    const connection = await dbPool.connect();
    try {
      await connection.query("BEGIN");
      const matches = await connection.query(
        `SELECT id, user_id, created_at, historical_ready_at,
                encrypted_access_token, access_token_iv, access_token_tag
           FROM plaid_items
          WHERE plaid_item_id = $1 AND disconnected_at IS NULL
          FOR UPDATE`,
        [expectedItem.itemId]
      );
      const row = matches.rows[0];
      if (matches.rows.length !== 1 || row.user_id !== userId ||
          row.created_at.toISOString() !== expectedItem.linkedAt ||
          row.created_at > new Date(at) ||
          decryptToken({
            ciphertext: row.encrypted_access_token,
            iv: row.access_token_iv,
            tag: row.access_token_tag,
          }, tokenEncryptionKey) !== expectedItem.accessToken) {
        await connection.query("ROLLBACK");
        return null;
      }
      const result = await connection.query(
        `UPDATE plaid_items
            SET historical_ready_at = COALESCE(historical_ready_at, $2)
          WHERE id = $1 AND disconnected_at IS NULL
          RETURNING historical_ready_at`,
        [row.id, at]
      );
      await connection.query("COMMIT");
      return result.rows[0]?.historical_ready_at?.toISOString?.() || null;
    } catch (error) {
      await connection.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      connection.release();
    }
  }

  async function markHistoricalRecoveryStarted(userId, itemId, at) {
    const result = await dbPool.query(
      `UPDATE plaid_items
          SET historical_recovery_started_at = $3
        WHERE user_id = $1 AND plaid_item_id = $2
          AND disconnected_at IS NULL
        RETURNING id`,
      [userId, itemId, at]
    );
    return result.rowCount === 1;
  }

  async function close() {
    if (!pool) {
      await dbPool.end();
    }
  }

  return {
    driver: "postgres",
    ensureSchema,
    ensureUser,
    getUserItems,
    saveUserItem,
    removeUserItem,
    removeAllUserItems,
    getUserItemCount,
    getUserItemReadiness,
    markHistoricalReadyByItemID,
    markHistoricalReadyForUserItem,
    markHistoricalRecoveryStarted,
    close,
  };
}

module.exports = {
  createPostgresPlaidItemStore,
};
