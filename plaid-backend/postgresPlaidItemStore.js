const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
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
      "004_item_lifecycle.sql",
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
      `INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`,
      [userId]
    );
  }

  async function withLockedUser(userId, work) {
    const connection = await dbPool.connect();
    try {
      await connection.query("BEGIN");
      await connection.query(
        `INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`,
        [userId]
      );
      const result = await connection.query(
        `SELECT item_lifecycle_generation, item_lifecycle_state, deleted_at
           FROM users WHERE id = $1 FOR UPDATE`, [userId]
      );
      const value = await work(connection, result.rows[0]);
      await connection.query("COMMIT");
      return value;
    } catch (error) {
      await connection.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      connection.release();
    }
  }

  async function beginItemExchange(userId, context = {}) {
    return withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active") {
        throw new Error("item_lifecycle_unavailable");
      }
      const lease = { id: crypto.randomUUID(),
        generation: Number(owner.item_lifecycle_generation) };
      await connection.query(
        `INSERT INTO plaid_item_exchange_leases
         (id, user_id, generation, public_token_sha256, link_session_id)
         VALUES ($1, $2, $3, $4, $5)`,
        [lease.id, userId, lease.generation,
          context.publicToken ? crypto.createHash("sha256")
            .update(context.publicToken).digest("hex") : null,
          context.linkSessionId || null]
      );
      return lease;
    });
  }

  async function markItemExchangeDispatched(userId, lease) {
    await withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
          Number(owner.item_lifecycle_generation) !== lease.generation) {
        throw new Error("item_exchange_lease_changed");
      }
      const result = await connection.query(
        `UPDATE plaid_item_exchange_leases SET state = 'dispatch_uncertain'
           WHERE id = $1 AND user_id = $2 AND generation = $3
             AND state = 'prepared'`, [lease.id, userId, lease.generation]);
      if (result.rowCount !== 1) throw new Error("item_exchange_lease_changed");
    });
  }

  async function recordItemExchangeResult(userId, lease, item, requestId = null) {
    if (!item.itemId || !item.accessToken) {
      throw new Error("item_exchange_lease_changed");
    }
    const encrypted = encryptToken(item.accessToken, tokenEncryptionKey);
    await withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
          Number(owner.item_lifecycle_generation) !== lease.generation) {
        throw new Error("item_exchange_lease_changed");
      }
      const result = await connection.query(
        `UPDATE plaid_item_exchange_leases SET state = 'result_recorded',
           plaid_item_id = $4, encrypted_access_token = $5,
           access_token_iv = $6, access_token_tag = $7,
           provider_request_id = $8
           WHERE id = $1 AND user_id = $2 AND generation = $3
             AND state = 'dispatch_uncertain'`,
        [lease.id, userId, lease.generation, item.itemId,
          encrypted.ciphertext, encrypted.iv, encrypted.tag, requestId]);
      if (result.rowCount !== 1) throw new Error("item_exchange_lease_changed");
    });
  }

  async function markItemExchangeRemovalConfirmed(userId, lease, item,
    removalRequestId, recoveryId = null) {
    if (!removalRequestId) throw new Error("item_exchange_resolution_unverified");
    await withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
          Number(owner.item_lifecycle_generation) !== lease.generation) {
        throw new Error("item_exchange_lease_changed");
      }
      const result = await connection.query(
        `SELECT plaid_item_id, encrypted_access_token, access_token_iv,
                access_token_tag, state FROM plaid_item_exchange_leases
           WHERE id = $1 AND user_id = $2 AND generation = $3
             AND state IN ('result_recorded', 'dispatch_uncertain')`,
        [lease.id, userId, lease.generation]);
      if (result.rowCount !== 1) {
        throw new Error("item_exchange_resolution_unverified");
      }
      let source = result.rows[0];
      if (source.state === "dispatch_uncertain" && recoveryId) {
        const recovery = await connection.query(
          `SELECT plaid_item_id, encrypted_access_token, access_token_iv,
                  access_token_tag FROM plaid_item_removal_recoveries
             WHERE id = $1 AND user_id = $2 AND exchange_lease_id = $3`,
          [recoveryId, userId, lease.id]);
        if (recovery.rowCount !== 1) {
          throw new Error("item_exchange_resolution_unverified");
        }
        source = recovery.rows[0];
      } else if (source.state !== "result_recorded") {
        throw new Error("item_exchange_resolution_unverified");
      }
      if (source.plaid_item_id !== item.itemId ||
          decryptToken({ ciphertext: source.encrypted_access_token,
            iv: source.access_token_iv,
            tag: source.access_token_tag }, tokenEncryptionKey) !== item.accessToken) {
        throw new Error("item_exchange_resolution_unverified");
      }
      await connection.query(
        `UPDATE plaid_item_exchange_leases
            SET state = 'removal_confirmed', removal_request_id = $4,
                plaid_item_id = $5, encrypted_access_token = $6,
                access_token_iv = $7, access_token_tag = $8
          WHERE id = $1 AND user_id = $2 AND generation = $3`,
        [lease.id, userId, lease.generation, removalRequestId,
          item.itemId, source.encrypted_access_token, source.access_token_iv,
          source.access_token_tag]);
    });
  }

  async function getItemExchangeLeases(userId) {
    const result = await dbPool.query(
      `SELECT id, generation, state, public_token_sha256, link_session_id,
              plaid_item_id, encrypted_access_token, access_token_iv,
              access_token_tag, provider_request_id, removal_request_id,
              created_at
         FROM plaid_item_exchange_leases WHERE user_id = $1 ORDER BY created_at`,
      [userId]);
    return result.rows.map((row) => ({ id: row.id,
      generation: Number(row.generation), state: row.state,
      publicTokenSHA256: row.public_token_sha256,
      linkSessionId: row.link_session_id, itemId: row.plaid_item_id,
      providerRequestId: row.provider_request_id,
      removalRequestId: row.removal_request_id,
      accessToken: row.encrypted_access_token ? decryptToken({
        ciphertext: row.encrypted_access_token, iv: row.access_token_iv,
        tag: row.access_token_tag }, tokenEncryptionKey) : null,
      createdAt: row.created_at?.toISOString?.() || row.created_at }));
  }

  async function finishItemExchange(userId, lease, resolution) {
    await withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
          Number(owner.item_lifecycle_generation) !== lease.generation) {
        throw new Error("item_exchange_lease_changed");
      }
      const result = await connection.query(
        `SELECT plaid_item_id, encrypted_access_token, access_token_iv,
                access_token_tag, state, removal_request_id
           FROM plaid_item_exchange_leases
           WHERE id = $1 AND user_id = $2 AND generation = $3`,
        [lease.id, userId, lease.generation]);
      if (result.rowCount !== 1) throw new Error("item_exchange_lease_changed");
      const entry = result.rows[0];
      const item = resolution?.item;
      if (!item?.itemId || !item?.accessToken ||
          (entry.plaid_item_id && entry.plaid_item_id !== item.itemId) ||
          (entry.encrypted_access_token && decryptToken({
            ciphertext: entry.encrypted_access_token, iv: entry.access_token_iv,
            tag: entry.access_token_tag }, tokenEncryptionKey) !== item.accessToken)) {
        throw new Error("item_exchange_resolution_unverified");
      }
      let persisted;
      if (resolution.kind === "saved") {
        if (entry.state !== "item_saved") {
          throw new Error("item_exchange_resolution_unverified");
        }
        persisted = await connection.query(
          `SELECT encrypted_access_token, access_token_iv, access_token_tag
             FROM plaid_items WHERE user_id = $1 AND plaid_item_id = $2
               AND disconnected_at IS NULL`, [userId, item.itemId]);
      } else if (resolution.kind === "recovery") {
        persisted = await connection.query(
          `SELECT encrypted_access_token, access_token_iv, access_token_tag
             FROM plaid_item_removal_recoveries
            WHERE user_id = $1 AND id = $2 AND plaid_item_id = $3
              AND exchange_lease_id = $4`,
          [userId, resolution.recoveryId, item.itemId, lease.id]);
      } else if (resolution.kind === "removed") {
        if (entry.state !== "removal_confirmed" || !entry.removal_request_id) {
          throw new Error("item_exchange_resolution_unverified");
        }
      } else {
        throw new Error("item_exchange_resolution_unverified");
      }
      if (persisted && (persisted.rowCount !== 1 || decryptToken({
        ciphertext: persisted.rows[0].encrypted_access_token,
        iv: persisted.rows[0].access_token_iv,
        tag: persisted.rows[0].access_token_tag }, tokenEncryptionKey) !== item.accessToken)) {
        throw new Error("item_exchange_resolution_unverified");
      }
      const removed = await connection.query(
        `DELETE FROM plaid_item_exchange_leases
           WHERE id = $1 AND user_id = $2 AND generation = $3`,
        [lease.id, userId, lease.generation]);
      if (removed.rowCount !== 1) throw new Error("item_exchange_lease_changed");
    });
  }

  async function beginItemRemoval(userId, purpose) {
    if (!["disconnecting", "deleting"].includes(purpose)) {
      throw new Error("Invalid Item removal purpose.");
    }
    return withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active") {
        throw new Error("item_lifecycle_unavailable");
      }
      const obligations = await connection.query(
        `SELECT (SELECT count(*)::int FROM plaid_item_exchange_leases
                   WHERE user_id = $1) AS exchanges,
                (SELECT count(*)::int FROM plaid_item_removal_recoveries
                   WHERE user_id = $1) AS recoveries`, [userId]
      );
      if (obligations.rows[0].exchanges || obligations.rows[0].recoveries) {
        throw new Error("item_lifecycle_busy");
      }
      const result = await connection.query(
        `UPDATE users SET item_lifecycle_generation = item_lifecycle_generation + 1,
                 item_lifecycle_state = $2, updated_at = now()
           WHERE id = $1 RETURNING item_lifecycle_generation`,
        [userId, purpose]
      );
      return Number(result.rows[0].item_lifecycle_generation);
    });
  }

  async function finishItemRemoval(userId, generation, purpose, deleted = false) {
    const result = await dbPool.query(
      `UPDATE users SET item_lifecycle_state = $4, updated_at = now()
         WHERE id = $1 AND item_lifecycle_generation = $2
           AND item_lifecycle_state = $3`,
      [userId, generation, purpose, deleted ? "deleted" : "active"]
    );
    if (result.rowCount !== 1) throw new Error("item_lifecycle_changed");
  }

  async function getItemLifecycleObligations(userId) {
    const result = await dbPool.query(
      `SELECT (SELECT count(*)::int FROM plaid_item_exchange_leases
                 WHERE user_id = $1) AS pending_exchanges,
              (SELECT count(*)::int FROM plaid_item_removal_recoveries
                 WHERE user_id = $1) AS removal_recoveries`, [userId]
    );
    return {
      pendingExchanges: result.rows[0].pending_exchanges,
      removalRecoveries: result.rows[0].removal_recoveries,
    };
  }

  async function recordRemovalRecovery(userId, item, lease = null) {
    const encrypted = encryptToken(item.accessToken, tokenEncryptionKey);
    const id = crypto.randomUUID();
    const insert = async (connection) => connection.query(
      `INSERT INTO plaid_item_removal_recoveries
       (id, user_id, plaid_item_id, encrypted_access_token,
        access_token_iv, access_token_tag, exchange_lease_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, userId, item.itemId, encrypted.ciphertext, encrypted.iv, encrypted.tag,
        lease?.id || null]);
    if (lease) {
      await withLockedUser(userId, async (connection, owner) => {
        if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
            Number(owner.item_lifecycle_generation) !== lease.generation) {
          throw new Error("item_exchange_lease_changed");
        }
        const result = await connection.query(
          `SELECT plaid_item_id FROM plaid_item_exchange_leases
            WHERE id = $1 AND user_id = $2 AND generation = $3`,
          [lease.id, userId, lease.generation]);
        if (result.rowCount !== 1 ||
            (result.rows[0].plaid_item_id &&
              result.rows[0].plaid_item_id !== item.itemId)) {
          throw new Error("item_exchange_lease_changed");
        }
        await insert(connection);
      });
    } else {
      await insert(dbPool);
    }
    return id;
  }

  async function clearRemovalRecovery(userId, id) {
    await dbPool.query(
      `DELETE FROM plaid_item_removal_recoveries WHERE user_id = $1 AND id = $2`,
      [userId, id]
    );
  }

  async function getRemovalRecoveries(userId) {
    const result = await dbPool.query(
      `SELECT id, plaid_item_id, encrypted_access_token,
              access_token_iv, access_token_tag, exchange_lease_id, created_at
         FROM plaid_item_removal_recoveries WHERE user_id = $1
         ORDER BY created_at`, [userId]
    );
    return result.rows.map((row) => ({
      id: row.id, itemId: row.plaid_item_id,
      accessToken: decryptToken({ ciphertext: row.encrypted_access_token,
        iv: row.access_token_iv, tag: row.access_token_tag }, tokenEncryptionKey),
      exchangeLeaseId: row.exchange_lease_id,
      createdAt: row.created_at?.toISOString?.() || row.created_at,
    }));
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

  async function saveUserItem(userId, item, lease = null) {
    const normalizedItem = normalizeLinkedItem(item);

    if (!normalizedItem) {
      return getUserItemCount(userId);
    }

    const plaidItemId = stableLegacyItemID(normalizedItem);
    const encryptedToken = encryptToken(normalizedItem.accessToken, tokenEncryptionKey);

    return withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
          (lease && Number(owner.item_lifecycle_generation) !== lease.generation)) {
        throw new Error("item_lifecycle_unavailable");
      }
      if (lease) {
        const leaseResult = await connection.query(
          `SELECT state, plaid_item_id, encrypted_access_token,
                  access_token_iv, access_token_tag
             FROM plaid_item_exchange_leases
            WHERE id = $1 AND user_id = $2 AND generation = $3`,
          [lease.id, userId, lease.generation]
        );
        if (leaseResult.rowCount !== 1) throw new Error("item_lifecycle_unavailable");
        const currentLease = leaseResult.rows[0];
        if (!["dispatch_uncertain", "result_recorded"].includes(currentLease.state) ||
            (currentLease.plaid_item_id && currentLease.plaid_item_id !== plaidItemId) ||
            (currentLease.encrypted_access_token && decryptToken({
              ciphertext: currentLease.encrypted_access_token,
              iv: currentLease.access_token_iv,
              tag: currentLease.access_token_tag,
            }, tokenEncryptionKey) !== normalizedItem.accessToken)) {
          throw new Error("item_lifecycle_unavailable");
        }
      }
      await connection.query(
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
      if (lease) {
        const marked = await connection.query(
          `UPDATE plaid_item_exchange_leases
              SET state = 'item_saved', plaid_item_id = $4,
                  encrypted_access_token = $5, access_token_iv = $6,
                  access_token_tag = $7
            WHERE id = $1 AND user_id = $2 AND generation = $3
              AND state IN ('dispatch_uncertain', 'result_recorded')`,
          [lease.id, userId, lease.generation, plaidItemId,
            encryptedToken.ciphertext, encryptedToken.iv, encryptedToken.tag]);
        if (marked.rowCount !== 1) throw new Error("item_lifecycle_unavailable");
      }
      const count = await connection.query(
        `SELECT count(*)::int AS count FROM plaid_items
          WHERE user_id = $1 AND disconnected_at IS NULL`, [userId]);
      return count.rows[0].count;
    });
  }

  async function inspectItemExchangeSave(userId, lease, item) {
    return withLockedUser(userId, async (connection, owner) => {
      if (owner.deleted_at || owner.item_lifecycle_state !== "active" ||
          Number(owner.item_lifecycle_generation) !== lease.generation ||
          !item?.itemId || !item?.accessToken) {
        return { outcome: "unknown" };
      }
      const leaseResult = await connection.query(
        `SELECT state, plaid_item_id, encrypted_access_token,
                access_token_iv, access_token_tag
           FROM plaid_item_exchange_leases
          WHERE id = $1 AND user_id = $2 AND generation = $3`,
        [lease.id, userId, lease.generation]);
      if (leaseResult.rowCount !== 1) return { outcome: "unknown" };
      const entry = leaseResult.rows[0];
      if ((entry.plaid_item_id && entry.plaid_item_id !== item.itemId) ||
          (entry.encrypted_access_token && decryptToken({
            ciphertext: entry.encrypted_access_token, iv: entry.access_token_iv,
            tag: entry.access_token_tag }, tokenEncryptionKey) !== item.accessToken)) {
        return { outcome: "unknown" };
      }
      const currentResult = await connection.query(
        `SELECT encrypted_access_token, access_token_iv, access_token_tag
           FROM plaid_items WHERE user_id = $1 AND plaid_item_id = $2
             AND disconnected_at IS NULL`, [userId, item.itemId]);
      const current = currentResult.rows[0];
      if (entry.state === "item_saved") {
        if (!current || decryptToken({
          ciphertext: current.encrypted_access_token, iv: current.access_token_iv,
          tag: current.access_token_tag }, tokenEncryptionKey) !== item.accessToken) {
          return { outcome: "unknown" };
        }
        const count = await connection.query(
          `SELECT count(*)::int AS count FROM plaid_items
            WHERE user_id = $1 AND disconnected_at IS NULL`, [userId]);
        return { outcome: "saved", linkedItemCount: count.rows[0].count };
      }
      if (current || !["dispatch_uncertain", "result_recorded"].includes(entry.state)) {
        return { outcome: "unknown" };
      }
      // The owner lock also serialized with the original save transaction.
      // Once it is acquired, an absent row plus an unmarked lease proves that
      // this attempt did not commit; a failed read instead throws as unknown.
      return { outcome: "not_saved" };
    });
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

  async function removeUserItemIfMatching(userId, expectedItem) {
    if (!expectedItem?.itemId || !expectedItem?.accessToken) return false;
    const connection = await dbPool.connect();
    try {
      await connection.query("BEGIN");
      const result = await connection.query(
        `SELECT id, created_at, encrypted_access_token, access_token_iv,
                access_token_tag FROM plaid_items
          WHERE user_id = $1 AND plaid_item_id = $2
            AND disconnected_at IS NULL FOR UPDATE`,
        [userId, expectedItem.itemId]
      );
      const row = result.rows[0];
      if (!row || new Date(row.created_at).toISOString() !==
          new Date(expectedItem.linkedAt).toISOString() ||
          decryptToken({ ciphertext: row.encrypted_access_token,
            iv: row.access_token_iv, tag: row.access_token_tag },
          tokenEncryptionKey) !== expectedItem.accessToken) {
        await connection.query("ROLLBACK");
        return false;
      }
      await connection.query(
        `UPDATE plaid_items SET disconnected_at = now(), updated_at = now()
          WHERE id = $1 AND disconnected_at IS NULL`, [row.id]
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
    beginItemExchange,
    markItemExchangeDispatched,
    recordItemExchangeResult,
    markItemExchangeRemovalConfirmed,
    getItemExchangeLeases,
    finishItemExchange,
    beginItemRemoval,
    finishItemRemoval,
    getItemLifecycleObligations,
    recordRemovalRecovery,
    clearRemovalRecovery,
    getRemovalRecoveries,
    saveUserItem,
    inspectItemExchangeSave,
    removeUserItem,
    removeUserItemIfMatching,
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
