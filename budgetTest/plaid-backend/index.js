const express = require("express");
console.log("EXPRESS");
const cors = require("cors");
console.log("EXPRESS");
const dotenv = require("dotenv");
console.log("EXPRESS");
const plaid = require("plaid");
console.log("EXPRESS");
dotenv.config();

const app = express();

app.use(cors());
app.use(express.json());

let ACCESS_TOKEN = null;

const configuration = new plaid.Configuration({
  basePath: plaid.PlaidEnvironments.sandbox,
  baseOptions: {
    headers: {
      "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID,
      "PLAID-SECRET": process.env.PLAID_SECRET,
    },
  },
});

const client = new plaid.PlaidApi(configuration);

// Health Check
app.get("/api/health", (req, res) => {
  res.json({ status: "ok" });
});

// Create Link Token
app.post("/api/create_link_token", async (req, res) => {
  try {
    const response = await client.linkTokenCreate({
      user: {
        client_user_id: "test-user",
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
    console.error(
      "Create Link Token Error:",
      error.response?.data || error
    );

    res.status(500).json({
      error: "Failed to create link token",
    });
  }
});

// Exchange Public Token
app.post("/api/exchange_public_token", async (req, res) => {
  try {
    const { public_token } = req.body;

    const response = await client.itemPublicTokenExchange({
      public_token,
    });

    ACCESS_TOKEN = response.data.access_token;

    console.log("✅ Access token stored");

    res.json({
      success: true,
      item_id: response.data.item_id,
    });
  } catch (error) {
    console.error(
      "Exchange Token Error:",
      error.response?.data || error
    );

    res.status(500).json({
      error: "Failed to exchange token",
    });
  }
});

// Get Accounts
app.get("/api/accounts", async (req, res) => {
  try {
    if (!ACCESS_TOKEN) {
      return res.json({
        accounts: [],
      });
    }

    const response = await client.accountsGet({
      access_token: ACCESS_TOKEN,
    });

    res.json(response.data);
  } catch (error) {
    console.error(
      "Accounts Error:",
      error.response?.data || error
    );

    res.status(500).json({
      error: "Failed to fetch accounts",
    });
  }
});

// Get Transactions
app.get("/api/transactions", async (req, res) => {
  try {
    if (!ACCESS_TOKEN) {
      return res.json({
        transactions: [],
      });
    }

    const today = new Date();

    const startDate = new Date();
    startDate.setDate(today.getDate() - 30);

    const response = await client.transactionsGet({
      access_token: ACCESS_TOKEN,
      start_date: startDate.toISOString().split("T")[0],
      end_date: today.toISOString().split("T")[0],
    });

    res.json(response.data);
  } catch (error) {
    console.error(
      "Transactions Error:",
      error.response?.data || error
    );

    res.status(500).json({
      error: "Failed to fetch transactions",
    });
  }
});

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`🚀 Plaid backend running on port ${PORT}`);
});
