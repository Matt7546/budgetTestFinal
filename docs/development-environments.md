# Caldera Development Environments

Caldera separates local development from TestFlight production behavior by build configuration.

## Debug

- iOS build configuration: Debug
- Backend: `http://10.0.0.244:3001`
- Expected Plaid environment: Sandbox
- Use for local development and sandbox bank testing.
- Settings shows a DEBUG-only Environment section with the active backend and expected Plaid environment.

## Release / TestFlight

- iOS build configuration: Release
- Backend: `https://plaid-backend-2wqb.onrender.com`
- Expected Plaid environment: Production
- Release builds do not show environment labels, Developer QA tools, or Plaid diagnostic logs.

## API Key

Both Debug and Release read `APP_API_KEY` from the same Xcode build setting path:

1. Create or update `Config/Secrets.xcconfig`.
2. Add your local value there as `APP_API_KEY = ...`.
3. Keep `Config/Secrets.xcconfig` out of Git. It is intentionally ignored.

Do not hardcode API keys, Plaid client IDs, or Plaid secrets in Swift files or Xcode project files.

## Running the Local Backend

From the backend folder:

```sh
cd plaid-backend
npm install
npm start
```

For local sandbox work, the backend `.env` should use Plaid sandbox credentials and `PLAID_ENV=sandbox`. Render should use production credentials and `PLAID_ENV=production` for TestFlight.
