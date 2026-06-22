const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const fs = require("fs");
const path = require("path");
const plaid = require("plaid");
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

const personalUserKey =
  process.env.PLAID_PERSONAL_USER_KEY || "personal";

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

function getAccessToken() {
  const store = readTokenStore();

  return store[personalUserKey]?.accessToken || null;
}

function saveAccessToken(accessToken) {
  const store = readTokenStore();

  store[personalUserKey] = {
    accessToken,
    updatedAt: new Date().toISOString(),
  };

  writeTokenStore(store);
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

// Health Check
app.get("/api/health", (req, res) => {
  res.json({
    status: "ok",
    plaid_env: activePlaidEnvironmentName,
  });
});

// Create Link Token
app.post("/api/create_link_token", requireAppApiKey, async (req, res) => {
  try {
    const response = await client.linkTokenCreate({
      user: {
        client_user_id: personalUserKey,
      },
      client_name: "BudgetTest",
      products: ["transactions"],
      country_codes: ["US"],
      language: "en",
    });

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
    const { public_token } = req.body;

    if (!public_token) {
      return res.status(400).json({
        error: "missing_public_token",
        message: "A public token is required.",
      });
    }

    const response = await client.itemPublicTokenExchange({
      public_token,
    });

    saveAccessToken(response.data.access_token);

    console.log("Plaid item linked for personal user.");

    res.json({
      success: true,
      item_id: response.data.item_id,
    });
  } catch (error) {
    logPlaidError("Exchange Token Error", error);

    res.status(500).json({
      error: "Failed to exchange token",
    });
  }
});

// Get Accounts
app.get("/api/accounts", requireAppApiKey, async (req, res) => {
  try {
    const accessToken = getAccessToken();

    if (!accessToken) {
      return res.status(409).json({
        error: "not_linked",
        message: "No linked Plaid item found.",
      });
    }

    const response = await client.accountsGet({
      access_token: accessToken,
    });

    res.json(response.data);
  } catch (error) {
    logPlaidError("Accounts Error", error);

    res.status(500).json({
      error: "Failed to fetch accounts",
    });
  }
});

// Get Transactions
app.get("/api/transactions", requireAppApiKey, async (req, res) => {
  try {
    const accessToken = getAccessToken();

    if (!accessToken) {
      return res.status(409).json({
        error: "not_linked",
        message: "No linked Plaid item found.",
      });
    }

    const today = new Date();

    const startDate = new Date();
    startDate.setDate(today.getDate() - 30);

    const response = await client.transactionsGet({
      access_token: accessToken,
      start_date: startDate.toISOString().split("T")[0],
      end_date: today.toISOString().split("T")[0],
    });

    res.json(response.data);
  } catch (error) {
    logPlaidError("Transactions Error", error);

    res.status(500).json({
      error: "Failed to fetch transactions",
    });
  }
});

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`🚀 Plaid backend running on port ${PORT}`);
});
