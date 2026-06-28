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
    const sql = fs.readFileSync(
      path.join(__dirname, "migrations", "001_create_plaid_item_store.sql"),
      "utf8"
    );

    await dbPool.query(sql);
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
              created_at, updated_at
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
         disconnected_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now(), now(), NULL)
       ON CONFLICT (user_id, plaid_item_id)
       DO UPDATE SET
         institution_id = EXCLUDED.institution_id,
         institution_name = EXCLUDED.institution_name,
         encrypted_access_token = EXCLUDED.encrypted_access_token,
         access_token_iv = EXCLUDED.access_token_iv,
         access_token_tag = EXCLUDED.access_token_tag,
         updated_at = now(),
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
    close,
  };
}

module.exports = {
  createPostgresPlaidItemStore,
};
