const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const fs = require("fs");
const path = require("path");
const plaid = require("plaid");
const {
  getUserItems,
  saveUserItem,
  removeAllUserItems,
} = require("./userItemStore");
dotenv.config();

const app = express();

app.use(cors());
app.use(express.json());

const plaidEnvironmentName = (
  process.env.PLAID_ENV || "sandbox"
).toLowerCase();

const plaidEnvironments = {
  sandbox: plaid.PlaidEnvironments.sandbox,
  development: plaid.PlaidEnvironments.development,
  production: plaid.PlaidEnvironments.production,
};

const activePlaidEnvironment =
  plaidEnvironments[plaidEnvironmentName] ||
  plaid.PlaidEnvironments.sandbox;

const activePlaidEnvironmentName =
  plaidEnvironments[plaidEnvironmentName]
    ? plaidEnvironmentName
    : "sandbox";

const configuredTokenStorePath = process.env.PLAID_TOKEN_STORE_PATH;
const tokenStorePath = configuredTokenStorePath
  ? path.isAbsolute(configuredTokenStorePath)
    ? configuredTokenStorePath
    : path.join(__dirname, configuredTokenStorePath)
  : path.join(__dirname, ".plaid-token-store.json");

const plaidRedirectUri = process.env.PLAID_REDIRECT_URI;
const plaidRedirectUriHost = plaidRedirectUri
  ? (() => {
      try {
        return new URL(plaidRedirectUri).host;
      } catch {
        return "invalid_url";
      }
    })()
  : null;

const appleAppSiteAssociation = {
  applinks: {
    apps: [],
    details: [
      {
        appID: "HT5R7T5J34.com.matthewthomas.caldera",
        paths: ["/plaid/oauth"],
      },
    ],
  },
};

function requireAppApiKey(req, res, next) {
  const configuredApiKey = process.env.APP_API_KEY;

  if (!configuredApiKey) {
    console.warn("Protected Plaid route rejected: APP_API_KEY missing.");

    return res.status(503).json({
      error: "server_not_configured",
      message: "Backend API key is not configured.",
    });
  }

  if (req.get("x-app-api-key") !== configuredApiKey) {
    return res.status(401).json({
      error: "unauthorized",
      message: "Missing or invalid API key.",
    });
  }

  next();
}

function getRequestUserID(req) {
  // Phase A compatibility bridge: all current personal/internal TestFlight
  // requests still resolve to the configured personal user. Future auth
  // middleware will replace this with verified authenticated user identity.
  // Do not accept userId from request body/query/header before real auth.
  return process.env.PLAID_PERSONAL_USER_KEY || "personal";
}

function logPlaidError(context, error) {
  const plaidError = error.response?.data;
  const errorCode = plaidError?.error_code || error.code || "unknown";
  const errorType = plaidError?.error_type || "unknown";
  const status = error.response?.status || "unknown";

  console.error(
    `${context}: status=${status} type=${errorType} code=${errorCode}`
  );
}

function readTokenStore() {
  try {
    if (!fs.existsSync(tokenStorePath)) {
      return {};
    }

    return JSON.parse(
      fs.readFileSync(tokenStorePath, "utf8")
    );
  } catch {
    console.error("Token store read failed.");
    return {};
  }
}

function writeTokenStore(store) {
  fs.writeFileSync(
    tokenStorePath,
    JSON.stringify(store, null, 2),
    {
      mode: 0o600,
    }
  );
}

function withInstitutionMetadata(record, item) {
  return {
    ...record,
    item_id: item.itemId,
    institution_name: item.institutionName,
    institution_id: item.institutionId,
  };
}

function dedupeByID(records, key) {
  const byID = new Map();

  records.forEach((record) => {
    const id = record?.[key];

    if (id) {
      byID.set(id, record);
    }
  });

  return Array.from(byID.values());
}

const configuration = new plaid.Configuration({
  basePath: activePlaidEnvironment,
  baseOptions: {
    headers: {
      "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID,
      "PLAID-SECRET": process.env.PLAID_SECRET,
    },
  },
});

const client = new plaid.PlaidApi(configuration);

console.log(
  `Plaid backend configured for ${activePlaidEnvironmentName}.`
);
console.log(
  `Plaid redirect URI configured: ${Boolean(plaidRedirectUri)} host=${plaidRedirectUriHost || "none"}.`
);

app.get("/.well-known/apple-app-site-association", (req, res) => {
  res
    .type("application/json")
    .send(JSON.stringify(appleAppSiteAssociation));
});

app.get("/plaid/oauth", (req, res) => {
  res
    .type("html")
    .send("<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Return to Caldera</title></head><body><main style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;line-height:1.5;\"><h1>Return to Caldera</h1><p>If Caldera did not reopen automatically, return to the app to finish linking your account.</p></main></body></html>");
});

// Health Check
app.get("/api/health", (req, res) => {
  res.json({
    status: "ok",
    plaid_env: activePlaidEnvironmentName,
    redirect_uri_configured: Boolean(plaidRedirectUri),
    redirect_uri_host: plaidRedirectUriHost,
  });
});

// Create Link Token
app.post("/api/create_link_token", requireAppApiKey, async (req, res) => {
  try {
    const userId = getRequestUserID(req);
    const linkTokenRequest = {
      user: {
        client_user_id: userId,
      },
      client_name: "Caldera",
      products: ["transactions"],
      country_codes: ["US"],
      language: "en",
    };

    if (plaidRedirectUri) {
      linkTokenRequest.redirect_uri = plaidRedirectUri;
    }

    console.log(
      `Creating Plaid link token: redirect_uri_included=${Boolean(linkTokenRequest.redirect_uri)} redirect_uri_host=${plaidRedirectUriHost || "none"}.`
    );

    const response = await client.linkTokenCreate(linkTokenRequest);

    res.json({
      link_token: response.data.link_token,
    });
  } catch (error) {
    logPlaidError("Create Link Token Error", error);

    res.status(500).json({
      error: "Failed to create link token",
    });
  }
});

// Exchange Public Token
app.post("/api/exchange_public_token", requireAppApiKey, async (req, res) => {
  try {
    const {
      public_token,
      institution_name,
      institution_id,
    } = req.body;

    if (!public_token) {
      return res.status(400).json({
        error: "missing_public_token",
        message: "A public token is required.",
      });
    }

    const userId = getRequestUserID(req);
    const response = await client.itemPublicTokenExchange({
      public_token,
    });

    const store = readTokenStore();
    const linkedItemCount = saveUserItem(store, userId, {
      accessToken: response.data.access_token,
      itemId: response.data.item_id,
      institutionName: institution_name,
      institutionId: institution_id,
    });
    writeTokenStore(store);

    console.log(`Plaid item linked. linked_items=${linkedItemCount}`);

    res.json({
      success: true,
      item_id: response.data.item_id,
      linked_items: linkedItemCount,
    });
  } catch (error) {
    logPlaidError("Exchange Token Error", error);

    res.status(500).json({
      error: "Failed to exchange token",
    });
  }
});

// Disconnect Plaid Item
app.post("/api/disconnect", requireAppApiKey, async (req, res) => {
  const userId = getRequestUserID(req);
  const store = readTokenStore();
  const items = getUserItems(store, userId);

  if (items.length === 0) {
    if (store[userId]) {
      removeAllUserItems(store, userId);
      writeTokenStore(store);
    }

    return res.json({
      success: true,
      linked: false,
      removed_items: 0,
      removal_errors: 0,
    });
  }

  let removalErrors = 0;

  for (const item of items) {
    try {
      await client.itemRemove({
        access_token: item.accessToken,
      });
    } catch (error) {
      removalErrors += 1;
      logPlaidError("Disconnect Item Error", error);
    }
  }

  removeAllUserItems(store, userId);
  writeTokenStore(store);

  console.log(
    `Plaid items disconnected. removed_items=${items.length} removal_errors=${removalErrors}`
  );

  res.json({
    success: true,
    linked: false,
    removed_items: items.length,
    removal_errors: removalErrors,
  });
});

// Get Accounts
app.get("/api/accounts", requireAppApiKey, async (req, res) => {
  const userId = getRequestUserID(req);
  const store = readTokenStore();
  const items = getUserItems(store, userId);

  if (items.length === 0) {
    return res.status(409).json({
      error: "not_linked",
      message: "No linked Plaid item found.",
    });
  }

  const accounts = [];
  const itemErrors = [];
  let successfulItems = 0;

  for (const item of items) {
    try {
      const response = await client.accountsGet({
        access_token: item.accessToken,
      });

      successfulItems += 1;

      accounts.push(
        ...response.data.accounts.map((account) =>
          withInstitutionMetadata(account, item)
        )
      );
    } catch (error) {
      itemErrors.push({
        error: "accounts_fetch_failed",
      });
      logPlaidError("Accounts Item Error", error);
    }
  }

  if (successfulItems === 0 && itemErrors.length > 0) {
    return res.status(500).json({
      error: "Failed to fetch accounts",
    });
  }

  res.json({
    accounts: dedupeByID(accounts, "account_id"),
    item_errors: itemErrors,
    partial_failure: itemErrors.length > 0,
  });
});

// Get Transactions
app.get("/api/transactions", requireAppApiKey, async (req, res) => {
  const userId = getRequestUserID(req);
  const store = readTokenStore();
  const items = getUserItems(store, userId);

  if (items.length === 0) {
    return res.status(409).json({
      error: "not_linked",
      message: "No linked Plaid item found.",
    });
  }

  const today = new Date();
  const startDate = new Date();
  startDate.setDate(today.getDate() - 30);

  const transactions = [];
  const accounts = [];
  const itemErrors = [];
  let successfulItems = 0;

  for (const item of items) {
    try {
      const response = await client.transactionsGet({
        access_token: item.accessToken,
        start_date: startDate.toISOString().split("T")[0],
        end_date: today.toISOString().split("T")[0],
      });

      successfulItems += 1;

      transactions.push(
        ...response.data.transactions.map((transaction) =>
          withInstitutionMetadata(transaction, item)
        )
      );

      if (Array.isArray(response.data.accounts)) {
        accounts.push(
          ...response.data.accounts.map((account) =>
            withInstitutionMetadata(account, item)
          )
        );
      }
    } catch (error) {
      itemErrors.push({
        error: "transactions_fetch_failed",
      });
      logPlaidError("Transactions Item Error", error);
    }
  }

  if (successfulItems === 0 && itemErrors.length > 0) {
    return res.status(500).json({
      error: "Failed to fetch transactions",
    });
  }

  res.json({
    transactions: dedupeByID(transactions, "transaction_id"),
    accounts: dedupeByID(accounts, "account_id"),
    item_errors: itemErrors,
    partial_failure: itemErrors.length > 0,
  });
});

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`🚀 Plaid backend running on port ${PORT}`);
});
